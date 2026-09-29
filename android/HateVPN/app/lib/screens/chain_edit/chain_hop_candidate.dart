













import '../../models/node_link.dart';


enum ChainHopKind {

  node,


  group,


  direction,



  chain,


  builtin,


  unknown,


  pending,
}


class ChainHopCandidate {
  const ChainHopCandidate({
    required this.tag,
    required this.kind,
    this.below = false,
    this.body,
    this.detour = false,
    this.outboundType = '',
    this.masqueVhttp = '',
    this.offered = true,
    this.displayLabel = '',
    this.subline = '',
    this.link,
  });



  final NodeLink? link;


  NodeLink get address => link ?? NodeLink(tag: tag);



  final String displayLabel;



  final String subline;


  final String tag;

  final ChainHopKind kind;







  final bool below;




  final Map<String, dynamic>? body;



  final bool detour;




  final String outboundType;






  final bool offered;





  final String masqueVhttp;
}


Map<String, ChainHopCandidate> chainHopLookup(
        Iterable<ChainHopCandidate> cands) =>
    {for (final c in cands) c.tag: c};











ChainHopCandidate describeChainHop(
  String tag,
  Map<String, ChainHopCandidate> lookup, {
  required bool targetsKnown,
}) {
  final found = lookup[tag];
  if (found != null) return found;
  return ChainHopCandidate(
    tag: tag,
    kind: targetsKnown ? ChainHopKind.unknown : ChainHopKind.pending,
  );
}
