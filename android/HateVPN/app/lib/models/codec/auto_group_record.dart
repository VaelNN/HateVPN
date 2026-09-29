





























library;

import 'package:collection/collection.dart';

import '../../services/contract/group_genus.dart';
import '../../services/parser/uri_utils.dart' show newUuidV4;
import '../auto_select.dart';
import '../core_reject_verdict.dart'
    show storedWarningsFromJson, storedWarningsToJson;
import '../direction.dart' show StickyHashKey, UrltestMode;
import '../node_link.dart';
import '../node_spec.dart';
import '../server_list.dart';
import 'node_link_record.dart';


const String kNodeKindAuto = 'auto';



const String _kUntaggedAuto = 'Auto';


const Set<String> _autoKeys = {
  'kind', 'tag', 'enabled', 'group', 'members_rule', 'pool_badge',

  'warnings',
};

const Set<String> _groupKeys = {
  'group_type', 'default', 'members', 'strategy', 'members_rule', 'pool_badge',
};

const Set<String> _ruleKeys = {'include', 'exclude'};


const Set<String> _strategyKeys = {
  'mode', 'url', 'interval', 'tolerance', 'idle_timeout',
  'interrupt_exist_connections', 'pool', 'pool_tolerance', 'sticky_hash',
};






Map<String, dynamic> autoGroupMemberToRecord(
  FolderMember m,
  AutoSelectSpec group,
  String folderId,
) {
  final membership = group.membership;
  return {
    'kind': kNodeKindAuto,
    if (group.tag.isNotEmpty) 'tag': group.tag,
    'enabled': m.enabled,
    if (m.warnings.isNotEmpty) 'warnings': storedWarningsToJson(m.warnings),
    'group': {

      'group_type': group.genus,
      if (membership is ExplicitMembers)
        'members': [
          for (final l in membership.members)
            nodeLinkToRecord(
                l.isRoot ? NodeLink(folderId: folderId, tag: l.tag) : l),
        ],

      if (!group.isManual) 'strategy': autoSelectParamsToStrategy(group.params),

      if (membership is RuleMembers)
        'members_rule': {
          'include': membership.include,
          'exclude': membership.exclude,
        },
      if (group.poolBadge != kDefaultPoolBadge) 'pool_badge': group.poolBadge,


      if (group.isManual && group.manualDefault.isNotEmpty)
        'default': nodeLinkToRecord(
            _memberLink(membership, group.manualDefault, folderId)),



      if (!group.isManual && group.manualDefault.isNotEmpty)
        'default': group.manualDefault,
    },
  };
}



NodeLink _memberLink(
    AutoSelectMembership membership, String tag, String folderId) {
  if (membership is ExplicitMembers) {
    for (final l in membership.members) {
      if (l.tag == tag) {
        return l.isRoot ? NodeLink(folderId: folderId, tag: l.tag) : l;
      }
    }
  }
  return NodeLink(folderId: folderId, tag: tag);
}







Map<String, dynamic> autoSelectParamsToStrategy(AutoSelectParams p) {
  const d = AutoSelectParams();
  final rr = p.mode == UrltestMode.roundRobin;
  return {
    'mode': p.mode.wire,
    'url': p.url,
    'interval': p.interval,
    'tolerance': p.tolerance,
    'idle_timeout': p.idleTimeout,
    'interrupt_exist_connections': p.interruptExistConnections,
    if (rr || p.pool != d.pool) 'pool': p.pool,
    if (rr || p.poolTolerance != d.poolTolerance)
      'pool_tolerance': p.poolTolerance,
    if (rr ||
        !const ListEquality<StickyHashKey>().equals(p.stickyHash, d.stickyHash))
      'sticky_hash': p.stickyHash.isEmpty
          ? ['none']
          : [for (final k in p.stickyHash) k.wire],
  };
}





typedef AutoGroupRead = ({FolderMember member});





AutoGroupRead autoGroupMemberFromRecord(
  Map<String, dynamic> j, {
  required String folderId,
  required String where,
  List<String>? notes,
  List<String>? unknown,
  String path = '',
}) {
  _collectUnknown(j, _autoKeys, path, unknown);

  final rawTag = j['tag'];
  var tag = rawTag is String ? rawTag.trim() : '';
  if (tag.isEmpty) {
    notes?.add('$where: auto node without tag, named "$_kUntaggedAuto"');
    tag = _kUntaggedAuto;
  }

  final rawGroup = j['group'];
  final group = rawGroup is Map
      ? rawGroup.cast<String, dynamic>()
      : const <String, dynamic>{};
  if (rawGroup is! Map) {
    notes?.add('$where: auto node without group, read with no members');
  }
  _collectUnknown(group, _groupKeys, '${path}group.', unknown);



  final type = group['group_type'];
  final String genus;
  if (type is String && GroupGenus.isKnown(type)) {
    genus = type;
  } else {
    genus = GroupGenus.auto;
    if (type != null) {
      notes?.add('$where: group_type "$type" is read as ${GroupGenus.auto}');
    }
  }

  final links = <NodeLink>[];
  final rawMembers = group['members'];
  if (rawMembers is List) {
    for (var i = 0; i < rawMembers.length; i++) {
      final link = nodeLinkFromRecord(rawMembers[i]);
      if (link == null || link.tag.isEmpty) {
        notes?.add('$where: group.members[$i] is not a link, dropped');
        continue;
      }

      links.add(link.isRoot ? NodeLink(folderId: folderId, tag: link.tag) : link);
    }
  }




  final rawDefault = group['default'];
  var manualDefault = '';
  if (rawDefault != null) {
    final def = _defaultLink(rawDefault, links, folderId);
    manualDefault = def?.tag ?? (rawDefault is String ? rawDefault : '');
  }


  final inGroup = group.containsKey('members_rule');
  final rule = inGroup ? group['members_rule'] : j['members_rule'];
  final AutoSelectMembership membership;
  if (rule is Map && links.isEmpty) {
    _collectUnknown(rule, _ruleKeys,
        '$path${inGroup ? 'group.' : ''}members_rule.', unknown);
    membership = RuleMembers(
      include: rule['include'] is String ? rule['include'] as String : '',
      exclude: rule['exclude'] is String ? rule['exclude'] as String : '',
    );
  } else {
    if (rule is Map) {
      notes?.add('$where: group.members wins, members_rule ignored');
    }
    membership = ExplicitMembers(links);
  }

  final strategy = group['strategy'];
  if (strategy is Map) {
    _collectUnknown(strategy, _strategyKeys, '${path}group.strategy.', unknown);
  }
  final badge =
      group.containsKey('pool_badge') ? group['pool_badge'] : j['pool_badge'];
  final enabled = j['enabled'];

  return (
    member: FolderMember.auto(
      AutoSelectSpec(
        id: newUuidV4(),
        tag: tag,
        label: tag,
        membership: membership,
        params: autoSelectParamsFromStrategy(strategy),
        poolBadge: badge is String ? badge : kDefaultPoolBadge,
        manualDefault: manualDefault,
        genus: genus,
      ),
      enabled: enabled is bool ? enabled : true,
      warnings: storedWarningsFromJson(j['warnings']),
    ),
  );
}



AutoSelectParams autoSelectParamsFromStrategy(Object? raw) {
  const d = AutoSelectParams();
  if (raw is! Map) return d;
  String str(String key, String fallback) {
    final v = raw[key];
    return v is String ? v : fallback;
  }

  int integer(String key, int fallback) {
    final v = raw[key];
    return v is num ? v.toInt() : fallback;
  }

  final sticky = raw['sticky_hash'];
  final interrupt = raw['interrupt_exist_connections'];
  final mode = raw['mode'];
  return AutoSelectParams(
    mode: UrltestMode.fromWire(mode is String ? mode : null),
    url: str('url', d.url),
    interval: str('interval', d.interval),
    tolerance: integer('tolerance', d.tolerance),
    idleTimeout: str('idle_timeout', d.idleTimeout),
    interruptExistConnections:
        interrupt is bool ? interrupt : d.interruptExistConnections,
    pool: integer('pool', d.pool),
    poolTolerance:
        clampPoolTolerance(integer('pool_tolerance', d.poolTolerance)),
    stickyHash: sticky is List
        ? (sticky.contains('none')
            ? const <StickyHashKey>[]
            : [
                for (final k in sticky)
                  ?StickyHashKey.fromWire(k is String ? k : null),
              ])
        : d.stickyHash,
  );
}



NodeLink? _defaultLink(Object? raw, List<NodeLink> members, String folderId) {
  if (raw is String) {
    if (raw.isEmpty) return null;
    final hits = members.where((l) => l.tag == raw).toList();
    return hits.length == 1 ? hits.single : NodeLink(tag: raw);
  }
  final link = nodeLinkFromRecord(raw);
  if (link == null || link.tag.isEmpty) return null;
  return link.isRoot ? NodeLink(folderId: folderId, tag: link.tag) : link;
}

void _collectUnknown(
  Map<dynamic, dynamic> j,
  Set<String> known,
  String prefix,
  List<String>? out,
) {
  if (out == null) return;
  for (final k in j.keys) {
    if (!known.contains(k)) out.add('$prefix$k');
  }
}
