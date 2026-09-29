










library;

import 'dart:convert';

import '../../models/auto_select.dart';
import '../../models/node_link.dart';
import '../../models/node_spec.dart';
import '../../models/node_warning.dart';
import '../node_hash.dart';
import '../contract/body_edit.dart' show settleSanitized;
import '../contract/body_sanitizer.dart';
import '../contract/group_genus.dart';
import '../contract/registry.dart';
import '../node_identity.dart';
import 'authored_scope.dart'
    show parsingAuthoredBody, parsingOwnSource, singboxBodySource;
import 'json_parsers.dart';
import 'uri_utils.dart';




export 'uri_utils.dart' show kMaxDetourDepth;







const _kSingboxServiceTypes = {'direct', 'block', 'dns'};



bool _isGroupType(String type) => GroupGenus.isKnown(type);













List<NodeSpec> parseSingboxConfigs(List<Map<String, dynamic>> configs,
    {List<NodeWarning>? dropped}) {
  if (configs.isEmpty) return const [];




  final seen = <String>{};




  final synonyms = <String, String>{};









  final indexed = configs.asMap().entries.toList()
    ..sort((a, b) {
      final byPayload = _payloadCount(a.value).compareTo(_payloadCount(b.value));
      return byPayload != 0 ? byPayload : a.key.compareTo(b.key);
    });

  final owner = <String, Map<String, dynamic>>{};
  for (final e in indexed) {
    final before = seen.toSet();
    _parseOne(e.value,
        seen: seen,
        synonyms: synonyms,
        pendingGroups: Map<AutoSelectSpec, _GroupRefs>.identity());
    for (final id in seen.difference(before)) {
      owner[id] = e.value;
    }
  }




  final result = <NodeSpec>[];
  final groups = Map<AutoSelectSpec, _GroupRefs>.identity();
  for (final cfg in configs) {
    result.addAll(_parseOne(
      cfg,


      seen: <String>{},
      synonyms: synonyms,
      ownedBy: (sig) => identical(owner[sig], cfg),
      pendingGroups: groups,
      dropped: dropped,
    ));
  }
  return _bindGroupMembers(result, groups);
}






typedef _GroupRefs = ({List<Object> refs, int lost, Object? def});









List<NodeSpec> _bindGroupMembers(
  List<NodeSpec> nodes,
  Map<AutoSelectSpec, _GroupRefs> groups,
) {
  if (groups.isEmpty) return nodes;
  final rawTags = sourceNodeRawTags(nodes);
  final byKey = <String, NodeSpec>{};
  for (final n in nodes) {
    if (n.isGroup) continue;
    final key = nodeIdentityKey(n);
    if (key != null) byKey[key] = n;
  }
  final out = <NodeSpec>[];
  for (final n in nodes) {
    final pending = n is AutoSelectSpec ? groups[n] : null;
    if (n is! AutoSelectSpec || pending == null) {
      out.add(n);
      continue;
    }
    final links = <NodeLink>[];
    var lost = pending.lost;
    for (final ref in pending.refs) {
      final node = ref is NodeSpec ? ref : byKey[ref];
      final raw = node == null ? null : rawTags[node];
      if (raw == null) {
        lost++;
        continue;
      }
      final link = NodeLink(tag: raw);
      if (!links.contains(link)) links.add(link);
    }
    if (lost > 0) n.warnings.add(GroupMemberMissingWarning(lost));

    if (links.isEmpty) continue;



    final defRef = pending.def;
    final defNode = defRef is NodeSpec
        ? defRef
        : (defRef == null ? null : byKey[defRef]);
    final defRaw = defNode == null ? null : rawTags[defNode];
    out.add(n.copyWith(
      membership: ExplicitMembers(links),
      manualDefault: defRaw ?? n.manualDefault,
    )..sourceExtended = n.sourceExtended);
  }
  return out;
}



int _payloadCount(Map<String, dynamic> config) {
  var n = 0;
  for (final o in _allEntries(config)) {
    final type = o['type']?.toString() ?? '';
    if (_kSingboxServiceTypes.contains(type)) continue;
    if (_isGroupType(type)) continue;
    n++;
  }
  return n;
}






List<Map<String, dynamic>> _allEntries(Map<String, dynamic> config) {
  final out = <Map<String, dynamic>>[];
  for (final key in const ['outbounds', 'endpoints']) {
    final raw = config[key];
    if (raw is List) out.addAll(raw.whereType<Map<String, dynamic>>());
  }
  return out;
}


List<NodeSpec> _parseOne(
  Map<String, dynamic> config, {
  required Set<String> seen,
  required Map<String, String> synonyms,
  required Map<AutoSelectSpec, _GroupRefs> pendingGroups,
  bool Function(String signature)? ownedBy,
  List<NodeWarning>? dropped,
}) {
  final entries = _allEntries(config);
  if (entries.isEmpty) return const [];


  final byTag = <String, Map<String, dynamic>>{};
  for (final e in entries) {
    final tag = e['tag']?.toString() ?? '';
    if (tag.isNotEmpty) byTag.putIfAbsent(tag, () => e);
  }





  final brokenEdges = _findCycleEdges(entries, byTag);




  final detourTargets = <String>{};
  for (final e in entries) {
    final tag = e['tag']?.toString() ?? '';
    final d = e['detour'];
    if (d is! String || d.isEmpty) continue;
    if (brokenEdges.contains(tag)) continue;
    detourTargets.add(d);
  }

  final extended = _prettyJson(config);


  final candidates = <Map<String, dynamic>>[];
  final groups = <Map<String, dynamic>>[];
  for (final e in entries) {
    final type = e['type']?.toString() ?? '';
    if (_kSingboxServiceTypes.contains(type)) continue;
    if (_isGroupType(type)) {
      groups.add(e);
      continue;
    }
    final tag = e['tag']?.toString() ?? '';
    if (tag.isNotEmpty && detourTargets.contains(tag)) continue;
    candidates.add(e);
  }




  final tagUses = <String, int>{};
  for (final e in candidates) {
    final t = e['tag']?.toString().trim() ?? '';
    if (t.isNotEmpty) tagUses[t] = (tagUses[t] ?? 0) + 1;
  }



  final nodeByTag = <String, NodeSpec>{};
  final result = <NodeSpec>[];

  for (var i = 0; i < candidates.length; i++) {
    final ob = candidates[i];
    final rawTag = ob['tag']?.toString().trim() ?? '';
    try {

      final compact = _prettyJson(ob);
      final label = _entryLabel(tag: rawTag, index: i, tagUses: tagUses);
      final spec = parseSingboxEntry(
            _sanitizedEntry(_withLabel(ob, label)),
            rawSource: compact,
            sanitizedFrom: BodySource.singbox,
          ) ??
          _ownUnknownTypeNode(ob, label: label, rawSource: compact);
      if (spec == null) {


        final type = ob['type']?.toString() ?? '';
        dropped?.add(RegistryWarning(
          code: 'protocol_unsupported',
          params: {if (type.isNotEmpty) 'scheme': type},
          ownerTag: rawTag,
        ));
        continue;
      }





      final identity = nodeIdentityKey(spec);
      if (identity != null && rawTag.isNotEmpty) synonyms[rawTag] = identity;



      final chained = _buildChain(ob, byTag, spec.warnings);
      final node = chained == null ? spec : withChained(spec, chained);







      final signature = nodeDedupSignature(node);


      if (ownedBy != null && !ownedBy(signature)) continue;
      if (seen.contains(signature)) continue;
      seen.add(signature);



      node.sourceExtended = extended == compact ? null : extended;

      if (rawTag.isNotEmpty) nodeByTag[rawTag] = node;
      result.add(node);
    } catch (_) {




      dropped?.add(
          RegistryWarning(code: 'form_unrecognized', ownerTag: rawTag));
    }
  }



  for (final g in groups) {
    final spec = _groupToSpec(g, nodeByTag, synonyms, pendingGroups);
    if (spec != null) result.add(spec..sourceExtended = extended);
  }



  return result;
}












NodeSpec? _ownUnknownTypeNode(
  Map<String, dynamic> ob, {
  required String label,
  required String rawSource,
}) {
  final type = ob['type'];
  if (type is! String || type.trim().isEmpty) return null;
  if (isAppKnownSingboxType(type)) return null;


  final known = ContractRegistry.I.isUncheckedType(type);
  if (!known && !parsingOwnSource) return null;
  final tag = label.isNotEmpty ? label : type;
  final server = ob['server'];
  final port = ob['server_port'];
  return UnknownTypeSpec(
    id: newUuidV4(),
    tag: tag,
    label: tag,
    type: type,
    body: ob,
    server: server is String ? server : '',
    port: port is num ? port.toInt() : 0,
    rawSource: rawSource,
    warnings: known ? [] : [UnknownNodeTypeWarning(type)],
  );
}










String _entryLabel({
  required String tag,
  required int index,
  required Map<String, int> tagUses,
}) {
  if (tag.isEmpty) return '';

  if ((tagUses[tag] ?? 0) > 1) return '$tag ${index + 1}';
  return tag;
}






Map<String, dynamic> _withLabel(Map<String, dynamic> entry, String label) {
  if (label.isEmpty || label == entry['tag']?.toString()) return entry;
  return {...entry, 'tag': label};
}










Set<String> _findCycleEdges(
  List<Map<String, dynamic>> entries,
  Map<String, Map<String, dynamic>> byTag,
) {
  final broken = <String>{};

  final settled = <String>{};

  for (final start in entries) {
    final startTag = start['tag']?.toString() ?? '';
    if (startTag.isEmpty || settled.contains(startTag)) continue;

    final path = <String>{};
    var current = start;
    var tag = startTag;
    while (true) {
      path.add(tag);
      settled.add(tag);
      final d = current['detour'];
      if (d is! String || d.isEmpty) break;
      if (path.contains(d)) {
        broken.add(tag);
        break;
      }
      final next = byTag[d];
      if (next == null) break;
      current = next;
      tag = d;
    }
  }
  return broken;
}






NodeSpec? _buildChain(
  Map<String, dynamic> owner,
  Map<String, Map<String, dynamic>> byTag,
  List<NodeWarning> warnings,
) {


  final visited = <String>{};
  final ownerTag = owner['tag']?.toString() ?? '';
  if (ownerTag.isNotEmpty) visited.add(ownerTag);

  NodeSpec? build(Map<String, dynamic> node, int depth) {
    final raw = node['detour'];
    if (raw is! String || raw.isEmpty) return null;


    if (depth >= kMaxDetourDepth) {
      warnings.add(const DetourChainTooDeepWarning(kMaxDetourDepth));
      return null;
    }



    if (visited.contains(raw)) {
      warnings.add(DetourCycleBrokenWarning(raw));
      return null;
    }

    final target = byTag[raw];

    if (target == null) {
      warnings.add(DetourTargetMissingWarning(raw));
      return null;
    }



    final type = target['type']?.toString() ?? '';
    if (_isGroupType(type)) {
      warnings.add(DetourToGroupWarning(raw));
      return null;
    }
    if (_kSingboxServiceTypes.contains(type)) {


      return null;
    }

    visited.add(raw);
    final NodeSpec? spec;
    try {
      spec = parseSingboxEntry(
        _sanitizedEntry(target),
        rawSource: _prettyJson(target),
        sanitizedFrom: BodySource.singbox,
      );
    } catch (_) {

      warnings.add(DetourTargetMissingWarning(raw));
      return null;
    }
    if (spec == null) {
      warnings.add(DetourTargetMissingWarning(raw));
      return null;
    }

    final next = build(target, depth + 1);
    return next == null ? spec : withChained(spec, next);
  }

  return build(owner, 0);
}








AutoSelectSpec? _groupToSpec(
  Map<String, dynamic> group,
  Map<String, NodeSpec> nodeByTag,
  Map<String, String> synonyms,
  Map<AutoSelectSpec, _GroupRefs> groups,
) {
  final warnings = <NodeWarning>[];
  final type = group['type']?.toString() ?? '';



  final genus = GroupGenus.resolve(kGenusSourceSingbox, type) ?? GroupGenus.auto;




  final rawMembers = group['outbounds'];
  final memberTags = rawMembers is List
      ? rawMembers.map((e) => '$e').where((e) => e.isNotEmpty).toList()
      : const <String>[];

  final keys = <String>[];
  final refs = <Object>[];
  var lost = 0;
  final rawDefault = group['default']?.toString() ?? '';
  Object? def;
  for (final tag in memberTags) {


    final node = nodeByTag[tag];
    final key = node != null ? nodeIdentityKey(node) : synonyms[tag];


    if (key == null) {
      lost++;
      continue;
    }
    if (tag == rawDefault) def ??= node ?? key;
    if (keys.contains(key)) continue;
    keys.add(key);
    refs.add(node ?? key);
  }
  if (keys.isEmpty) {
    if (lost > 0) warnings.add(GroupMemberMissingWarning(lost));
    return null;
  }

  final label = group['tag']?.toString() ?? '';
  const d = AutoSelectParams();
  final params = AutoSelectParams(


    url: group['url']?.toString() ?? d.url,
    interval: group['interval']?.toString() ?? d.interval,
    tolerance: _asInt(group['tolerance']) ?? d.tolerance,
    idleTimeout: group['idle_timeout']?.toString() ?? d.idleTimeout,
    interruptExistConnections:
        group['interrupt_exist_connections'] == true,



    mode: d.mode,
  );

  final spec = AutoSelectSpec(
    id: newUuidV4(),
    tag: tagFromLabel(label, 'urltest', 'auto', 0),
    label: label,


    membership: const ExplicitMembers([]),
    params: params,
    genus: genus,

    sourceParamKeys: {
      for (final k in params.toJson().keys)
        if (group.containsKey(k)) k,
    },


    manualDefault: group['default']?.toString() ?? '',
    warnings: warnings,
    rawSource: _prettyJson(group),
  );
  groups[spec] = (refs: refs, lost: lost, def: def);
  return spec;
}


int? _asInt(Object? v) => switch (v) {
      final num n => n.toInt(),
      final String s => int.tryParse(s.trim()),
      _ => null,
    };

















Map<String, dynamic> _sanitizedEntry(Map<String, dynamic> entry) {
  if (!ContractRegistry.I.isLoaded) return entry;
  final type = entry['type'];
  if (type is! String || type.isEmpty) return entry;
  final Map<String, dynamic> copy;
  try {
    copy = (jsonDecode(jsonEncode(entry)) as Map).cast<String, dynamic>();
  } catch (_) {
    return entry;
  }


  final res = settleSanitized(
    type,
    entry,
    RegistrySanitizer.sanitize(
      copy,
      scheme: type,
      coreVersion: '0.0.0',
      applyCoreGates: false,

      source: singboxBodySource,
    ),
    authored: parsingAuthoredBody,
  );
  return res.body ?? entry;
}


String _prettyJson(Object? value) {
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    return value.toString();
  }
}
