import '../../models/node_spec.dart';
import '../../models/node_warning.dart';
import '../contract/parse_warnings.dart';
import '../contract/registry.dart';
import '../node_hash.dart';
import 'authored_scope.dart';
import 'body_decoder.dart';
import 'engine/document.dart';
import 'ini_parser.dart';
import 'json_parsers.dart';
import 'singbox_config.dart';
import 'uri_parsers.dart';


















































List<NodeSpec> parseAll(
  DecodedBody decoded, {
  String? nameHint,
  List<NodeWarning>? dropped,
  bool own = false,
}) {
  final authored = own &&
      decoded is JsonConfig &&
      decoded.source.kind == SourceKind.singboxOutbound;
  return withOwnSource(
      own,
      () => withAuthoredBody(
          authored, () => _parseAllAnnotated(decoded, nameHint, dropped)));
}






List<NodeSpec>? acceptsOwnUnknownType(DecodedBody decoded) {
  if (decoded is! JsonConfig || decoded.source.mapper != 'singbox') {
    return null;
  }
  final own = parseAll(decoded, own: true);
  if (own.length != 1 || own.single is! UnknownTypeSpec) return null;
  return own;
}

List<NodeSpec> _parseAllAnnotated(
  DecodedBody decoded,
  String? nameHint,
  List<NodeWarning>? dropped,
) {
  final nodes = _parseAll(decoded, nameHint: nameHint, dropped: dropped);











  final byRegistry = annotateAllFromRawBody(nodes);
  if (byRegistry.isNotEmpty) {
    nodes.removeWhere(byRegistry.contains);



    dropped?.addAll(byRegistry.map(_dropReasonOf));
  }





  _dropDuplicates(nodes, dropped);

  annotateAllWithRegistry(nodes);
  return nodes;
}































void _dropDuplicates(List<NodeSpec> nodes, List<NodeWarning>? dropped) {
  if (nodes.length < 2) return;
  final seen = <String, NodeSpec>{};
  final dupes = <NodeSpec>[];
  for (final node in nodes) {
    if (node.isGroup) continue;
    final String sig;
    try {
      sig = nodeDedupSignature(node);
    } catch (_) {


      continue;
    }
    final winner = seen[sig];
    if (winner == null) {
      seen[sig] = node;
      continue;
    }
    dupes.add(node);
    dropped?.add(DuplicateNodeWarning(
      winner: winner.tag.trim() == node.tag.trim() ? '' : winner.tag.trim(),
    ));
  }




  if (dupes.isEmpty) return;
  nodes.removeWhere((n) => dupes.any((d) => identical(d, n)));
}








NodeWarning _dropReasonOf(NodeSpec node) {
  for (final w in node.warnings) {
    if (w is! RegistryWarning) continue;
    if (ContractRegistry.I.textFor(w.code)?.severity != 'error') continue;
    return RegistryWarning(
      code: w.code,
      path: w.path,
      value: w.value,
      params: w.params,
      ownerTag: node.tag,
    );
  }
  return RegistryWarning(code: 'type_invalid', ownerTag: node.tag);
}

List<NodeSpec> _parseAll(
  DecodedBody decoded, {
  String? nameHint,
  List<NodeWarning>? dropped,
}) {
  return switch (decoded) {



    UriLines(lines: final ls) => _parseUriLines(ls, dropped),
    IniConfig(text: final t) => _parseIniConfigs([t], nameHint: nameHint, dropped: dropped),




    AmneziaConfig(iniTexts: final ts) => _parseIniConfigs(
        ts,
        nameHint: nameHint,
        dropped: dropped,
        indexedHint: true,
      ),
    JsonConfig() => _parseJson(decoded, dropped),









    DecodeFailure(reason: final r) => _decodeFailed(r, dropped),
  };
}


List<NodeSpec> _decodeFailed(String reason, List<NodeWarning>? dropped) {
  dropped?.add(RegistryWarning(code: 'core_rejected', params: {'reason': reason}));
  return const <NodeSpec>[];
}

List<NodeSpec> _parseUriLines(List<String> lines, List<NodeWarning>? dropped) {
  final nodes = <NodeSpec>[];
  for (final l in lines) {

    final verdicts = <XrayDropVerdict>[];
    final all = parseContainerLineAll(l, verdicts: verdicts);
    if (all != null) {
      nodes.addAll(all);
      for (var k = 0; k < verdicts.length; k++) {
        final r = verdicts[k].reason;
        if (r == null) continue;

        dropped?.add(withDropOwner(
            r, verdicts.length > 1 ? '${l.trim()} #${k + 1}' : l.trim()));
      }
      continue;
    }
    final verdict = XrayDropVerdict();
    final n = parseUri(l, dropped: verdict);
    if (n != null) {
      nodes.add(n);
    } else if (verdict.reason != null) {





      dropped?.add(withDropOwner(verdict.reason!, l.trim()));
    }
  }
  return nodes;
}



NodeWarning withDropOwner(NodeWarning w, String owner) {
  if (owner.isEmpty || w.ownerTag.isNotEmpty || w is! RegistryWarning) {
    return w;
  }
  return RegistryWarning(
    code: w.code,
    path: w.path,
    value: w.value,
    params: w.params,
    ownerTag: owner,
  );
}

List<NodeSpec> _parseIniConfigs(
  List<String> texts, {
  String? nameHint,
  List<NodeWarning>? dropped,
  bool indexedHint = false,
}) {
  final nodes = <NodeSpec>[];
  for (var i = 0; i < texts.length; i++) {
    final hint = indexedHint ? _indexedHint(nameHint, i) : nameHint;
    final verdict = XrayDropVerdict();
    final n = parseWireguardIni(texts[i], nameHint: hint, dropped: verdict);
    if (n != null) {
      nodes.add(n);
    } else if (verdict.reason != null) {


      dropped?.add(withDropOwner(
          verdict.reason!, hint ?? (texts.length > 1 ? '#${i + 1}' : '')));
    }
  }
  return nodes;
}





String? _indexedHint(String? hint, int i) {
  final h = hint?.trim() ?? '';
  if (h.isEmpty) return null;
  return i == 0 ? h : '$h ${i + 1}';
}




int _payloadCount(Map<String, dynamic> element) {
  final obs = element['outbounds'];
  if (obs is! List) return 0;
  const service = {'freedom', 'blackhole', 'dns', 'loopback'};
  return obs
      .whereType<Map<String, dynamic>>()
      .where((o) => !service.contains(o['protocol']?.toString() ?? ''))
      .length;
}

List<NodeSpec> _parseJson(JsonConfig j, List<NodeWarning>? out) {












  final source = j.source;
  final spec = source.elements;
  final mapper = source.mapper;


  if (mapper == null || spec == null) return const [];


  final groups = DocumentRegistry.groupsFor(spec, j.value);
  if (groups == null || groups.isEmpty) return const [];

  return mapper == 'xray'
      ? _parseXrayDocument(groups, out)
      : parseSingboxConfigs(groups, dropped: out);
}






List<NodeSpec> _parseXrayDocument(
  List<Map<String, dynamic>> elements,
  List<NodeWarning>? out,
) {






      final seen = <String>{};






      final synonyms = <String, String>{};




      final dropped = <NodeWarning>[];





















      final indexed = elements.asMap().entries.toList()
        ..sort((a, b) {
          final byPayload =
              _payloadCount(a.value).compareTo(_payloadCount(b.value));
          return byPayload != 0 ? byPayload : a.key.compareTo(b.key);
        });
      final priming = [for (final e in indexed) e.value];
      final owner = <String, Map<String, dynamic>>{};
      for (final e in priming) {
        final before = seen.toSet();
        parseXrayElement(e, seen: seen, synonyms: synonyms);
        for (final id in seen.difference(before)) {
          owner[id] = e;
        }
      }
      final nodes = elements
          .expand((e) => parseXrayElement(
                e,



                seen: <String>{},
                synonyms: synonyms,
                ownedBy: (sig) => identical(owner[sig], e),
                dropped: dropped,
              ))
          .toList();




      out?.addAll(dropped);
      return nodes;
}
