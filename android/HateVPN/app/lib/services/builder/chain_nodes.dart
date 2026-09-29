



















import '../../models/node_link.dart';
import '../../models/source_chain.dart';
import '../contract/chain_strip.dart';
import '../contract/registry_warning.dart';
import 'core_chain_capability.dart';
import 'node_link_resolve.dart';





class ChainDegradation {
  const ChainDegradation({
    required this.tag,
    required this.label,
    required this.reason,
    required this.code,
  });

  final String tag;
  final String label;


  final String reason;




  final String code;
}



class ChainNote {
  const ChainNote({
    required this.tag,
    required this.label,
    required this.code,
    required this.params,
    required this.line,
  });

  final String tag;
  final String label;


  final String code;
  final Map<String, String> params;



  final String line;
}


class ChainResolution {
  const ChainResolution({
    required this.nodes,
    required this.degraded,
    this.notes = const [],
  });


  final List<Map<String, dynamic>> nodes;


  final List<ChainDegradation> degraded;


  final List<ChainNote> notes;



  List<String> get tags =>
      [for (final n in nodes) n['tag'] as String? ?? ''];
}




















ChainResolution resolveChains(
  List<SourceChain> chains, {
  required Set<String> knownTags,
  NodeLinkTargets? targets,
  Map<String, Map<String, dynamic>> hopBodies = const {},
  String coreVersion = '',
}) {
  final nodes = <Map<String, dynamic>>[];
  final degraded = <ChainDegradation>[];
  final notes = <ChainNote>[];


  final live = [for (final c in chains) if (c.enabled) c];
  if (live.isEmpty) return ChainResolution(nodes: nodes, degraded: degraded);

  final supported = coreSupportsChain(coreVersion);


  final chainTags = <String>{};

  for (final c in live) {
    void degrade(String code, String reason) =>
        degraded.add(ChainDegradation(
            tag: c.tag, label: c.displayLabel, reason: reason, code: code));

    if (!supported) {
      degrade('chain_unsupported_by_core',
          chainUnsupportedByCoreLine(c.displayLabel, coreVersion));
      continue;
    }


    final invalid = chainEmitError(c);
    if (invalid.isNotEmpty) {
      degrade('chain_invalid',
          'Hop chain "${c.displayLabel}" was skipped: $invalid.');
      continue;
    }




    if (knownTags.contains(c.tag)) {
      degrade(
          'chain_invalid',
          'Hop chain "${c.displayLabel}" was skipped: the tag "${c.tag}" is '
              'already taken by another outbound, direction or chain.');
      continue;
    }




    final hopTags = <String>[];
    NodeLink? missing;
    var missingWhy = '';
    var missingAt = 0;
    for (var i = 0; i < c.hops.length; i++) {
      final hop = c.hops[i];
      final String? tag;
      if (targets != null) {
        final r = targets.resolve(hop);
        tag = r.tag;
        missingWhy = r.reason;
      } else {
        tag = hop.isRoot && knownTags.contains(hop.tag) ? hop.tag : null;
      }
      if (tag == null) {
        missing = hop;
        missingAt = i + 1;
        break;
      }
      hopTags.add(tag);
    }
    if (missing != null) {


      final notFound = missing.isRoot &&
          (targets == null || missingWhy.startsWith('target '));
      degrade(
          'chain_hop_missing',
          notFound
              ? 'Hop chain "${c.displayLabel}" was dropped: position $missingAt '
                  '("${missing.tag}") was not found among nodes, directions and '
                  'chains declared above it. A route without a hop is a '
                  'different route, so the whole chain is skipped.'
              : 'Hop chain "${c.displayLabel}" was dropped: position $missingAt '
                  '(${targets?.describe(missing) ?? '"${missing.tag}"'}) did not '
                  'resolve — $missingWhy. A route without a hop is a different '
                  'route, so the whole chain is skipped.');
      continue;
    }




    final nested = <String>[];
    for (var i = 1; i < hopTags.length; i++) {
      if (chainTags.contains(hopTags[i])) nested.add(hopTags[i]);
    }
    if (nested.isNotEmpty) {
      degrade(
          'chain_nested_position',
          'Hop chain "${c.displayLabel}" was dropped: nested chains '
              '${nested.map((t) => '"$t"').join(', ')} are not at position 1 — '
              'the core allows a nested chain only as the first hop.');
      continue;
    }



    final unstrips = chainHopUnstrips(
      stripEvasion: c.stripEvasion,
      patch: c.strip,
      hops: [for (final t in hopTags) (t, hopBodies[t])],
    );
    var emitted = c;
    if (unstrips.isNotEmpty) {
      emitted = c.copyWith(strip: applyChainUnstrips(c.strip, unstrips));
      for (final u in unstrips) {
        final params = {'target': u.target};
        notes.add(ChainNote(
          tag: c.tag,
          label: c.displayLabel,
          code: u.code,
          params: params,
          line: 'Hop chain "${c.displayLabel}": '
              '${registryText(u.code, RegistryLang.en, params: params)} '
              '[${u.code}]',
        ));
      }
    }
    nodes.add(chainOutboundObject(emitted, hopTags));
    knownTags.add(c.tag);
    targets?.addRootNames([c.tag]);
    chainTags.add(c.tag);
  }
  return ChainResolution(nodes: nodes, degraded: degraded, notes: notes);
}























Map<String, List<String>> chainHopsByTag(List<Map<String, dynamic>> chainNodes) {
  final out = <String, List<String>>{};
  for (final n in chainNodes) {
    final tag = n['tag'];
    if (tag is! String || tag.isEmpty) continue;
    out[tag] = [
      for (final h in (n['outbounds'] as List? ?? const []))
        if (h is String) h,
    ];
  }
  return out;
}







bool chainPassesThrough(
  String chainTag,
  String target,
  Map<String, List<String>> hopsByTag, [
  Set<String>? seen,
]) {
  final visited = seen ?? <String>{};
  if (!visited.add(chainTag)) return false;
  for (final hop in hopsByTag[chainTag] ?? const <String>[]) {
    if (hop == target) return true;
    if (hopsByTag.containsKey(hop) &&
        chainPassesThrough(hop, target, hopsByTag, visited)) {
      return true;
    }
  }
  return false;
}










({List<String> kept, List<String> dropped}) dropChainsThroughDirection(
  List<String> nodes,
  String directionTag,
  Map<String, List<String>> hopsByTag,
) {
  if (directionTag.isEmpty || hopsByTag.isEmpty) {
    return (kept: nodes, dropped: const []);
  }



  final cyclic = <String>{};
  for (final tag in nodes) {
    if (!hopsByTag.containsKey(tag) || cyclic.contains(tag)) continue;
    if (chainPassesThrough(tag, directionTag, hopsByTag)) cyclic.add(tag);
  }
  if (cyclic.isEmpty) return (kept: nodes, dropped: const []);
  final kept = <String>[];
  final dropped = <String>[];
  for (final tag in nodes) {
    if (cyclic.contains(tag)) {
      if (!dropped.contains(tag)) dropped.add(tag);
      continue;
    }
    kept.add(tag);
  }
  return (kept: kept, dropped: dropped);
}


String chainCycleThroughDirectionLine(String directionLabel, List<String> chains) {
  final list = chains.map((t) => '"$t"').join(', ');
  final subject = chains.length == 1 ? 'Hop chain $list runs' : 'Hop chains $list run';
  return '$subject through direction "$directionLabel" and '
      '${chains.length == 1 ? 'was' : 'were'} left out of it — otherwise '
      'picking the chain inside that direction would loop the traffic back '
      'onto itself. The chain is still available in other directions.';
}
