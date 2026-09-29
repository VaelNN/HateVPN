














import '../../models/config_node.dart';
import '../../models/direction.dart';
import '../../models/source_chain.dart';
import '../../services/builder/node_link_resolve.dart';
import 'chain_hop_candidate.dart';



const String kChainBuiltinDirect = 'direct-out';


















List<ChainHopCandidate> collectChainHopTargets({
  required ParsedConfig config,
  required List<Direction> directions,
  required List<SourceChain> chains,
  required String selfTag,
  NodeLinkTargets? pool,
}) {
  final seen = <String>{};
  final out = <ChainHopCandidate>[];

  void add(ChainHopCandidate c) {
    final tag = c.tag.trim();
    if (tag.isEmpty || tag == selfTag || !seen.add(tag)) return;
    out.add(c);
  }




  for (final d in directions) {
    if (!d.enabled) continue;



    add(ChainHopCandidate(
        tag: d.tag,
        kind: ChainHopKind.direction,
        offered: d.isDetour,
        displayLabel: d.displayLabel,
        subline: d.tag));
  }




  add(const ChainHopCandidate(
      tag: kChainBuiltinDirect, kind: ChainHopKind.builtin, offered: false));




  var belowSelf = false;
  for (final c in chains) {
    if (c.tag == selfTag) {
      belowSelf = true;
      continue;
    }
    if (!c.enabled) continue;
    add(ChainHopCandidate(
      tag: c.tag,
      kind: ChainHopKind.chain,
        offered: false,
      below: belowSelf,
    
        displayLabel: c.displayLabel,
        subline: '${c.hops.length}',));
  }




  final nodes = <ChainHopCandidate>[];
  for (final n in config.byTag.values) {
    if (n.tag == selfTag || seen.contains(n.tag)) continue;
    if (n.type == 'direct' || n.type == 'block' || n.type == 'dns') continue;


    if (n.type == kChainOutboundType) continue;
    final isGroup = n.type == 'selector' || n.type == 'urltest';
    nodes.add(ChainHopCandidate(
      tag: n.tag,
      kind: isGroup ? ChainHopKind.group : ChainHopKind.node,


      body: isGroup ? null : n.raw,
      detour: (n.detour ?? '').isNotEmpty,
      outboundType: n.type,


      masqueVhttp: n.type == 'masque' ? (n.transportLabel ?? 'h3') : '',
      subline: _nodeSubline(n, isGroup: isGroup),
      offered: !isGroup,
      link: pool?.linkOfFinal(n.tag),
    ));
  }
  nodes.sort((a, b) => a.tag.compareTo(b.tag));
  for (final n in nodes) {
    add(n);
  }

  return out;
}






bool chainTargetsKnown(ParsedConfig config) => config.byTag.isNotEmpty;




String _nodeSubline(ConfigNode n, {required bool isGroup}) {
  if (isGroup) {
    final members = n.raw['outbounds'];
    final count = members is List ? members.length : 0;
    return '${n.type} · $count';
  }
  final server = n.raw['server'];
  final port = n.raw['server_port'];
  final addr = (server is String && server.isNotEmpty)
      ? (port == null ? server : '$server:$port')
      : '';
  return [n.type.toUpperCase(), if (addr.isNotEmpty) addr].join(' · ');
}
