import 'dart:convert';
import 'dart:math';

import 'amnezia_link.dart';
import 'engine/document.dart';
import 'engine/section_loader.dart';
import 'uri_utils.dart';



sealed class DecodedBody {
  const DecodedBody();
}

final class UriLines extends DecodedBody {
  final List<String> lines;




  final int skippedComments;
  const UriLines(this.lines, this.skippedComments);
}

final class IniConfig extends DecodedBody {
  final String text;
  const IniConfig(this.text);
}



final class AmneziaConfig extends DecodedBody {
  final List<String> iniTexts;
  const AmneziaConfig(this.iniTexts);
}

final class JsonConfig extends DecodedBody {
  final Object value;








  final DocumentSource source;

  const JsonConfig(this.value, this.source);
}

final class DecodeFailure extends DecodedBody {
  final String reason;
  final String? sample;
  const DecodeFailure(this.reason, [this.sample]);
}








abstract final class SourceKind {







  static const xrayConfigArray = 'xray_config_array';


  static const xrayConfig = 'xray_config';


  static const xrayOutbound = 'xray_outbound';


  static const xrayOutboundArray = 'xray_outbound_array';


  static const singboxOutbound = 'singbox_outbound';


  static const singboxOutboundArray = 'singbox_outbound_array';


  static const singboxConfig = 'singbox_config';


  static const singboxConfigArray = 'singbox_config_array';





  static const clashYaml = 'clash_yaml';


  static const unknown = 'unknown';
}










const kFallbackDocumentSources = <DocumentSource>[
  DocumentSource(
    kind: SourceKind.xrayConfigArray,
    mapper: 'xray',
    elements: '[].outbounds[]',
  ),
  DocumentSource(
    kind: SourceKind.singboxConfigArray,
    mapper: 'singbox',
    elements: '[].outbounds[]',
  ),
  DocumentSource(
    kind: SourceKind.singboxOutboundArray,
    mapper: 'singbox',
    elements: '[]',
  ),
  DocumentSource(
    kind: SourceKind.singboxOutbound,
    mapper: 'singbox',
    elements: r'$self',
  ),
  DocumentSource(
    kind: SourceKind.singboxConfig,
    mapper: 'singbox',
    elements: 'outbounds[]+endpoints[]',
  ),
  DocumentSource(kind: SourceKind.clashYaml),
  DocumentSource(kind: SourceKind.unknown),
];

DocumentSource _fallback(String kind) =>
    kFallbackDocumentSources.firstWhere((s) => s.kind == kind);




















DecodedBody decode(String body) {
  final original = body.trimRight();
  if (original.isEmpty) return const DecodeFailure('empty body');

  final registry = MapperSections.I.documents;
  if (registry == null) return _classifyLegacy(original);

  final match = registry.detect(original, unwrappers: _kUnwrappers);
  if (match == null) {
    return DecodeFailure(
        'no parseable content', original.substring(0, min(original.length, 80)));
  }



  if (match.source.unwrap == _kAmneziaUnwrap) {
    return decodeAmneziaLink(original);
  }

  return _classifyByKind(match);
}





DecodedBody _classifyByKind(DocumentMatch match) {
  final text = match.text;
  switch (match.source.mapper) {
    case 'conf':
      return IniConfig(text);
    case 'xray':
    case 'singbox':
      final value = match.json ?? _tryJsonDecode(text);
      if (value == null) return _classifyLegacy(text);


      return JsonConfig(value, match.source);
    case 'uri':






      final head = text.trimLeft();
      if (head.startsWith('{') || head.startsWith('[')) {
        final value = _tryJsonDecode(text);
        if (value != null) return JsonConfig(value, _detectLegacySource(value));
      }
      return _uriLines(text, match.source.lineCommentPrefixes);
    case null:



      if (match.source.unwrap != null) {
        return DecodeFailure(
            'no parseable content', text.substring(0, min(text.length, 80)));
      }


      final value = match.json ?? _tryJsonDecode(text);
      if (value == null) return _classifyLegacy(text);
      return JsonConfig(value, _detectLegacySource(value));
    default:
      return _classifyLegacy(text);
  }
}

Object? _tryJsonDecode(String text) {
  try {
    return jsonDecode(text.trim());
  } catch (_) {
    return null;
  }
}



const _kAmneziaUnwrap = 'amnezia_vpn';


final Map<String, Unwrapper> _kUnwrappers = {


  _kAmneziaUnwrap: (text) => text,
  'base64_utf8': (text) {
    final noWs = text.replaceAll(RegExp(r'\s+'), '');
    final bytes = decodeBase64Safe(noWs);
    if (bytes == null || !_isLikelyUtf8(bytes)) return null;
    final decoded = utf8Lossy(bytes).trim();
    return decoded.isEmpty ? null : decoded;
  },
};

DecodedBody _uriLines(String text, List<String> commentPrefixes) {
  final lines = <String>[];
  var skipped = 0;
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final l = raw.trim();
    if (l.isEmpty) continue;
    if (commentPrefixes.any(l.startsWith)) {
      skipped++;
      continue;
    }
    lines.add(l);
  }
  if (lines.isEmpty) {
    return DecodeFailure(
        'no parseable content', text.substring(0, min(text.length, 80)));
  }
  return UriLines(lines, skipped);
}


DecodedBody _classifyLegacy(String body) {
  final original = body.trimRight();
  if (original.isEmpty) return const DecodeFailure('empty body');

  if (original.trimLeft().startsWith('vpn://')) {
    return decodeAmneziaLink(original);
  }

  final trimmedNoWs = original.replaceAll(RegExp(r'\s+'), '');
  if (_looksLikeBase64(trimmedNoWs)) {
    final bytes = decodeBase64Safe(trimmedNoWs);
    if (bytes != null && _isLikelyUtf8(bytes)) {
      final decoded = utf8Lossy(bytes).trim();
      if (decoded.isNotEmpty && _isPlausiblePayload(decoded)) {
        return _classifyPlain(decoded);
      }
    }
  }

  return _classifyPlain(original);
}

DecodedBody _classifyPlain(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) return const DecodeFailure('empty after decode');


  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      final value = jsonDecode(trimmed);
      return JsonConfig(value, _detectLegacySource(value));
    } catch (_) {

    }
  }


  if (_firstNonCommentLine(trimmed).trim().toLowerCase() == '[interface]' &&
      trimmed.contains('[Peer]')) {
    return IniConfig(trimmed);
  }


  final lines = <String>[];
  var skipped = 0;
  for (final raw in trimmed.split(RegExp(r'\r?\n'))) {
    final l = raw.trim();
    if (l.isEmpty) continue;
    if (l.startsWith('#') || l.startsWith('//') || l.startsWith(';')) {
      skipped++;
      continue;
    }
    lines.add(l);
  }
  if (lines.isEmpty) {
    return DecodeFailure(
        'no parseable content', trimmed.substring(0, min(trimmed.length, 80)));
  }
  return UriLines(lines, skipped);
}

bool _looksLikeBase64(String s) {
  if (s.length < 16) return false;
  final re = RegExp(r'^[A-Za-z0-9+/_=\-]+$');
  return re.hasMatch(s);
}

bool _isLikelyUtf8(List<int> bytes) {
  try {
    final s = utf8.decode(bytes);

    var ctrl = 0;
    for (final r in s.runes) {
      if (r < 0x09 || (r > 0x0D && r < 0x20)) ctrl++;
    }
    return ctrl < (s.length * 0.2);
  } catch (_) {
    return false;
  }
}

bool _isPlausiblePayload(String s) {
  return s.contains('://') ||
      s.trimLeft().startsWith('{') ||
      s.trimLeft().startsWith('[') ||
      s.contains('[Interface]');
}

String _firstNonCommentLine(String s) {
  for (final raw in s.split(RegExp(r'\r?\n'))) {
    final l = raw.trim();
    if (l.isEmpty) continue;
    if (l.startsWith('#') || l.startsWith('//') || l.startsWith(';')) continue;
    return l;
  }
  return '';
}






DocumentSource _detectLegacySource(Object v) {
  if (v is List && v.isNotEmpty) {
    final first = v.first;
    if (first is Map && first['outbounds'] is List) {



      return _fallback(_looksLikeSingboxOutbounds(first['outbounds'] as List)
          ? SourceKind.singboxConfigArray
          : SourceKind.xrayConfigArray);
    }


    if (first is Map && first['type'] is String) {
      return _fallback(SourceKind.singboxOutboundArray);
    }
    return _fallback(SourceKind.unknown);
  }
  if (v is Map) {


    if (v['type'] is String) return _fallback(SourceKind.singboxOutbound);
    if (v['proxies'] is List) return _fallback(SourceKind.clashYaml);


    if (v['outbounds'] is List || v['endpoints'] is List) {
      return _fallback(SourceKind.singboxConfig);
    }
  }
  return _fallback(SourceKind.unknown);
}







bool _looksLikeSingboxOutbounds(List outbounds) {
  for (final o in outbounds) {
    if (o is! Map) continue;
    if (o['type'] is String) return true;
    if (o['protocol'] is String) return false;
  }
  return false;
}
