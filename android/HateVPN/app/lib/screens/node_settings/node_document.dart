

















library;

import 'dart:convert';

import '../../models/codec/source_record.dart';
import '../../models/node_spec.dart';
import '../../models/singbox_entry.dart';
import '../../models/template_vars.dart';
import '../../services/l10n/locale_controller.dart';
import '../../services/parser/body_decoder.dart';
import '../../services/parser/json_comments.dart';
import '../../services/parser/parse_all.dart';

sealed class NodeDocumentPrep {
  const NodeDocumentPrep();
}


final class NodeDocumentReady extends NodeDocumentPrep {
  const NodeDocumentReady(this.text,
      {required this.isDocument,
      this.droppedExtras = false,
      this.commentsRemoved = false});


  final bool commentsRemoved;



  final String text;


  final bool isDocument;



  final bool droppedExtras;
}


final class NodeDocumentRejected extends NodeDocumentPrep {
  const NodeDocumentRejected(this.message);
  final String message;
}




const Set<String> _kNonNodeTypes = {
  'direct',
  'block',
  'dns',
  'selector',
  'urltest',
};


const Set<String> _kNodeListKeys = {'outbounds', 'endpoints'};

NodeDocumentPrep prepareNodeDocumentForSave(String text, String tag) {

  final uncommented = uncommentedJson(text);
  if (uncommented == null) return _prepare(text, tag);
  final prep = _prepare(uncommented, tag);
  return switch (prep) {
    NodeDocumentReady r => NodeDocumentReady(r.text,
        isDocument: r.isDocument,
        droppedExtras: r.droppedExtras,
        commentsRemoved: true),
    NodeDocumentRejected() => prep,
  };
}

NodeDocumentPrep _prepare(String text, String tag) {
  final Object? parsed;
  try {
    parsed = jsonDecode(text);
  } on FormatException catch (e) {
    return NodeDocumentRejected(
        getLocalText.s("Invalid JSON: %s", e.message));
  }

  final newTag = tag.trim();

  if (parsed is List) {
    if (parsed.isEmpty) {
      return NodeDocumentRejected(getLocalText.s("Invalid JSON: empty array"));
    }
    final first = parsed.first;
    if (first is! Map || first['type'] is! String) {
      return NodeDocumentRejected(getLocalText.s(
          "JSON must be an outbound object with \"type\" or a document with \"endpoints\"/\"outbounds\""));
    }
    return NodeDocumentReady(
      _bodyText(first.cast<String, dynamic>(), newTag),
      isDocument: false,
      droppedExtras: parsed.length > 1,
    );
  }
  if (parsed is! Map) {
    return NodeDocumentRejected(getLocalText.s(
          "JSON must be an outbound object with \"type\" or a document with \"endpoints\"/\"outbounds\""));
  }
  final map = parsed.cast<String, dynamic>();

  if (map['type'] is String) {
    if (newTag.isEmpty || map['tag'] == newTag) {
      return NodeDocumentReady(text, isDocument: false);
    }
    map['tag'] = newTag;
    return NodeDocumentReady(jsonEncode(map), isDocument: false);
  }

  if (map['endpoints'] is! List && map['outbounds'] is! List) {
    return NodeDocumentRejected(getLocalText.s(
          "JSON must be an outbound object with \"type\" or a document with \"endpoints\"/\"outbounds\""));
  }


  final endpoints = map['endpoints'];
  final outbounds = map['outbounds'];
  final entries = <Object?>[
    if (endpoints is List) ...endpoints,
    if (outbounds is List) ...outbounds,
  ];
  final body = _firstNodeBody(entries);
  if (body == null) {
    return NodeDocumentRejected(
        getLocalText.s("The document has no node to save."));
  }
  final restNotKept = entries.length > 1 ||
      map.keys.any((k) => !_kNodeListKeys.contains(k));
  return NodeDocumentReady(
    _bodyText(body, newTag),
    isDocument: true,
    droppedExtras: restNotKept,
  );
}


String _bodyText(Map<String, dynamic> body, String newTag) {
  final out = Map<String, dynamic>.from(body);
  if (newTag.isNotEmpty) out['tag'] = newTag;
  return const JsonEncoder.withIndent('  ').convert(out);
}











String? checkPayloadFor(String text) {
  final List<NodeSpec> nodes;
  try {

    nodes = parseAll(decode(text), own: true);
  } catch (_) {
    return null;
  }
  if (nodes.isEmpty) return null;
  final node = nodes.first;
  final entry = node.emit(TemplateVars.empty);
  final key = switch (entry) {
    Endpoint() => 'endpoints',
    Outbound() => 'outbounds',
  };
  Map<String, dynamic> body;
  if (sourceIsSingbox(text)) {
    final Object? decoded;
    try {
      decoded = jsonDecode(node.rawSource);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    body = Map<String, dynamic>.from(decoded);
  } else {
    body = Map<String, dynamic>.from(entry.map);
  }
  body.remove('detour');
  return jsonEncode({
    key: [body],
  });
}



Map<String, dynamic>? _firstNodeBody(List<Object?> entries) {
  for (final e in entries) {
    if (e is! Map) continue;
    final type = e['type'];
    if (type is! String || _kNonNodeTypes.contains(type)) continue;
    return e.cast<String, dynamic>();
  }
  return null;
}
