

















import 'package:collection/collection.dart';

import '../services/contract/chain_strip.dart'
    show chainStripKeyKnown, chainStripKeys, orderedChainStrip;
import '../services/json_clone.dart' show deepCloneJson;
import 'codec/node_link_record.dart' show nodeLinkToRecord;
import 'node_link.dart';



const String kChainOutboundType = 'chain';













class SourceChain {
  const SourceChain({
    required this.tag,
    this.label = '',
    this.enabled = true,
    this.hops = const [],
    this.idleTimeout = '',
    this.stripEvasion,
    this.strip = const {},
    this.rewrite = const {},
  });




  final String tag;


  final String label;





  final bool enabled;




















  final List<NodeLink> hops;



  final String idleTimeout;









  final bool? stripEvasion;



  final Map<String, bool> strip;








  final Map<String, dynamic> rewrite;



  String get displayLabel => label.isNotEmpty ? label : tag;


  bool get stripEvasionEnabled => stripEvasion ?? true;

  SourceChain copyWith({
    String? label,
    bool? enabled,
    List<NodeLink>? hops,
    String? idleTimeout,
    bool? stripEvasion,
    bool clearStripEvasion = false,
    Map<String, bool>? strip,
    Map<String, dynamic>? rewrite,
  }) =>
      SourceChain(
        tag: tag,
        label: label ?? this.label,
        enabled: enabled ?? this.enabled,
        hops: hops ?? this.hops,
        idleTimeout: idleTimeout ?? this.idleTimeout,
        stripEvasion:
            clearStripEvasion ? null : (stripEvasion ?? this.stripEvasion),
        strip: strip ?? this.strip,
        rewrite: rewrite ?? this.rewrite,
      );







  Map<String, dynamic> toCanonJson() => {
        'hops': [for (final h in hops) nodeLinkToRecord(h)],
        if (idleTimeout.isNotEmpty) 'idle_timeout': idleTimeout,
        if (stripEvasion != null) 'strip_evasion': stripEvasion,
        if (strip.isNotEmpty) 'strip': orderedChainStrip(strip),
        if (rewrite.isNotEmpty) 'rewrite': deepCloneJson(rewrite),
      };

  static const _eq = DeepCollectionEquality();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SourceChain &&
          tag == other.tag &&
          label == other.label &&
          enabled == other.enabled &&
          _eq.equals(hops, other.hops) &&
          idleTimeout == other.idleTimeout &&
          stripEvasion == other.stripEvasion &&
          _eq.equals(strip, other.strip) &&
          _eq.equals(rewrite, other.rewrite));

  @override
  int get hashCode => Object.hash(tag, label, enabled, _eq.hash(hops),
      idleTimeout, stripEvasion, _eq.hash(strip), _eq.hash(rewrite));
}










typedef ChainHealResult = ({
  List<SourceChain> chains,
  int positions,
  List<String> touched,
});





















ChainHealResult clearChainHopRefs(
  List<SourceChain> chains,
  String deletedTag,
) {
  if (deletedTag.trim().isEmpty) {
    return (chains: chains, positions: 0, touched: const []);
  }
  final autoTag = '$deletedTag-auto';
  bool matches(NodeLink h) =>
      h.isRoot && (h.tag == deletedTag || h.tag == autoTag);
  var positions = 0;
  final touched = <String>[];
  final out = <SourceChain>[];
  for (final c in chains) {
    final kept = c.hops.where((h) => !matches(h)).toList(growable: false);
    if (kept.length == c.hops.length) {
      out.add(c);
      continue;
    }
    positions += c.hops.length - kept.length;
    touched.add(c.tag);
    out.add(c.copyWith(hops: kept));
  }
  return (chains: out, positions: positions, touched: touched);
}











String chainEmitError(SourceChain c) {
  final hops = c.hops;
  if (hops.isEmpty) return 'chain is empty: no positions set';
  if (hops.length < 2) {
    return 'chain has a single position: the core needs at least two';
  }
  final seen = <NodeLink>{};
  for (var i = 0; i < hops.length; i++) {
    final hop = hops[i];
    if (hop.tag.trim().isEmpty) return 'position ${i + 1} is empty';
    if (hop.isRoot && hop.tag == c.tag) {
      return 'position ${i + 1} references the chain itself';
    }
    if (!seen.add(hop)) return 'position ${i + 1} repeats "${hop.tag}"';
  }
  for (final typeName in c.rewrite.keys) {
    if (typeName.trim().isEmpty) return 'rewrite: empty outbound type name';
  }
  for (final key in c.strip.keys) {
    if (!chainStripKeyKnown(key)) {
      return 'strip: unknown key "$key" '
          '(allowed: ${chainStripKeys().join(', ')})';
    }
  }
  return '';
}











Map<String, dynamic> chainOutboundObject(SourceChain c, List<String> hopTags) => {
      'tag': c.tag,
      'type': kChainOutboundType,
      'outbounds': [...hopTags],
      if (c.idleTimeout.trim().isNotEmpty) 'idle_timeout': c.idleTimeout.trim(),
      if (c.stripEvasion != null) 'strip_evasion': c.stripEvasion,
      if (c.strip.isNotEmpty)


        'strip': orderedChainStrip(c.strip),
      if (c.rewrite.isNotEmpty) 'rewrite': deepCloneJson(c.rewrite),
    };




String nextChainTag(Iterable<String> usedTags) {
  final used = usedTags.toSet();
  for (var i = 1;; i++) {
    final tag = 'chain-$i';
    if (!used.contains(tag)) return tag;
  }
}
