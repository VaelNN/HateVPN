










import '../../models/node_spec.dart';
import '../../models/server_list.dart';
import '../preset_nodes_view.dart';





final class TailscaleEndpointOption {
  const TailscaleEndpointOption({required this.tag, required this.enabled});
  final String tag;
  final bool enabled;
}


const String kTailscaleNodeType = 'tailscale';





List<TailscaleEndpointOption> collectTailscaleEndpointOptions(
  List<ServerList> lists, {
  Map<String, NodeSpec> lastEmittedTagMap = const {},
}) {
  final seen = <String>{};
  return [
    for (final n in presetNodesForView(
      lists,
      nodeTypes: const {kTailscaleNodeType},
      lastEmittedTagMap: lastEmittedTagMap,
    ))
      if (seen.add(n.tag)) TailscaleEndpointOption(tag: n.tag, enabled: true),
  ];
}
