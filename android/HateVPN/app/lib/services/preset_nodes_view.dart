











library;

import '../models/custom_rule.dart';
import '../models/node_spec.dart';
import '../models/parser_config.dart';
import '../models/server_list.dart';
import '../models/template_vars.dart';
import 'builder/preset_expand.dart';
import 'l10n/locale_controller.dart';
import 'node_hash.dart';
import 'tag_resolver.dart';


Set<String> forEachNodeTypes(Iterable<SelectableRule> presets) => {
      for (final p in presets)
        if (p.forEach case final PresetForEach fe) fe.nodeType,
    };




List<PresetNode> presetNodesForView(
  List<ServerList> lists, {
  required Set<String> nodeTypes,
  Map<String, NodeSpec> lastEmittedTagMap = const {},
}) {
  if (nodeTypes.isEmpty) return const [];


  final finalTagOf = Map<NodeSpec, String>.identity();
  for (final e in lastEmittedTagMap.entries) {
    finalTagOf.putIfAbsent(e.value, () => e.key);
  }
  final out = <PresetNode>[];
  void add(NodeSpec node, String tagPrefix, bool skip) {
    if (!nodeTypes.contains(node.protocol)) return;
    final Map<String, dynamic> body;
    try {
      body = node.emit(TemplateVars.empty).map;
    } catch (_) {
      return;
    }
    if (!nodeTypes.contains(body['type'])) return;
    out.add(PresetNode(
      tag: finalTagOf[node] ?? TagResolver.displayTag(tagPrefix, node.tag),
      body: body,
      skipPresets: skip,
    ));
  }

  for (final list in lists) {
    if (!list.enabled) continue;
    switch (list) {
      case UserServer u:
        for (final n in u.nodes) {
          add(n, u.tagPrefix, u.skipPresets);
        }
      case FolderServers f:
        for (final m in f.members) {
          final node = m.node;
          if (!m.enabled || node == null) continue;
          add(node, f.tagPrefix, m.skipPresets);
        }
      case SubscriptionServers s:
        final identities =
            s.disabledHashes.isEmpty ? null : sourceNodeIdentities(s.nodes);
        for (final n in s.nodes) {
          final id = identities?[n];
          if (id != null && s.disabledHashes.containsKey(id)) continue;
          add(n, s.tagPrefix, false);
        }
    }
  }
  return out;
}



List<String>? presetServedTags(
  CustomRulePreset rule,
  SelectableRule preset,
  List<PresetNode> nodes, {
  Map<String, String> globalVars = const {},
}) {
  if (preset.forEach == null) return null;
  return [
    for (final n
        in presetForEachNodes(rule, preset, nodes, globalVars: globalVars))
      n.tag,
  ];
}



String presetServedNodesLabel(List<String> tags) => tags.isEmpty
    ? getLocalText.s("No matching nodes")
    : tags.join(', ');





bool skipPresetsToggleVisible({
  required ServerList list,
  required bool isMember,
  required String nodeType,
  required Iterable<SelectableRule> presets,
}) {
  final hasRecord = switch (list) {
    UserServer() => true,
    FolderServers() => isMember,
    SubscriptionServers() => false,
  };
  if (!hasRecord || nodeType.isEmpty) return false;
  return forEachNodeTypes(presets).contains(nodeType);
}
