








library;

import '../../config/consts.dart';
import '../../models/direction.dart';
import '../../models/emit_context.dart';
import '../../models/node_link.dart';
import '../../models/server_list.dart';
import '../../models/singbox_entry.dart';
import '../../models/template_vars.dart';
import '../tag_resolver.dart';
import 'node_link_resolve.dart';
import 'rule_set_registry.dart';
import 'server_list_build.dart';
import 'source_replace_build.dart' show ReplacePlan;



NodeLinkTargets computeNodeLinkPool(
  List<ServerList> lists, {
  List<Direction> directions = const [],
}) {
  final targets = NodeLinkTargets()
    ..addRootNames([
      kDirectOutboundTag,
      kBlockOutboundTag,
      for (final d in directions) ...[d.tag, d.autoTag],

      ...sourceReplaceNames(lists),
    ]);
  for (final l in lists) {
    if (l is! UserServer) targets.noteContainer(l.id, l.name);
  }
  final ctx = _PoolCtx(targets, [
    for (final d in directions) ...[d.tag, d.autoTag],
    ...sourceReplaceNames(lists),
  ]);
  for (final l in lists) {
    try {
      l.build(ctx);
    } catch (_) {


    }
  }
  return targets;
}











List<NodeLinkTargets> computeDisabledNodeLinkPools(
  List<ServerList> lists, {
  List<Direction> directions = const [],
}) {
  final reserved = [
    for (final d in directions) ...[d.tag, d.autoTag],
  ];
  final live = _PoolCtx(NodeLinkTargets(), reserved);
  final out = <NodeLinkTargets>[];
  for (final l in lists) {
    final whole = _enabledWhole(l);
    if (whole != null) {
      final targets = NodeLinkTargets();
      _buildQuiet(whole, _PoolCtx(targets, live._taken));
      out.add(targets);
    }
    _buildQuiet(l, live);
  }
  return out;
}


ServerList? _enabledWhole(ServerList l) => switch (l) {
      SubscriptionServers s when !s.enabled || s.disabledHashes.isNotEmpty =>
        s.copyWith(enabled: true, disabledHashes: const {}),
      UserServer u when !u.enabled => u.copyWith(enabled: true),
      FolderServers f when !f.enabled || f.members.any((m) => !m.enabled) =>
        f.copyWith(enabled: true, members: [
          for (final m in f.members) m.enabled ? m : m.copyWith(enabled: true),
        ]),
      _ => null,
    };

void _buildQuiet(ServerList l, EmitContext ctx) {
  try {
    l.build(ctx);
  } catch (_) {

  }
}




String nodeLinkDisplay(
  NodeLink link,
  NodeLinkTargets? pool, {
  List<ServerList> lists = const [],
}) {
  if (link.isEmpty) return '';
  final known = pool?.finalOf(link);
  if (known != null) return known;
  if (!link.isRoot) {
    for (final l in lists) {
      if (l.id == link.folderId) {
        return TagResolver.displayTag(l.tagPrefix, link.tag);
      }
    }
  }
  return link.tag;
}

class _PoolCtx implements EmitContext {
  _PoolCtx(this.linkTargets, Iterable<String> reserved) {
    _taken.addAll(reserved);
  }

  @override
  final NodeLinkTargets linkTargets;


  final _taken = <String>{kDirectOutboundTag, 'dns-out', 'block-out'};
  final _ruleSets = RuleSetRegistry();

  @override
  TemplateVars get vars => TemplateVars.empty;

  @override
  RuleSetRegistry get ruleSets => _ruleSets;

  @override
  bool get passiveCheck => false;

  @override
  String get coreVersion => '';

  @override
  String allocateTag(String baseTag) {
    if (_taken.add(baseTag)) return baseTag;
    for (var i = 1; i < 100000; i++) {
      final c = '$baseTag-$i';
      if (_taken.add(c)) return c;
    }
    return baseTag;
  }

  @override
  void addEntry(SingboxEntry entry) {}

  @override
  void addToSelectorTagList(SingboxEntry entry) {}

  @override
  void addToAutoList(SingboxEntry entry) {}

  @override
  void addReplacePlan(ReplacePlan plan) {}

  @override
  bool isReplaceBlocked(String listId) => false;

  @override
  void noteEmitted(node, String finalTag) {}

  @override
  void noteEmittedAlias(String finalTag, node) {}

  @override
  void warn(String line) {}

  @override
  void deferDetour(DeferredDetour detour) {}
}
