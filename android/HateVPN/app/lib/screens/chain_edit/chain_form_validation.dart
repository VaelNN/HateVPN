













import '../../models/server_list.dart';
import '../../models/source_chain.dart';
import '../../services/builder/node_link_pool.dart';
import '../../services/builder/node_link_resolve.dart';
import '../../services/contract/chain_strip.dart';
import '../../services/contract/registry_warning.dart';
import '../../services/l10n/locale_controller.dart';
import 'chain_hop_candidate.dart';


enum ChainIssueLevel {

  blocking,




  warning,



  info,
}






enum ChainIssueCode {

  tooFewHops,


  duplicateHop,


  selfReference,




  emptyHop,


  nestedNotFirst,




  masqueFixedH3OnLink,




  wgBehindTcpHop,


  forwardChainReference,




  stripKeptForHop,


  detourAtEntry,


  detourIgnoredOnLink,


  missingHops,


  tagTaken,


  tagEmpty,
}


class ChainFormIssue {
  const ChainFormIssue({
    required this.code,
    required this.level,
    required this.message,
    this.hops = const [],
  });

  final ChainIssueCode code;
  final ChainIssueLevel level;


  final String message;


  final List<String> hops;

  bool get blocks => level == ChainIssueLevel.blocking;
}


class ChainFormContext {
  const ChainFormContext({
    this.candidates = const {},
    this.targetsKnown = false,
    this.takenTags = const {},
    this.originalTag = '',
  });


  final Map<String, ChainHopCandidate> candidates;




  final bool targetsKnown;



  final Set<String> takenTags;



  final String originalTag;
}


class ChainFormState {
  const ChainFormState({
    required this.tag,
    required this.hops,
    this.stripEvasion,
    this.strip = const {},
  });




  ChainFormState.of(
    SourceChain c, {
    NodeLinkTargets? pool,
    List<ServerList> lists = const [],
  })  : tag = c.tag,
        hops = [for (final h in c.hops) nodeLinkDisplay(h, pool, lists: lists)],
        stripEvasion = c.stripEvasion,
        strip = c.strip;

  final String tag;


  final List<String> hops;
  final bool? stripEvasion;
  final Map<String, bool> strip;
}






List<ChainFormIssue> validateChainForm(
  ChainFormState state,
  ChainFormContext ctx,
) {
  final blocking = <ChainFormIssue>[];
  final soft = <ChainFormIssue>[];
  final hops = state.hops;




  if (hops.length < 2) {
    blocking.add(ChainFormIssue(
      code: ChainIssueCode.tooFewHops,
      level: ChainIssueLevel.blocking,
      message: getLocalText.s("At least two positions are needed: the core rejects a single-hop chain."),
    ));
  }





  final empties = <int>[
    for (var i = 0; i < hops.length; i++)
      if (hops[i].trim().isEmpty) i + 1,
  ];
  if (empties.isNotEmpty) {
    blocking.add(ChainFormIssue(
      code: ChainIssueCode.emptyHop,
      level: ChainIssueLevel.blocking,
      message: getLocalText.s(
          "Positions %s are empty — remove them: the core rejects a chain with a blank position.",
          empties.join(', ')),
    ));
  }



  final selfRefs = [
    for (final h in hops)
      if (h == state.tag && h.isNotEmpty) h,
  ];
  if (selfRefs.isNotEmpty) {
    blocking.add(ChainFormIssue(
      code: ChainIssueCode.selfReference,
      level: ChainIssueLevel.blocking,
      message: getLocalText.s("Position %s references this chain itself — the core rejects that.", _list(selfRefs.toSet().toList())),
      hops: selfRefs.toSet().toList(),
    ));
  }

  final dupes = <String>[];
  final seen = <String>{};
  for (final h in hops) {
    if (!seen.add(h) && !dupes.contains(h)) dupes.add(h);
  }
  if (dupes.isNotEmpty) {
    blocking.add(ChainFormIssue(
      code: ChainIssueCode.duplicateHop,
      level: ChainIssueLevel.blocking,
      message: getLocalText.s("Position %s is used more than once — the core rejects a chain with repeats.", _list(dupes)),
      hops: dupes,
    ));
  }




  final nested = <String>[];
  for (var i = 1; i < hops.length; i++) {
    if (ctx.candidates[hops[i]]?.kind == ChainHopKind.chain) {
      nested.add(hops[i]);
    }
  }
  if (nested.isNotEmpty) {
    blocking.add(ChainFormIssue(
      code: ChainIssueCode.nestedNotFirst,
      level: ChainIssueLevel.blocking,
      message: getLocalText.s("A nested chain (%s) is only allowed at the first position — "
        "move it to the top or remove it.", _list(nested)),
      hops: nested,
    ));
  }





  final forward = <String>[];
  for (final h in hops) {
    final c = ctx.candidates[h];
    if (c != null && c.kind == ChainHopKind.chain && c.below) forward.add(h);
  }
  if (forward.isNotEmpty) {
    blocking.add(ChainFormIssue(
      code: ChainIssueCode.forwardChainReference,
      level: ChainIssueLevel.blocking,
      message: getLocalText.s("Chains %s are declared below this one — a chain may only reference "
        "chains above it. Move them up, or this chain will not build.", _list(forward)),
      hops: forward,
    ));
  }




  final unstrips = chainHopUnstrips(
    stripEvasion: state.stripEvasion,
    patch: state.strip,
    hops: [for (final h in hops) (h, ctx.candidates[h]?.body)],
  );
  final lang = registryLangForTag(LocaleController.I.effectiveTag);
  for (final u in unstrips) {
    soft.add(ChainFormIssue(
      code: ChainIssueCode.stripKeptForHop,
      level: ChainIssueLevel.warning,
      message: registryText(u.code, lang, params: {'target': u.target}),
      hops: [u.target],
    ));
  }


  final tag = state.tag.trim();
  if (tag.isEmpty) {
    blocking.add(ChainFormIssue(
      code: ChainIssueCode.tagEmpty,
      level: ChainIssueLevel.blocking,
      message: getLocalText.s("A chain needs a name — it becomes its tag in the config."),
    ));
  } else if (tag != ctx.originalTag && ctx.takenTags.contains(tag)) {
    blocking.add(ChainFormIssue(
      code: ChainIssueCode.tagTaken,
      level: ChainIssueLevel.blocking,
      message: getLocalText.s("The name \"%s\" is already taken by another node, direction or chain — "
        "two outbounds with one tag cannot coexist.", tag),
    ));
  }










  if (ctx.targetsKnown) {
    final missing = [
      for (final h in hops)
        if (h.isNotEmpty && !ctx.candidates.containsKey(h) && h != state.tag) h,
    ];
    if (missing.isNotEmpty) {
      soft.add(ChainFormIssue(
        code: ChainIssueCode.missingHops,
        level: ChainIssueLevel.warning,
        message: getLocalText.s("These positions are no longer among the available targets: %s. "
        "A chain with such a reference will not reach the config.", _list(missing)),
        hops: missing,
      ));
    }
  }















  if (hops.isNotEmpty && (ctx.candidates[hops[0]]?.detour ?? false)) {
    soft.add(ChainFormIssue(
      code: ChainIssueCode.detourAtEntry,
      level: ChainIssueLevel.warning,
      message: getLocalText.s("The first position (%s) dials through its own detour — the real path "
        "is longer than shown: one more hop precedes it that is not in this list.", hops[0]),
      hops: [hops[0]],
    ));
  }
  final detoured = <String>[];
  for (var i = 1; i < hops.length; i++) {
    if ((ctx.candidates[hops[i]]?.detour ?? false) && !detoured.contains(hops[i])) {
      detoured.add(hops[i]);
    }
  }
  if (detoured.isNotEmpty) {
    soft.add(ChainFormIssue(
      code: ChainIssueCode.detourIgnoredOnLink,
      level: ChainIssueLevel.info,
      message: getLocalText.s("Positions %s have their own detour — it does not apply inside a chain: "
        "a link always dials through the previous position. The path is exactly "
        "as shown.", _list(detoured)),
      hops: detoured,
    ));
  }





  const tcpHops = {
    'vless', 'vmess', 'trojan', 'shadowsocks', 'socks', 'http',
    'anytls', 'naive', 'shadowtls',
  };
  for (var i = 1; i < hops.length; i++) {
    final c = ctx.candidates[hops[i]];
    if (c == null) continue;
    if (c.outboundType == 'masque' && c.masqueVhttp == 'h3') {
      soft.add(ChainFormIssue(
        code: ChainIssueCode.masqueFixedH3OnLink,
        level: ChainIssueLevel.warning,
        message: getLocalText.s(
            "Position %s is MASQUE with fixed h3: QUIC through the previous "
            "hop may hang. Set vhttp: auto (or h2) on the node.", hops[i]),
        hops: [hops[i]],
      ));
    }
    final prev = ctx.candidates[hops[i - 1]];
    if (c.outboundType == 'wireguard' &&
        prev != null &&
        tcpHops.contains(prev.outboundType)) {
      soft.add(ChainFormIssue(
        code: ChainIssueCode.wgBehindTcpHop,
        level: ChainIssueLevel.warning,
        message: getLocalText.s(
            "Position %s is WireGuard behind a TCP hop: the previous server "
            "must actually proxy UDP, otherwise the handshake goes nowhere.",
            hops[i]),
        hops: [hops[i]],
      ));
    }
  }

  return [...blocking, ...soft];
}





bool chainFormCanSave(List<ChainFormIssue> issues) =>
    !issues.any((i) => i.blocks);

String _list(List<String> tags) => tags.join(', ');
