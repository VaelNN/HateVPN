



import 'dart:convert';

import '../parser/engine/section_loader.dart' show MapperSections;
import '../parser/mappers/uri_pipeline.dart' show pipelineSchemes;








bool isSubscriptionUrl(String input) {
  final t = input.trim();
  return t.startsWith('http://') || t.startsWith('https://');
}




bool isFileSubscription(String url) => url.startsWith('file:');


















bool isDirectLink(String input) {
  final t = input.trim();
  final sep = t.indexOf('://');
  if (sep <= 0) return false;
  return pipelineSchemes().contains(t.substring(0, sep).toLowerCase());
}








String? documentKindOf(String input) {
  final reg = MapperSections.I.documents;
  if (reg == null) return null;



  final hits = reg.matchAll(input);
  if (hits.isEmpty) return reg.defaultSource?.kind;
  var best = hits.first;
  for (final s in hits) {
    if (s.priority < best.priority) best = s;
  }
  return best.kind;
}



String? _bodyTypeOfKind(String kind) {
  final mapper = MapperSections.I.documents?.sourceByKind(kind)?.mapper;
  if (mapper == null) return null;
  final types = MapperSections.I.typesFor(mapper);
  return types.length == 1 ? types.single : null;
}

bool isWireGuardConfig(String input) {


  return documentKindOf(input) == 'wireguard_conf';
}







bool isAmneziaVpnLink(String input) =>
    documentKindOf(input) == 'amnezia_link';



String inputSourceLabel(String input) {
  final t = input.trim();
  final firstLine = t.split(RegExp(r'\r?\n')).first.trim();
  if (firstLine.contains('://')) {
    final uri = Uri.tryParse(firstLine);
    if (uri != null) {
      if (uri.fragment.isNotEmpty) return uri.fragment;
      if (uri.scheme.isNotEmpty) return uri.scheme;
    }
    final scheme = firstLine.split('://').first.toLowerCase();
    if (scheme.isNotEmpty) return scheme;
  }


  if (isWireGuardConfig(t)) {
    return _bodyTypeOfKind(documentKindOf(t) ?? '') ?? 'input';
  }
  if (firstLine.startsWith('{') || firstLine.startsWith('[')) {
    try {
      final decoded = jsonDecode(t);
      if (decoded is Map) {
        final type = decoded['type'] ?? decoded['protocol'];
        if (type is String && type.isNotEmpty) return type;
      }
    } on FormatException {

    }
    return 'json';
  }
  return 'input';
}
