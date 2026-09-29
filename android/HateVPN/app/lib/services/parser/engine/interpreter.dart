






















library;

import 'dart:convert' show Base64Codec, jsonDecode;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../models/node_warning.dart';
import '../drop_verdict.dart';
import 'decoders.dart';
import 'ini_space.dart';
import 'lexer.dart';
import 'section.dart';
import 'source_space.dart';
import 'trace.dart';



















@visibleForTesting
int? normalizeBandwidthMbps(String value) {
  final m = RegExp(r'^\s*(\d+(?:\.\d+)?)\s*([a-zA-Z]*)\s*$').firstMatch(value);
  if (m == null) return null;
  final n = double.tryParse(m.group(1)!);
  if (n == null || !n.isFinite) return null;

  final factor = switch (m.group(2)!.toLowerCase()) {
    '' || 'm' || 'mb' || 'mbps' => 1.0,
    'g' || 'gb' || 'gbps' => 1000.0,
    'k' || 'kb' || 'kbps' => 1 / 1000,
    'b' || 'bps' => 1 / 1000000,
    _ => null,
  };
  if (factor == null) return null;
  final mbps = n * factor;
  if (mbps <= 0) return null;
  return mbps.ceil();
}


final class EngineResult {
  const EngineResult({
    required this.body,
    required this.label,
    this.warnings = const [],
    this.extensionFields = const {},
    this.wsEarlyDataHeaderImplicit = false,
    this.tagAddress,
    this.tagScheme,
    this.kinds = const {},
    this.bodySource = '',
  });


  final Map<String, dynamic> body;


  final String label;

  final List<NodeWarning> warnings;
  final Map<String, dynamic> extensionFields;
  final bool wsEarlyDataHeaderImplicit;
  final (String, int)? tagAddress;



  final Set<String> kinds;



  final String? tagScheme;








  final String bodySource;
}





EngineResult? runSection(MapperSection section, String text,
    {MapperTrace? trace, XrayDropVerdict? dropped}) {
  final space = _selectForm(section, text);
  if (space == null) {




    if (dropped != null && dropped.reason == null) {
      dropped.reason = const RegistryWarning(code: 'form_unrecognized');
    }
    return null;
  }
  return _Run(section, space, trace, dropped: dropped).execute();
}












EngineResult? runSectionOnJson(
  MapperSection section,
  Map<String, dynamic> doc, {
  MapperTrace? trace,
  XrayDropVerdict? dropped,
  Map<String, dynamic>? context,
  List<dynamic>? document,
}) {
  final space = _selectJsonForm(section, doc);
  if (space == null) {




    if (dropped != null && dropped.reason == null) {
      dropped.reason = const RegistryWarning(code: 'form_unrecognized');
    }
    return null;
  }
  return _Run(section, space, trace,
          dropped: dropped, context: context, document: document)
      .execute();
}















EngineResult? runSectionOnIni(
  MapperSection section,
  String text, {
  String? nameHint,
  MapperTrace? trace,
  XrayDropVerdict? dropped,
  Map<String, dynamic>? context,
}) {
  final space = _selectIniForm(section, text);
  if (space == null) return null;
  final parsed = parseIniSpace(text, section.iniDialect ?? const IniDialect());
  return _Run(section, space, trace,
          nameHint: nameHint, dropped: dropped, context: context)
      .execute(inputCodes: parsed.codes);
}




List<MapperForm> formsInTrialOrder(List<MapperForm> forms) {
  if (forms.length < 2) return forms;
  final i = forms.indexWhere((f) => f.detect?['default'] == true);
  if (i < 0 || i == forms.length - 1) return forms;
  return [
    for (final f in forms)
      if (f.detect?['default'] != true) f,
    for (final f in forms)
      if (f.detect?['default'] == true) f,
  ];
}



SourceSpace? _selectIniForm(MapperSection section, String text) {
  final dialect = section.iniDialect ?? const IniDialect();
  final parsed = parseIniSpace(text, dialect);
  final forms = section.forms.isEmpty
      ? const [MapperForm(id: 'ini', space: 'ini')]
      : formsInTrialOrder(section.forms);
  for (final form in forms) {
    if (!detectMatchesIni(form.detect, parsed.space)) continue;
    return SourceSpace(formId: form.id, ini: parsed.space);
  }
  return null;
}






SourceSpace? _selectForm(MapperSection section, String text) {
  final forms = section.forms.isEmpty
      ? const [MapperForm(id: 'url', space: 'url')]
      : formsInTrialOrder(section.forms);
  for (final form in forms) {








    if (form.space == 'ini') {
      final ini = _selectLinkIniForm(section, form, text);
      if (ini != null) return ini;
      continue;
    }
    final rawHit = formMatchesText(form.detect, text);
    if (!rawHit && form.decode.isEmpty) continue;




    final decoded = _applyFormDecode(form, text);
    if (decoded == null) continue;
    if (!rawHit) {
      final revealed = _applyScopedDecodeToPayload(form, decoded);
      if (revealed == null || !formMatchesText(form.detect, revealed)) {
        continue;
      }
    }
    switch (form.space) {
      case 'url':
        final space = lexUri(decoded, formId: form.id);
        if (space == null) continue;
















        final unwrapped = _applyScopedDecodeToPayload(form, decoded);
        if (unwrapped == null) continue;
        if (unwrapped != decoded) {
          final relexed = lexUri(unwrapped, formId: form.id);
          if (relexed != null) return relexed;
          continue;
        }
        final scoped = _applyScopedDecode(form, space);
        if (scoped != null) return scoped;
      case 'json':















        final unwrapped = _applyScopedDecodeToPayload(form, decoded);
        if (unwrapped == null) continue;
        final doc = _decodeFormJson(form, unwrapped);
        if (doc == null) continue;
        if (!detectMatchesJson(form.detect, doc)) continue;
        return SourceSpace(
          formId: form.id,
          scheme: _splitScheme(decoded)?.scheme ?? '',
          json: doc,
          jsonBase: form.base,









          query: _flattenContainer(doc),
        );
      default:


        continue;
    }
  }
  return null;
}










SourceSpace? _selectLinkIniForm(
    MapperSection section, MapperForm form, String text) {
  final split = _splitScheme(text);
  if (split == null) return null;
  var payload = split.payload;
  var fragment = '';
  final hash = payload.indexOf('#');
  if (hash >= 0) {
    fragment = payload.substring(hash + 1);
    payload = payload.substring(0, hash);
  }
  final bare = '${split.scheme}://$payload';
  if (!formMatchesText(form.detect, bare)) return null;
  final decoded = _applyFormDecode(form, bare);
  if (decoded == null) return null;
  final unwrapped = _applyScopedDecodeToPayload(form, decoded);
  if (unwrapped == null) return null;
  final conf = _splitScheme(unwrapped)?.payload ?? unwrapped;
  final parsed =
      parseIniSpace(conf, section.iniDialect ?? const IniDialect());
  return SourceSpace(
    formId: form.id,
    scheme: split.scheme,
    fragment: fragment,
    ini: parsed.space,
  );
}



SourceSpace? _selectJsonForm(MapperSection section, Map<String, dynamic> doc) {
  final forms = section.forms.isEmpty
      ? const [MapperForm(id: 'json', space: 'json')]
      : formsInTrialOrder(section.forms);
  for (final form in forms) {
    if (!detectMatchesJson(form.detect, doc)) continue;
    return SourceSpace(formId: form.id, json: doc, jsonBase: form.base);
  }
  return null;
}




({String scheme, String payload})? _splitScheme(String text) {
  final i = text.indexOf('://');
  if (i <= 0) return null;
  return (scheme: text.substring(0, i), payload: text.substring(i + 3));
}













String? _applyFormDecode(MapperForm form, String text) {
  if (form.decode.isEmpty) return text;
  final split = _splitScheme(text);
  if (split == null) return text;
  var payload = split.payload;
  var fragment = '';
  final hash = payload.indexOf('#');
  if (hash >= 0) {
    fragment = payload.substring(hash);
    payload = payload.substring(0, hash);
  }
  for (final step in form.decode) {
    if (step == 'url') continue;


    if (step is Map && step['scope'] != null && step['scope'] != 'all') {
      continue;
    }
    if (step == 'percent') {
      payload = percentDecodeOnce(payload, mode: DecodeMode.path);
      continue;
    }
    if (step is Map && step['decoder'] != null) {
      final d = step['decoder'];
      if (d == 'percent') {
        payload = percentDecodeOnce(payload, mode: DecodeMode.path);
      } else if (d == 'base64' || d == 'base64?' || d == 'base64url') {
        final decoded = _RunDecode.base64(payload.trim());
        if (decoded == null) {
          if (d == 'base64') return null;
          continue;
        }
        payload = decoded;
      }
      continue;
    }
    if (step == 'base64' || step == 'base64?') {
      final decoded = _RunDecode.base64(payload.trim());
      if (decoded == null) {
        if (step == 'base64') return null;
        continue;
      }
      payload = decoded;
      continue;
    }
    if (step is Map && step['reparse'] != null) continue;



    if (step == 'json') continue;
  }
  return '${split.scheme}://$payload$fragment';
}

















String? _applyScopedDecodeToPayload(MapperForm form, String text) {
  final split = _splitScheme(text);
  if (split == null) return text;
  var payload = split.payload;
  var fragment = '';
  final hash = payload.indexOf('#');
  if (hash >= 0) {
    fragment = payload.substring(hash);
    payload = payload.substring(0, hash);
  }
  for (final step in form.decode) {
    if (step is! Map) continue;



    if (step['scope'] != 'authority') continue;
    final decoder = step['decoder'];
    if (decoder == 'percent') {
      payload = percentDecodeOnce(payload, mode: DecodeMode.path);
      continue;
    }
    if (decoder == 'base64' || decoder == 'base64?' || decoder == 'base64url') {
      final decoded = _RunDecode.base64(payload.trim());
      if (decoded == null) {
        if (decoder == 'base64') return null;
        continue;
      }
      payload = decoded;
    }
  }
  return '${split.scheme}://$payload$fragment';
}














SourceSpace? _applyScopedDecode(MapperForm form, SourceSpace space) {
  var result = space;
  for (final step in form.decode) {
    if (step is! Map) continue;
    final scope = step['scope'];
    if (scope == null || scope == 'all') continue;
    final decoder = step['decoder'];
    final optional = decoder == 'base64?' || decoder == 'percent';

    String piece;
    switch (scope) {
      case 'userinfo':
        piece = result.userinfo;
      case 'authority':
        piece = result.authority;
      default:
        continue;
    }
    if (piece.isEmpty) continue;

    String? decoded;
    switch (decoder) {
      case 'base64':
      case 'base64?':
      case 'base64url':
        decoded = _RunDecode.base64(piece.trim());
      case 'percent':
        decoded = percentDecodeOnce(piece, mode: DecodeMode.path);
      default:
        continue;
    }
    if (decoded == null) {
      if (optional) continue;
      return null;
    }




    final tail = StringBuffer()
      ..write(result.path)
      ..write(result.query.pairs.isEmpty
          ? ''
          : '?${result.query.pairs.map((p) => '${p.$1}=${p.$2}').join('&')}')
      ..write(result.fragment.isEmpty ? '' : '#${result.fragment}');
    final authority = scope == 'userinfo'
        ? '$decoded@${result.authority.substring(result.authority.lastIndexOf('@') + 1)}'
        : decoded;
    final relexed = lexUri('${result.scheme}://$authority$tail',
        formId: result.formId);
    if (relexed == null) return null;
    result = relexed;
  }
  return result;
}










QueryPairs _flattenContainer(Map<String, dynamic> doc) => QueryPairs([
      for (final e in doc.entries)
        if (e.value != null && e.value is! Map && e.value is! List)
          (e.key, '${e.value}'),
    ]);










Map<String, dynamic>? _decodeFormJson(MapperForm form, String decoded) {
  if (!form.decode.contains('json')) return null;
  var payload = _splitScheme(decoded)?.payload ?? decoded;






  final hash = payload.indexOf('#');
  if (hash >= 0) payload = payload.substring(0, hash);
  try {
    final parsed = jsonDecode(payload.trim());
    if (parsed is Map) return parsed.cast<String, dynamic>();
  } catch (_) {


  }
  return null;
}


abstract final class _RunDecode {






  static List<int>? bytes(String raw) {
    final trimmed = raw.replaceAll(RegExp(r'=+$'), '');
    if (trimmed.isEmpty) return null;
    final values = <int>[];
    for (final unit in trimmed.codeUnits) {
      final v = _b64Value(unit);
      if (v == null) return null;
      values.add(v);
    }

    final rem = values.length % 4;
    if (rem == 1) return null;

    final out = <int>[];
    var i = 0;
    while (i + 4 <= values.length) {
      final n = (values[i] << 18) |
          (values[i + 1] << 12) |
          (values[i + 2] << 6) |
          values[i + 3];
      out..add((n >> 16) & 0xFF)..add((n >> 8) & 0xFF)..add(n & 0xFF);
      i += 4;
    }
    if (rem == 2) {
      out.add(((values[i] << 2) | (values[i + 1] >> 4)) & 0xFF);
    } else if (rem == 3) {
      final n = (values[i] << 10) | (values[i + 1] << 4) | (values[i + 2] >> 2);
      out..add((n >> 8) & 0xFF)..add(n & 0xFF);
    }
    return out;
  }

  static int? _b64Value(int unit) {
    if (unit >= 0x41 && unit <= 0x5A) return unit - 0x41;
    if (unit >= 0x61 && unit <= 0x7A) return unit - 0x61 + 26;
    if (unit >= 0x30 && unit <= 0x39) return unit - 0x30 + 52;
    if (unit == 0x2B || unit == 0x2D) return 62;
    if (unit == 0x2F || unit == 0x5F) return 63;
    return null;
  }

  static String? base64(String raw) {
    try {
      var s = raw.replaceAll('-', '+').replaceAll('_', '/');
      final pad = s.length % 4;
      if (pad != 0) s = s.padRight(s.length + (4 - pad), '=');






      return decodeUtf8Lenient(_b64.decode(s));
    } catch (_) {
      return null;
    }
  }
}






bool formMatchesText(Map<String, dynamic>? d, String text) {
  if (d == null || d['default'] == true) return true;


  final payload = _splitScheme(text)?.payload ?? text;
  final schemeIn = (d['scheme_in'] as List?)?.cast<String>();
  if (schemeIn != null) {
    final colon = text.indexOf(':');
    final scheme = colon > 0 ? text.substring(0, colon).toLowerCase() : '';
    if (!schemeIn.any((s) => s.toLowerCase() == scheme)) return false;
  }
  final re = d['regex'] as String?;
  if (re != null && !RegExp(re).hasMatch(payload)) return false;
  final txt = (d['text'] as Map?)?.cast<String, dynamic>();
  if (txt != null) {
    final prefix = txt['prefix_fold'] as String?;



    if (prefix != null) {
      final p = prefix.toLowerCase();
      if (!payload.toLowerCase().startsWith(p) &&
          !text.toLowerCase().startsWith(p)) {
        return false;
      }
    }





    final contains = txt['contains'] as String?;
    if (contains != null &&
        !payload.contains(contains) &&
        !text.contains(contains)) {
      return false;
    }



    final prefixTrim = txt['prefix_trim'] as String?;
    if (prefixTrim != null && !payload.trimLeft().startsWith(prefixTrim)) {
      return false;
    }



    final minLen = (txt['min_len'] as num?)?.toInt();
    if (minLen != null && payload.replaceAll(RegExp(r'\s+'), '').length < minLen) {
      return false;
    }
  }



  final ini = (d['ini'] as Map?)?.cast<String, dynamic>();
  if (ini != null) {
    final want = (ini['first_section_fold'] as String?)?.toLowerCase();
    if (want != null && _firstIniSection(text)?.toLowerCase() != want) {
      return false;
    }
  }



  final not = d['not'];
  if (not is Map && formMatchesText(not.cast<String, dynamic>(), text)) {
    return false;
  }
  final all = d['all'];
  if (all is List) {
    for (final sub in all) {
      if (sub is! Map) continue;
      if (!formMatchesText(sub.cast<String, dynamic>(), text)) return false;
    }
  }
  final any = d['any'];
  if (any is List && any.isNotEmpty) {
    var hit = false;
    for (final sub in any) {
      if (sub is! Map) continue;
      if (formMatchesText(sub.cast<String, dynamic>(), text)) {
        hit = true;
        break;
      }
    }
    if (!hit) return false;
  }
  return true;
}



String? _firstIniSection(String text) {
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final l = raw.trim();
    if (l.isEmpty) continue;
    if (l.startsWith('#') || l.startsWith('//') || l.startsWith(';')) continue;
    if (l.startsWith('[') && l.endsWith(']')) {
      return l.substring(1, l.length - 1).trim();
    }
    return null;
  }
  return null;
}















bool detectMatchesIni(Map<String, dynamic>? d, Map<String, String> space) {
  if (d == null || d['default'] == true) return true;
  final ini = (d['ini'] as Map?)?.cast<String, dynamic>();
  if (ini == null) return d.isEmpty;

  bool hasKey(String key) {
    final want = key.toLowerCase();


    if (want.contains('.')) return space.containsKey(want);
    return space.keys.any((k) {
      final dot = k.lastIndexOf('.');
      return dot >= 0 && k.substring(dot + 1) == want;
    });
  }

  final sections = (ini['sections'] as List?)?.cast<String>();
  if (sections != null) {
    for (final s in sections) {
      final want = '${s.toLowerCase()}.';
      if (!space.keys.any((k) => k.startsWith(want))) return false;
    }
  }
  final keysAny = (ini['keys_any'] as List?)?.cast<String>();
  if (keysAny != null && keysAny.isNotEmpty && !keysAny.any(hasKey)) {
    return false;
  }
  final keysAll = (ini['keys_all'] as List?)?.cast<String>();
  if (keysAll != null && !keysAll.every(hasKey)) return false;
  return true;
}






















bool detectMatchesJson(Map<String, dynamic>? d, dynamic value) {
  if (d == null || d['default'] == true) return true;










  final topAll = d['all'];
  if (topAll is List) {
    for (final sub in topAll) {
      if (sub is! Map) continue;
      if (!detectMatchesJson(sub.cast<String, dynamic>(), value)) return false;
    }
  }
  final topAny = d['any'];
  if (topAny is List && topAny.isNotEmpty) {
    var hit = false;
    for (final sub in topAny) {
      if (sub is! Map) continue;
      if (detectMatchesJson(sub.cast<String, dynamic>(), value)) {
        hit = true;
        break;
      }
    }
    if (!hit) return false;
  }
  final topNot = d['not'];
  if (topNot is Map &&
      detectMatchesJson(topNot.cast<String, dynamic>(), value)) {
    return false;
  }

  final j = (d['json'] as Map?)?.cast<String, dynamic>();
  if (j == null) {


    if (d.containsKey('json')) return false;
    final combinatorsOnly = d.keys.every(
      (k) => k == 'all' || k == 'any' || k == 'not',
    );
    return d.isEmpty || combinatorsOnly;
  }
  final valueOf = (j['value_of'] as Map?)?.cast<String, dynamic>();
  if (valueOf != null) {
    for (final e in valueOf.entries) {
      final actual = jsonPathValue(value, e.key);
      if (actual == null) return false;
      if (!_scalarEq(actual, e.value)) return false;
    }
  }
  final valueIn = (j['value_in'] as Map?)?.cast<String, dynamic>();
  if (valueIn != null) {
    for (final e in valueIn.entries) {
      final actual = jsonPathValue(value, e.key);
      if (actual == null) return false;
      final set = (e.value as List?) ?? const [];
      if (!set.any((v) => _scalarEq(actual, v))) return false;
    }
  }



  final hasKey = ((j['required_keys'] ?? j['has_key']) as List?)?.cast<String>();
  if (hasKey != null) {
    for (final path in hasKey) {
      if (jsonPathValue(value, path) == null) return false;
    }
  }


  final anyOfKeys = (j['any_keys'] as List?)?.cast<String>();
  if (anyOfKeys != null && anyOfKeys.isNotEmpty) {
    if (!anyOfKeys.any((p) => jsonPathValue(value, p) != null)) return false;
  }





  final keyAbsent = (j['key_absent'] as List?)?.cast<String>();
  if (keyAbsent != null) {
    for (final path in keyAbsent) {
      if (jsonPathValue(value, path) != null) return false;
    }
  }
  final anyKeys = (j['array_elem_any_keys'] as List?)?.cast<String>();
  if (anyKeys != null) {
    for (final path in anyKeys) {
      if (!_anyElemHas(value, path)) return false;
    }
  }
  final type = j['type'] as String?;
  if (type != null && !_isJsonType(value, type)) return false;
















  final typeOf = (j['type_of'] as Map?)?.cast<String, dynamic>();
  if (typeOf != null) {
    for (final e in typeOf.entries) {
      final actual = jsonPathValue(value, e.key);
      if (actual == null) return false;
      if (!_isJsonType(actual, '${e.value}')) return false;
    }
  }



  final any = j['any'];
  if (any is List && any.isNotEmpty) {
    var hit = false;
    for (final sub in any) {
      if (sub is! Map) continue;
      if (detectMatchesJson(sub.cast<String, dynamic>(), value)) {
        hit = true;
        break;
      }
    }
    if (!hit) return false;
  }
  final all = j['all'];
  if (all is List) {
    for (final sub in all) {
      if (sub is! Map) continue;
      if (!detectMatchesJson(sub.cast<String, dynamic>(), value)) return false;
    }
  }
  final not = j['not'];
  if (not is Map && detectMatchesJson(not.cast<String, dynamic>(), value)) {
    return false;
  }
  return true;
}




bool _isJsonType(dynamic value, String type) => switch (type) {
      'object' => value is Map,
      'array' => value is List,
      'string' => value is String,
      'number' => value is num,
      'bool' => value is bool,
      _ => false,
    };







bool _anyElemHas(dynamic root, String path) {
  final marker = path.indexOf('[]');
  if (marker < 0) return jsonPathValue(root, path) != null;
  final arrayPath = path.substring(0, marker);
  final rest = path.substring(marker + 2).replaceFirst(RegExp(r'^\.'), '');
  final arr = arrayPath.isEmpty ? root : jsonPathValue(root, arrayPath);
  if (arr is! List) return false;
  for (final el in arr) {
    if (rest.isEmpty) return true;
    if (_anyElemHas(el, rest)) return true;
  }
  return false;
}

bool _scalarEq(dynamic actual, dynamic expected) {
  if (actual is bool || expected is bool) return actual == expected;
  if (actual is num && expected is num) return actual == expected;
  return actual.toString() == expected.toString();
}






dynamic jsonPathValue(dynamic root, String path) {





  if (path.trim() == r'$root') return root;
  dynamic cur = root;
  for (final seg in path.split('.')) {
    if (seg.isEmpty) continue;

    final sel = _parseSelector(seg);
    if (sel != null) {
      final list = cur is Map ? cur[sel.name] : null;
      if (list is! List) return null;
      cur = null;
      for (final el in list) {
        if (_selectorMatches(el, sel)) {
          cur = el;
          break;
        }
      }
      if (cur == null) return null;
      continue;
    }
    if (cur is Map) {
      cur = cur[seg];
    } else if (cur is List) {
      final i = int.tryParse(seg);
      if (i == null || i < 0 || i >= cur.length) return null;
      cur = cur[i];
    } else {
      return null;
    }
    if (cur == null) return null;
  }
  return cur;
}


typedef _Selector = ({String name, String key, String value});

final RegExp _kSelectorRe = RegExp(r'^([^\[\]=]+)\[([^\[\]=]+)=([^\[\]]*)\]$');
final Map<String, _Selector?> _selectorCache = {};

_Selector? _parseSelector(String seg) {
  if (!seg.endsWith(']')) return null;
  return _selectorCache.putIfAbsent(seg, () {
    final m = _kSelectorRe.firstMatch(seg);
    if (m == null) return null;
    return (name: m.group(1)!, key: m.group(2)!, value: m.group(3)!);
  });
}



bool _selectorMatches(dynamic el, _Selector sel) {
  if (el is! Map) return false;
  final v = el[sel.key];
  if (v == null || v is Map || v is List) return false;
  return v.toString().toLowerCase() == sel.value.toLowerCase();
}




List<String> expandSelectorPaths(dynamic root, String path) {
  if (!path.contains('[')) return [path];
  var prefixes = <({String path, dynamic node})>[(path: '', node: root)];
  for (final seg in path.split('.')) {
    if (seg.isEmpty) continue;
    final sel = _parseSelector(seg);
    final next = <({String path, dynamic node})>[];
    for (final p in prefixes) {
      final base = p.path.isEmpty ? '' : '${p.path}.';
      if (sel == null) {
        final node = p.node;
        dynamic child;
        if (node is Map) {
          child = node[seg];
        } else if (node is List) {
          final i = int.tryParse(seg);
          if (i != null && i >= 0 && i < node.length) child = node[i];
        }
        next.add((path: '$base$seg', node: child));
        continue;
      }
      final list = p.node is Map ? (p.node as Map)[sel.name] : null;
      if (list is! List) continue;
      for (var i = 0; i < list.length; i++) {
        if (_selectorMatches(list[i], sel)) {
          next.add((path: '$base${sel.name}.$i', node: list[i]));
        }
      }
    }
    prefixes = next;
    if (prefixes.isEmpty) break;
  }
  return [for (final p in prefixes) p.path];
}



const Set<String> _kListNormalizers = {'port_range_spec', 'cidr_prefix'};



final RegExp _kUintRe = RegExp(r'^\d+$');













final class _SectionPlan {
  _SectionPlan(MapperSection section)
      : selectors = _pass(section, selector: true),
        dependents = _pass(section, selector: false),
        declared = _declaredOf(section),
        declaredIni = _declaredIniOf(section),
        declaredJson = _declaredJsonOf(section),
        labelKeys = _labelKeysOf(section);


  final List<MapperParam> selectors;


  final List<MapperParam> dependents;



  late final List<MapperParam> all = [...selectors, ...dependents];














  final Set<String> declared;


  final Set<String> declaredIni;



  final Set<String> declaredJson;



  final Set<String> labelKeys;



  static List<MapperParam> _pass(MapperSection s, {required bool selector}) {
    final all = s.params.values.toList();








    final picked = [
      for (var i = 0; i < all.length; i++)
        if (all[i].selector == selector) i,
    ];
    picked.sort((a, b) {
      final pa = all[a].priority ?? 0;
      final pb = all[b].priority ?? 0;
      if (pa != pb) return pa.compareTo(pb);
      return a.compareTo(b);
    });
    return [for (final i in picked) all[i]];
  }

  static Set<String> _declaredOf(MapperSection section) {
    final out = <String>{};
    for (final p in section.params.values) {
      for (final s in p.spellings) {
        out.add(s.toLowerCase());
      }


      final sources = [
        ...p.source,
        for (final l in p.sourceByForm.values) ...l,
      ];
      for (final src in sources) {
        if (src.startsWith('query.')) {
          out.add(src.substring('query.'.length).toLowerCase());
        }
      }
    }






    for (final o in section.overlays) {
      for (final src in o.source) {
        if (src.startsWith('query.')) {
          out.add(src.substring('query.'.length).toLowerCase());
        }
      }
    }
    return out;
  }

  static Set<String> _declaredIniOf(MapperSection section) {
    final out = <String>{};
    void declare(String src) {
      if (!src.startsWith('ini.')) return;
      final rest = src.substring('ini.'.length);

      if (rest.startsWith(r'$')) return;
      if (rest.split('.').length != 2) return;
      out.add(rest.toLowerCase());
    }

    for (final p in section.params.values) {
      for (final src in p.source) {
        declare(src);
      }
      for (final l in p.sourceByForm.values) {
        for (final src in l) {
          declare(src);
        }
      }
    }
    for (final src in section.label.source) {
      declare(src);
    }
    for (final l in section.label.sourceByForm.values) {
      for (final src in l) {
        declare(src);
      }
    }
    return out;
  }

  static Set<String> _declaredJsonOf(MapperSection section) {
    final out = <String>{};
    for (final p in section.params.values) {
      final sources = [
        ...p.source,
        for (final l in p.sourceByForm.values) ...l,
      ];
      for (final src in sources) {
        if (!src.startsWith('json.')) continue;
        final rest = src.substring('json.'.length);
        final dot = rest.indexOf('.');
        out.add((dot < 0 ? rest : rest.substring(0, dot)).toLowerCase());
      }
    }
    return out;
  }

  static Set<String> _labelKeysOf(MapperSection section) {
    final out = <String>{};
    final byForm = section.label.sourceByForm;
    final sources = [
      ...section.label.source,
      for (final l in byForm.values) ...l,
    ];
    for (final src in sources) {
      if (!src.startsWith('json.')) continue;
      final rest = src.substring('json.'.length);
      final dot = rest.indexOf('.');
      out.add((dot < 0 ? rest : rest.substring(0, dot)).toLowerCase());
    }
    return out;
  }
}



final Expando<_SectionPlan> _planCache = Expando<_SectionPlan>('mapper plan');







final Map<String, List<String>> _segCache = {};

List<String> _segments(String path) => _segCache[path] ??= path.split('.');


final class _Run {
  _Run(this.section, this.space, this._trace,
      {this.nameHint, XrayDropVerdict? dropped, this.context, this.document})
      : _plan = _planCache[section] ??= _SectionPlan(section),
        _dropped = dropped;





  final Map<String, dynamic>? context;




  final List<dynamic>? document;



  final Map<String, Object?> _refs = {};


  final _SectionPlan _plan;




  final String? nameHint;




  final MapperTrace? _trace;


  final XrayDropVerdict? _dropped;


  String get _mapperId =>
      '${section.singboxType}.${section.kind}'
      '${space.formId.isEmpty ? '' : '.${space.formId}'}';

  final MapperSection section;
  SourceSpace space;

  final Map<String, dynamic> body = {};
  final Map<String, dynamic> extensionFields = {};
  final List<NodeWarning> warnings = [];



  final Map<String, int> _writtenBy = {};



  final Set<String> _consumed = {};

  bool _wsEarlyDataHeaderImplicit = false;



  dynamic _schemeDefaultPort;



  bool _dropNode = false;


  final Map<String, QueryPairs> _overlays = {};






















  final Set<String> _flattened = {};




  EngineResult? execute({List<String> inputCodes = const []}) {








    _trace?.add(
      stage: TraceStage.elemDetect,
      mapper: _mapperId,
      entry: r'$form',
      src: section.kind,
      val: space.formId,
      act: TraceAct.keep,
    );
    for (final code in inputCodes) {
      warnings.add(NodeWarning.byCode(code, path: '', value: ''));
    }
    body['type'] = section.singboxType;



    _buildOverlays();









    final schemeAll = section.schemeSets['*'];
    if (schemeAll is Map) _applySets(schemeAll.cast<String, dynamic>(), null);

    final schemeSet = _lookupFold(section.schemeSets, space.scheme);
    if (schemeSet is Map) _applySets(schemeSet.cast<String, dynamic>(), null);







    if (!_applyUserinfo()) return null;


    for (final p in _plan.selectors) {
      _applyParam(p);
      if (_dropNode) return null;
    }
    for (final p in _plan.dependents) {
      _applyParam(p);
      if (_dropNode) return null;
    }


    for (final p in _plan.all) {
      _applyDefaults(p);
    }










    for (final e in section.defaults.entries) {


      if (e.key.startsWith(DraftNames.serviceParamPrefix)) continue;
      if (_read(e.key) != null) {
        _trace?.add(
          stage: TraceStage.defaults,
          mapper: _mapperId,
          entry: r'$defaults',
          val: e.value,
          path: e.key,
          act: TraceAct.skip,
          why: TraceWhy.byDefault,
        );
        continue;
      }
      _put(e.key, e.value);
      _trace?.add(
        stage: TraceStage.defaults,
        mapper: _mapperId,
        entry: r'$defaults',
        val: e.value,
        path: e.key,
        act: TraceAct.write,
        why: TraceWhy.byDefault,
      );
    }



    if (_schemeDefaultPort != null && _read('server_port') == null) {
      _put('server_port', _schemeDefaultPort);
    }


    for (final p in _plan.all) {
      if (!p.required) continue;









      final paths = <String>[
        if (p.mapsTo != null) p.mapsTo!,
        ...p.splitInto.keys,
        ...?p.extract?.into.values.map(
          (v) => v is Map ? v['path'] as String? ?? '' : '$v',
        ),



        if (p.onNoMatch['action'] == 'take_all' &&
            p.onNoMatch['into'] is String)
          p.onNoMatch['into'] as String,
      ]..removeWhere((s) => s.isEmpty);
      if (paths.isEmpty) continue;
      final any = paths.any((path) {
        final v = _read(path);
        return v != null && !(v is String && v.isEmpty);
      });
      if (!any) {
        _rejectFieldMissing(bodyPath: paths.first, param: p);
        return null;
      }
    }


    _reportUnknown();

    final label = _label();
    _trace?.add(
      stage: TraceStage.label,
      mapper: _mapperId,
      entry: r'$label',
      val: label,
      act: label.isEmpty ? TraceAct.skip : TraceAct.write,
      why: label.isEmpty ? TraceWhy.empty : TraceWhy.none,
    );




    _trace?.add(
      stage: TraceStage.result,
      mapper: _mapperId,
      entry: r'$result',
      val: {
        'body': body,
        'label': label,
        'body_source': section.bodySource,
      },
      act: TraceAct.keep,
    );

    return EngineResult(
      body: body,
      label: label,
      warnings: warnings,
      extensionFields: extensionFields,
      wsEarlyDataHeaderImplicit: _wsEarlyDataHeaderImplicit,
      tagScheme: section.label.fallbackScheme,
      bodySource: section.bodySource,
      tagAddress: _tagAddress(),
      kinds: _kinds(),
    );
  }






  Set<String> _kinds() {
    if (section.kindWhen.isEmpty) return const {};
    final out = <String>{};
    for (final e in section.kindWhen.entries) {
      final cond = (e.value as Map?)?.cast<String, dynamic>();
      if (cond != null && _whenHolds(cond)) out.add(e.key);
    }
    return out;
  }





  (String, int)? _tagAddress() {
    final sPath = section.label.fallbackServerPath;
    if (sPath == null) return null;
    final server = _read(sPath);
    if (server == null) return null;
    final pPath = section.label.fallbackPortPath;
    final port = pPath == null ? null : _read(pPath);
    return ('$server', port is num ? port.toInt() : 0);
  }














  void _buildOverlays() {
    for (final o in section.overlays) {
      if (o.name.isEmpty) continue;
      String? text;









      Map<String, dynamic>? direct;
      for (final src in o.source) {
        final v = _readSourceBare(src);
        if (v is Map) {
          direct = v.cast<String, dynamic>();
          _consumeOverlaySource(src);
          break;
        }
        if (v is String && v.isNotEmpty) {
          text = v;
          _consumeOverlaySource(src);
          break;
        }
      }
      if (direct != null) {
        _overlays[o.name] = QueryPairs(_overlayPairs(direct, o.flatten));
        continue;
      }
      if (text == null) continue;
      for (final step in o.decode) {
        switch (step) {
          case 'percent':
            text = percentDecodeOnce(text!, mode: DecodeMode.query);
          case 'base64':
          case 'base64?':
            final decoded = _tryBase64(text!);
            if (decoded != null) {
              text = decoded;
            } else if (step == 'base64') {
              text = null;
            }
        }
        if (text == null) break;
      }
      if (text == null) continue;
      Object? parsed;
      try {
        parsed = jsonDecode(text);
      } catch (_) {
        continue;
      }
      if (parsed is! Map) continue;
      _overlays[o.name] =
          QueryPairs(_overlayPairs(parsed.cast<String, dynamic>(), o.flatten));
    }
  }







  void _consumeOverlaySource(String src) {
    if (src.startsWith('query.')) {
      _consumeSpelling(src.substring('query.'.length));
      return;
    }
    if (src.startsWith('json.')) {
      _consumeJson(_resolveBase(src.substring('json.'.length)));
    }
  }




  List<(String, String)> _overlayPairs(
    Map<String, dynamic> obj,
    List<String> flatten,
  ) {
    final pairs = <(String, String)>[];
    void put(String k, Object? v) {
      if (v == null || v is Map || v is List) return;
      pairs.add((k, '$v'));
    }

    for (final e in obj.entries) {
      if (flatten.contains(e.key) && e.value is Map) {
        for (final f in (e.value as Map).cast<String, dynamic>().entries) {
          put(f.key, f.value);
        }
      } else {
        put(e.key, e.value);
      }
    }
    return pairs;
  }












  void _applyFlatten(MapperParam p) {
    for (final src in _sourcesOf(p)) {
      if (!src.startsWith('json.')) continue;
      final path = _resolveBase(src.substring('json.'.length));
      final owner = jsonPathValue(space.json, path);
      if (owner is! Map) continue;
      for (final name in p.flatten) {
        if (!_flattened.add(name)) continue;









        final sources = <Map>[
          if (_overlayRaw[name] is Map) _overlayRaw[name]! as Map,
          if (owner[name] is Map) owner[name] as Map,
        ];
        if (sources.isEmpty) continue;
        final pairs = <(String, String)>[];
        for (final inner in sources) {
          for (final e in inner.cast<String, dynamic>().entries) {
            final v = e.value;
            if (v == null) continue;
            if (v is Map || v is List) {


              _overlayRaw.putIfAbsent(e.key, () => v);
              continue;
            }
            pairs.add((e.key, _scalar(v)));
          }
        }



        final nonEmpty = {
          for (final p in pairs)
            if (p.$2.trim().isNotEmpty) p.$1.toLowerCase(),
        };
        _overlays[name] = QueryPairs([
          for (final p in pairs)
            if (p.$2.trim().isNotEmpty || !nonEmpty.contains(p.$1.toLowerCase()))
              p,
        ]);
      }


      return;
    }
  }



  final Map<String, dynamic> _overlayRaw = {};




  static String _scalar(Object v) {
    if (v is double && v == v.roundToDouble() && v.abs() < 1e15) {
      return v.toInt().toString();
    }
    return '$v';
  }


  Iterable<String> _sourcesOf(MapperParam p) =>
      p.sourceByForm[space.formId] ?? p.source;




  void _rejectFieldMissing({
    required String bodyPath,
    MapperParam? param,
    String? fallbackField,
  }) {
    final descEn = param?.raw['desc_en'] as String?;
    final field = (descEn != null && descEn.isNotEmpty)
        ? descEn
        : (fallbackField ?? bodyPath);
    final w = RegistryWarning(
      code: 'field_missing',
      path: bodyPath,
      params: {'field': field},
    );
    warnings.add(w);
    if (_dropped != null) {
      _dropped.explicit = true;
      _dropped.reason = w;
    }
  }



  bool _applyUserinfo() {
    final u = section.userinfo;
    if (u == null) return true;




    var raw = percentDecodeOnce(space.userinfo, mode: DecodeMode.path);










    final needSep = u.decodeRequiresSeparator;
    final skipDecode = needSep != null && raw.contains(needSep);
    for (final step in u.decode) {
      if (skipDecode && step != 'percent') continue;
      switch (step) {
        case 'percent':

          raw = percentDecodeOnce(raw, mode: DecodeMode.path);
        case 'base64':
        case 'base64?':
          final decoded = _tryBase64(raw);
          if (decoded != null) {

            if (needSep != null && !decoded.contains(needSep)) break;
            raw = decoded;
          } else if (step == 'base64') {
            return false;
          }
        case 'base64_if_no_colon':
          if (!raw.contains(':')) {
            final decoded = _tryBase64(raw);
            if (decoded != null) raw = decoded;
          }
      }
    }

    if (raw.isEmpty) {




      if (u.required) {
        final path =
            u.singleInto ?? (u.into.isNotEmpty ? u.into.first : 'userinfo');
        _rejectFieldMissing(bodyPath: path, fallbackField: path);
        return false;
      }
      if (u.into.isNotEmpty) return true;
    }

    final sep = u.splitSep;
    if (sep == null || !raw.contains(sep)) {





















      final single = u.singleInto;
      if (single != null && raw.isNotEmpty) {
        _write(single, raw, null);
        if (u.into.isNotEmpty && single == u.into.last) {
          space = space.copyWith(userinfoPass: raw);
        } else {
          space = space.copyWith(userinfoUser: raw);
        }
      }
      return true;
    }



    final limit = u.splitLimit;
    List<String> parts;
    if (limit != null && limit > 0) {
      final idx = raw.indexOf(sep);
      parts = [raw.substring(0, idx), raw.substring(idx + sep.length)];
      if (limit == 1) parts = [raw];
    } else {
      parts = raw.split(sep);
    }

    for (var i = 0; i < u.into.length && i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      _write(u.into[i], parts[i], null);
    }
    space = space.copyWith(
      userinfoUser: parts.isNotEmpty ? parts.first : null,
      userinfoPass: parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null,
    );
    return true;
  }



  void _applyParam(MapperParam p) {


    if (p.roundTripOnly == 'emit') return;


    _applyDeref(p);








    if (p.when.containsKey(r'$value')) {
      var own = _valueOfBare(p);
      if (own is String && own.isEmpty) own = null;
      if (!_matches(own, p.when[r'$value'])) {
        _trace?.add(
          stage: TraceStage.field,
          mapper: _mapperId,
          entry: p.name,
          src: '-',
          path: p.mapsTo,
          act: TraceAct.skip,
          why: TraceWhy.whenFalse,
        );
        return;
      }
    }

    if (!_whenHolds(p.when)) {
      _trace?.add(
        stage: TraceStage.field,
        mapper: _mapperId,
        entry: p.name,
        src: p.source.isEmpty ? '-' : p.source.first,
        path: p.mapsTo,
        act: TraceAct.skip,
        why: TraceWhy.whenFalse,
      );





      final code = p.onWhenFalse['code'] as String?;
      if (code != null) {
        final probe = _valueOfBare(p);
        if (probe != null && !(probe is String && probe.isEmpty)) {
          warnings.add(NodeWarning.byCode(code,
              path: p.name, value: probe is String ? probe.trim() : '$probe'));
        }
      }
      return;
    }






    if (p.flatten.isNotEmpty) _applyFlatten(p);





    _applyOnLenGt(p);

    var raw = _applySubstitute(p, _valueOf(p));
    final emptyRaw = raw == null || (raw is String && raw.isEmpty);
    if (emptyRaw) {










      _applyOnEmpty(p);




      if (p.defaultWhen['absent'] == true && p.defaultWhen['value'] != null) {
        raw = p.defaultWhen['value'];
      } else {



        final absentSet = p.sets[''];
        if (absentSet is Map && p.sets.containsKey('')) {
          _applySets(absentSet.cast<String, dynamic>(), p);
        }
        return;
      }
    }


    if (p.onLenGt.isNotEmpty && p.mapsToPresent && p.mapsTo == null) return;

    var value = raw;
















    if (p.onInvalid['action'] == 'default_from' && value is String) {
      final cond = (p.onInvalid['when'] as Map?)?.cast<String, dynamic>();
      final probe = cond == null ? null : cond['value'];
      if (probe != null && _matches(value, probe)) {
        final code = p.onInvalid['code'] as String?;
        if (code != null) {
          warnings.add(
              NodeWarning.byCode(code, path: p.name, value: value.trim()));
        }
        final next = _nextValidSource(p, probe);
        if (next == null) return;
        raw = _applySubstitute(p, next);
        value = raw;
      }
    }


    final de = p.decodeExtra;
    if (de != null && value is String) {
      value = decodeExtra(
        value,
        mode: de.mode == 'path' ? DecodeMode.path : DecodeMode.query,
        passes: de.untilStable ? null : de.passes,
        max: de.max,
      );
    }








    final norm = p.normalize;
    if (norm != null && value is String) {
      if (norm.startsWith('range_order')) {
        final swap = norm.endsWith('swap');
        value = _normalizeRange(value, swap: swap);
        if (value == null) {
          _applyOnInvalid(p, raw is String ? raw : '$raw');
          return;
        }
      } else if (!_kListNormalizers.contains(norm)) {
        value = _normalize(value, norm);
      }
    }





    if (p.mapsToPresent && p.mapsTo == null && p.sets.isEmpty) {



      final off = value is String && p.valueMap.isNotEmpty
          ? _mapValue(p.valueMap, value,
              caseSensitive: p.valueMapCase == 'sensitive')
          : (matched: false, value: value);
      if (!(off.matched && off.value == null)) {
        _applyOnPresent(p, value is String ? value : '$value');
      }
      _applyImplies(p);
      return;
    }









    if (p.extract != null &&
        p.list != null &&
        p.type == 'object' &&
        value is String) {
      _applyExtractItems(p, value);
      return;
    }


    if (p.extract != null && value is String) {
      _applyExtract(p, value);
      return;
    }



    if (p.valueMap.isNotEmpty && value is String) {
      final mapped = _mapValue(p.valueMap, value,
          caseSensitive: p.valueMapCase == 'sensitive');
      if (mapped.matched) {
        if (mapped.value == null) {


          _applyValueSets(p, value);
          _applyImplies(p);
          return;
        }
        value = mapped.value;
      } else if (p.allow.isNotEmpty &&
          p.allow.any((a) => a.trim().toLowerCase() == value.toString().trim().toLowerCase())) {



      } else if (p.sets.isEmpty && p.onNoMatch.isNotEmpty) {




        if (p.onNoMatch['action'] == 'drop_node') return;
        _applyOnNoMatch(p, value);
        _applyImplies(p);
        return;
      } else if (p.sets.isEmpty && p.onInvalid['action'] == 'drop') {














        final w = _applyOnInvalid(p, value.toString());
        if (p.selector) {
          _dropNode = true;


          if (w is RegistryWarning && _dropped != null) {
            _dropped.explicit = true;
            _dropped.reason = w;
          }
        }
        return;
      }
    }


    final hadSets = _applyValueSets(p, raw is String ? raw : '$raw');













    if (hadSets && _setsErasedOwnPath(p, raw is String ? raw : '$raw')) {
      _applyImplies(p);
      return;
    }




    if (!hadSets && p.sets.isNotEmpty && p.onNoMatch.isNotEmpty) {
      if (p.onNoMatch['action'] == 'drop_node') {
        _dropNode = true;
        return;
      }
    }


    var typed = _coerceType(p, value);









    final lspec = p.list;
    if (lspec != null && lspec.item == 'int' && raw is String) {
      final gotInts = typed is List && typed.isNotEmpty;
      if (!gotInts) {
        final bytes = _RunDecode.bytes(raw.trim());
        if (bytes != null && bytes.isNotEmpty) typed = bytes;
      }
    }

    if (typed == null) {






      if (p.onInvalid['action'] == 'keep') {
        typed = value;
      } else {
        _applyOnInvalid(p, raw is String ? raw : '$raw');
        _applyImplies(p);
        return;
      }
    }


    if (norm != null && _kListNormalizers.contains(norm) && typed is List) {
      typed = _normalizeList(typed, norm);
    }







    if (p.splitInto.isNotEmpty && typed is List) {
      _applySplitInto(p, typed);
      _applyImplies(p);
      return;
    }

    if (p.mapsTo != null) {
      _write(p.mapsTo!, typed, p);
    } else if (!hadSets && p.mapsToPresent) {
      _applyOnPresent(p, raw is String ? raw : '$raw');
    }

    _applyImplies(p);
  }






  bool _setsErasedOwnPath(MapperParam p, String value) {
    final target = p.mapsTo;
    if (target == null || p.sets.isEmpty) return false;
    final set = _lookupFold(p.sets, value);
    if (set is! Map) return false;
    final low = target.toLowerCase();
    for (final e in set.cast<String, dynamic>().entries) {
      if (e.value != null) continue;
      final k = e.key.toLowerCase();
      if (low == k || low.startsWith('$k.')) return true;
    }
    return false;
  }


  bool _applyValueSets(MapperParam p, String value) {
    if (p.sets.isEmpty) return false;
    final set = _lookupFold(p.sets, value);
    if (set is! Map) return false;
    _applySets(set.cast<String, dynamic>(), p);
    return true;
  }

  void _applyImplies(MapperParam p) {
    if (p.implies.isEmpty) return;





    final code = p.onImpliesWritten['code'] as String?;
    final before = code == null
        ? null
        : {for (final k in p.implies.keys) k: _read(k)};
    _applySets(p.implies, p);
    if (code != null) {
      for (final e in before!.entries) {
        final now = _read(e.key);
        if (now != null && now != e.value) {
          warnings.add(NodeWarning.byCode(code, path: e.key, value: '$now'));
          break;
        }
      }
    }
    if (p.implicit) _wsEarlyDataHeaderImplicit = true;
  }






  void _applySets(Map<String, dynamic> sets, MapperParam? p) {
    for (final e in sets.entries) {









      if (e.key == r'$default_port') {
        if (e.value != null) _schemeDefaultPort = e.value;
        continue;
      }
      if (e.value == null) {
        _erase(e.key);
      } else {
        _write(e.key, _substituteServiceValue(e.value), p);
      }
    }
  }







  Object? _substituteServiceValue(Object? v) {
    if (v is! String) return v;
    switch (v) {
      case r'$host':
        return space.host;
      default:
        return v;
    }
  }










  void _applyExtractItems(MapperParam p, String value) {
    final spec = p.extract!;
    final re = _regex(spec.re);
    String? keyGroup;
    String? valueGroup;
    for (final e in spec.into.entries) {
      final target = e.value;
      if (target == r'$key') keyGroup = e.key;
      if (target == r'$value') valueGroup = e.key;
    }
    if (keyGroup == null) return;

    final out = <String, dynamic>{};
    var reported = false;
    for (final part in value.split(p.list!.sep)) {
      if (part.trim().isEmpty) continue;
      final m = re.firstMatch(part);
      final k = m?.namedGroup(keyGroup);
      if (m == null || k == null || k.isEmpty) {
        final code = p.onItemInvalid['code'] as String?;
        if (code != null && !reported) {
          reported = true;
          warnings.add(
            NodeWarning.byCode(code, path: p.name, value: part.trim()),
          );
        }
        continue;
      }
      out[k] = valueGroup == null ? '' : (m.namedGroup(valueGroup) ?? '');
    }
    if (out.isEmpty) return;





    final result = p.sortKeys
        ? <String, dynamic>{
            for (final k in out.keys.toList()..sort()) k: out[k],
          }
        : out;
    if (p.mapsTo != null) _write(p.mapsTo!, result, p);
    _applyImplies(p);
  }

  void _applyExtract(MapperParam p, String value) {
    final spec = p.extract!;
    final m = _regex(spec.re).firstMatch(value);
    if (m == null) {





      if (p.onNoMatch['action'] != 'take_all') return;
      final into = p.onNoMatch['into'] as String?;
      if (into == null) return;
      _write(into, value, p);
      final defaults = (p.onNoMatch['defaults'] as Map?)?.cast<String, dynamic>();
      if (defaults != null) {
        for (final e in defaults.entries) {
          if (_read(e.key) == null) _put(e.key, e.value);
        }
      }
      _applyImplies(p);
      return;
    }





    var converted = false;
    for (final e in spec.into.entries) {
      String? group;
      try {
        group = m.namedGroup(e.key);
      } catch (_) {
        group = null;
      }
      if (group == null || group.isEmpty) continue;
      final target = e.value;
      if (target is String) {
        _write(target, group, p);
      } else if (target is Map) {
        final t = target.cast<String, dynamic>();
        final path = t['path'] as String?;
        if (path == null) continue;
        dynamic typed = t['type'] == 'int' ? int.tryParse(group.trim()) : group;
        if (typed == null) continue;


        if (typed is int && typed <= 0) continue;











        final prependFrom = t['prepend_group'] as String?;
        if (prependFrom != null && typed is String) {
          String? head;
          try {
            head = m.namedGroup(prependFrom);
          } catch (_) {
            head = null;
          }
          if (head != null) typed = '$head$typed';
        }
        final memberNorm = t['normalize'] as String?;
        if (memberNorm != null && typed is String) {
          if (_kListNormalizers.contains(memberNorm)) {
            final sep = (t['sep'] as String?) ?? ',';
            typed = _normalizeList(
              typed.split(sep).where((s) => s.trim().isNotEmpty).toList(),
              memberNorm,
            );
            if ((typed as List).isEmpty) continue;
          } else if (memberNorm.startsWith('range_order')) {
            typed = _normalizeRange(typed, swap: memberNorm.endsWith('swap'));
            if (typed == null) continue;
          } else {
            typed = _normalize(typed, memberNorm);
          }
        }
        _write(path, typed, p);


        converted = true;
        _convertedValue = '$typed';




        _memberCode ??= t['code'] as String?;
        final implies = (t['implies'] as Map?)?.cast<String, dynamic>();
        if (implies != null) {
          for (final i in implies.entries) {
            final iv = i.value;
            if (iv is Map && iv['implicit'] == true) {


              _wsEarlyDataHeaderImplicit = true;
              _writeIfAbsent(i.key, iv['value'], p);
            } else {
              _writeIfAbsent(i.key, iv, p);
            }
          }
        }
      }
    }

    if (converted) {
      final mc = _memberCode;
      _memberCode = null;
      if (mc != null) {
        warnings
            .add(NodeWarning.byCode(mc, path: p.name, value: _convertedValue));
      } else {
        _applyOnPresent(p, _convertedValue);
      }
    }
  }


  String? _memberCode;



  String _convertedValue = '';











  void _applyOnPresent(MapperParam p, String raw) {
    final code = p.onPresent['code'] as String? ?? p.onInvalid['code'] as String?;
    if (code == null) return;
    var shown = raw.trim();
    final ex = p.extract;
    if (ex != null) {
      final m = _regex(ex.re).firstMatch(shown);
      final first = ex.into.keys.isEmpty ? null : ex.into.keys.first;
      if (m != null && first != null) {
        shown = m.namedGroup(first) ?? shown;
      }
    }
    warnings.add(NodeWarning.byCode(code, path: p.name, value: shown));
  }







  void _applySplitInto(MapperParam p, List<dynamic> items) {
    for (final e in p.splitInto.entries) {
      final spec = (e.value as Map?)?.cast<String, dynamic>();
      if (spec == null) continue;
      final cond = (spec['when'] as Map?)?.cast<String, dynamic>();
      final probe = cond == null ? null : cond['item'];
      final hits = [
        for (final it in items)
          if (probe == null || _matches(it, probe)) it,
      ];
      if (hits.isEmpty) continue;
      _write(e.key, spec['take'] == 'first' ? hits.first : hits, p);
    }
  }


  void _applyOnNoMatch(MapperParam p, String raw) {
    final code = p.onNoMatch['code'] as String?;
    if (code == null) return;
    warnings.add(NodeWarning.byCode(code, path: p.name, value: raw.trim()));
  }









  NodeWarning? _applyOnInvalid(MapperParam p, String raw) {
    final code = p.onInvalid['code'] as String?;
    if (code == null) return null;
    final w = NodeWarning.byCode(code, path: p.name, value: raw.trim());
    warnings.add(w);
    return w;
  }






  void _applyOnEmpty(MapperParam p) {
    final code = p.onEmpty['code'] as String?;
    if (code == null) return;
    warnings.add(NodeWarning.byCode(code, path: p.name, value: ''));
  }







  void _applyOnLenGt(MapperParam p) {
    if (p.onLenGt.isEmpty) return;
    if ((p.onLenGt['action'] as String?) != 'note') return;
    final code = p.onLenGt['code'] as String?;
    if (code == null) return;
    final n = (p.onLenGt['n'] as num?)?.toInt() ?? 1;
    if (n <= 0) return;
    final sources = p.sourceByForm.isNotEmpty
        ? (p.sourceByForm[space.formId] ?? const <String>[])
        : p.source;
    for (final src in sources) {
      final raw = _readSource(src, p);
      if (raw is! List || raw.length <= n) continue;
      warnings.add(
          NodeWarning.byCode(code, path: p.name, value: '${raw.length}'));
      return;
    }
  }




  dynamic _valueOf(MapperParam p) {
    final sources = p.sourceByForm.isNotEmpty
        ? (p.sourceByForm[space.formId] ?? const <String>[])
        : p.source;
    for (final src in sources) {
      final v = _readSource(src, p);
      if (v == null) continue;
      if (v is String && v.isEmpty && p.empty != 'significant') continue;
      return v;
    }
    return null;
  }




  dynamic _nextValidSource(MapperParam p, Object probe) {
    final sources = p.sourceByForm.isNotEmpty
        ? (p.sourceByForm[space.formId] ?? const <String>[])
        : p.source;
    var hit = false;
    for (final src in sources) {
      final v = _readSource(src, p);
      if (v == null) continue;
      if (v is String && v.isEmpty && p.empty != 'significant') continue;
      if (!hit) {
        hit = true;
        continue;
      }
      if (v is String && _matches(v, probe)) continue;
      return v;
    }
    return null;
  }

  dynamic _readSource(String src, MapperParam p) {
    if (src.startsWith('query.')) {
      final name = src.substring('query.'.length);



      final names = name == p.name ? p.spellings : [name];
      String? found;
      for (final n in names) {
        final v = space.query.get(n);
        if (v == null) continue;
        _consumeSpelling(n);
        found ??= v;
      }
      if (found == null) return null;
      return _decodeQueryValue(found, p);
    }
    switch (src) {
      case 'scheme':
        return space.scheme;
      case 'authority':
        return space.authority;



      case 'userinfo':
        return _decodeQueryValue(space.userinfo, p);
      case 'userinfo.user':
        final u = space.userinfoUser;
        return u == null ? null : _decodeQueryValue(u, p);
      case 'userinfo.pass':
        final pw = space.userinfoPass;
        return pw == null ? null : _decodeQueryValue(pw, p);
      case 'host':
        return space.host;
      case 'port':
        return space.port;
      case 'port_raw':
        return space.portRaw;
      case 'path':
        return space.path;
      case 'fragment':
        return space.fragment;
    }
    final layered = _readContextOrRef(src);
    if (layered.hit) return layered.value;
    if (src.startsWith('json.')) {
      final path = _resolveBase(src.substring('json.'.length));
      _consumeJson(path);
      return jsonPathValue(space.json, path);
    }
    if (src.startsWith('ini.')) {
      return space.ini?[src.substring('ini.'.length).toLowerCase()];
    }


    final dot = src.indexOf('.');
    if (dot > 0) {
      final layer = _overlays[src.substring(0, dot)];
      if (layer != null) return layer.get(src.substring(dot + 1));
    }
    return null;
  }





  String _resolveBase(String path) {
    if (!path.contains(DraftNames.baseAnchor)) return path;
    final base = space.jsonBase ?? '';
    final out = path.replaceAll(DraftNames.baseAnchor, base);

    return out.startsWith('.') ? out.substring(1) : out;
  }







  void _consumeJson(String path) {
    _consumed.add('json.$path'.toLowerCase());
    final dot = path.indexOf('.');
    _consumed.add('json.${dot < 0 ? path : path.substring(0, dot)}'
        .toLowerCase());
  }












  String _decodeQueryValue(String raw, MapperParam p) {
    final pathMode = p.decodeExtra?.mode == 'path';









    if (p.format == 'pem') {
      final decoded = percentDecodeOnce(raw, mode: DecodeMode.path);
      return decoded
          .split('\n')
          .map((line) {
            final t = line.trimLeft();
            return t.startsWith('-----') ? line.replaceAll('+', ' ') : line;
          })
          .join('\n');
    }
    return percentDecodeOnce(
      raw,
      mode: p.plusLiteral || pathMode ? DecodeMode.path : DecodeMode.query,
    );
  }

  void _consumeSpelling(String name) {
    _consumed.add(name.toLowerCase());
  }



  void _applyDefaults(MapperParam p) {
    final path = p.mapsTo;
    if (path == null) return;
    final present = _read(path) != null;



    if (!present && p.defaultFrom.isNotEmpty && _whenHolds(p.when)) {
      for (final src in p.defaultFrom) {




        var v = src.startsWith('body.')
            ? _read(src.substring('body.'.length))
            : _readSource(src, p);







        if ((v == null || (v is String && v.isEmpty)) &&
            !src.startsWith('body.')) {
          final bv = _read(src);
          if (bv is String || bv is num) v = '$bv';
        }
        if (v == null) continue;
        if (v is String && v.isEmpty) continue;




        _write(path, p.coerceScalarToList && v is! List ? [v] : v, p);
        break;
      }
    }


    if (p.defaultWhen.isNotEmpty && _whenHolds(p.when)) {
      final absent = p.defaultWhen['absent'] == true;
      if ((absent && _read(path) == null) ||
          (!absent && _read(path) == null)) {
        final v = p.defaultWhen['value'];
        if (v != null) _write(path, v, p);
      }
    }




    if (p.materializeDefault && _read(path) == null) {




      final v = p.defaultWhen['value'] ??
          section.defaults[path] ??
          p.valueMap[''];
      if (v != null) _write(path, v, p);
    }






    final omit = p.raw['omit_default'];
    if (omit != null && omit is! List && omit is! Map) {
      final v = _read(path);
      if (v != null && v is! Map && v is! List && '$v' == '$omit') {
        _erase(path);
      }
    }
  }





  bool _whenHolds(Map<String, dynamic> when) {
    if (when.isEmpty) return true;
    for (final e in when.entries) {
      final key = e.key;









      if (key.startsWith(r'$') && key != r'$type' && key != r'$form') continue;
      if (key == 'any_set') {
        final names = (e.value as List?)?.cast<String>() ?? const <String>[];
        if (!names.any((n) => _readSourceBare(n) != null)) return false;
        continue;
      }
      dynamic actual;
      if (key == r'$type') {
        actual = section.singboxType;
      } else if (key == r'$form') {
        actual = space.formId;
      } else if (key.startsWith('query.') ||
          key.startsWith('json.') ||
          key.startsWith('ini.') ||
          key.startsWith('context.') ||
          key.startsWith('ref.') ||
          _kLexicalSources.contains(key)) {
        actual = _readSourceBare(key);
      } else {
        actual = _read(key);
      }
      if (!_matches(actual, e.value)) return false;
    }
    return true;
  }






  dynamic _valueOfBare(MapperParam p) {
    final sources = p.sourceByForm.isNotEmpty
        ? (p.sourceByForm[space.formId] ?? const <String>[])
        : p.source;
    for (final src in sources) {
      final v = _readSourceBare(src);
      if (v == null) continue;
      if (v is String && v.isEmpty && p.empty != 'significant') continue;
      return v;
    }
    return null;
  }




  dynamic _readSourceBare(String src) {
    if (src.startsWith('query.')) {
      final raw = space.query.get(src.substring('query.'.length));
      return raw == null ? null : percentDecodeOnce(raw);
    }
    switch (src) {
      case 'scheme':
        return space.scheme;
      case 'host':
        return space.host;
      case 'port':
        return space.port;
      case 'port_raw':
        return space.portRaw;
      case 'path':
        return space.path;
      case 'fragment':
        return space.fragment;
      case 'userinfo':
        return space.userinfo;


      case 'hint':
        return nameHint;
    }
    final layered = _readContextOrRef(src);
    if (layered.hit) return layered.value;
    if (src.startsWith('json.')) {
      return jsonPathValue(
          space.json, _resolveBase(src.substring('json.'.length)));
    }
    if (src.startsWith('ini.')) {
      return space.ini?[src.substring('ini.'.length).toLowerCase()];
    }
    final dot = src.indexOf('.');
    if (dot > 0) {
      final layer = _overlays[src.substring(0, dot)];
      if (layer != null) return layer.get(src.substring(dot + 1));
    }
    return null;
  }




  ({bool hit, Object? value}) _readContextOrRef(String src) {
    if (src.startsWith('context.')) {
      final ctx = context;
      return (
        hit: true,
        value: ctx == null
            ? null
            : jsonPathValue(ctx, src.substring('context.'.length)),
      );
    }
    if (src.startsWith('ref.')) {
      final rest = src.substring('ref.'.length);
      final dot = rest.indexOf('.');
      final name = dot < 0 ? rest : rest.substring(0, dot);
      final layer = _refs[name];
      if (layer == null) return (hit: true, value: null);
      return (
        hit: true,
        value: dot < 0 ? layer : jsonPathValue(layer, rest.substring(dot + 1)),
      );
    }
    return (hit: false, value: null);
  }





  void _applyDeref(MapperParam p) {
    final d = p.deref;
    if (d == null) return;
    final key = d['key'];
    final as = d['as'];
    if (key is! String || as is! String) return;
    _refs.remove(as);
    final doc = document;
    if (doc == null) return;
    final v = _valueOfBare(p);
    if (v == null || v is Map || v is List) return;
    final want = '$v';
    for (final el in doc) {
      if (el is! Map) continue;
      final k = jsonPathValue(el, key);
      if (k == null || k is Map || k is List) continue;
      if ('$k' == want) {
        _refs[as] = el;
        return;
      }
    }
  }





  Object? _applySubstitute(MapperParam p, Object? raw) {
    final sub = p.substitute;
    if (sub == null || raw is! String) return raw;
    final sep = sub['sep'];
    final join = sub['join'];
    final tokens = (sub['tokens'] as Map?)?.cast<String, dynamic>();
    if (sep is! String || sep.isEmpty || tokens == null || tokens.isEmpty) {
      return raw;
    }
    final parts = raw.split(sep);
    if (!parts.any((e) => tokens.containsKey(e.trim()))) return raw;
    final out = <String>[];
    for (final part in parts) {
      final t = part.trim();
      final srcName = tokens[t];
      if (srcName is! String) {
        if (t.isNotEmpty) out.add(t);
        continue;
      }
      final v = _readSourceBare(srcName);
      if (v == null || v is Map || v is List) continue;
      final str = '$v'.trim();
      if (str.isNotEmpty) out.add(str);
    }
    if (out.isEmpty) return null;
    return out.join(join is String ? join : sep);
  }

  static const _kLexicalSources = {
    'scheme',
    'host',
    'port',
    'port_raw',
    'path',
    'fragment',
    'userinfo',
    'authority',
  };

  bool _matches(dynamic actual, dynamic expected) {
    if (expected is Map) {
      final m = expected.cast<String, dynamic>();
      if (m.containsKey('in')) {
        final list = (m['in'] as List).map(_fold).toSet();
        return list.contains(_fold(actual ?? ''));
      }




      if (m.containsKey('not_in')) {
        if (actual == null) return true;
        final list = (m['not_in'] as List).map(_fold).toSet();
        return !list.contains(_fold(actual));
      }
      if (m.containsKey('not')) return !_matches(actual, m['not']);


      if (m.containsKey('type_of')) {
        return actual != null && _isJsonType(actual, '${m['type_of']}');
      }
      if (m.containsKey('present')) {
        return (actual != null) == (m['present'] == true);
      }






      if (m.containsKey('absent')) {
        return (actual == null) == (m['absent'] == true);
      }



      if (m.containsKey('matches')) {
        return actual is String &&
            _regex(m['matches'] as String).hasMatch(actual);
      }
      if (m.containsKey('not_matches')) {
        return actual is! String ||
            !_regex(m['not_matches'] as String).hasMatch(actual);
      }



      if (m.containsKey('lt') || m.containsKey('gt')) {
        final n = actual is num
            ? actual.toDouble()
            : double.tryParse('${actual ?? ''}'.trim());
        if (n == null) return false;
        final lt = (m['lt'] as num?)?.toDouble();
        final gt = (m['gt'] as num?)?.toDouble();
        if (lt != null && !(n < lt)) return false;
        if (gt != null && !(n > gt)) return false;
        return true;
      }
      return false;
    }
    if (expected is bool) return actual == expected;
    if (expected == null) return actual == null;
    return _fold(actual ?? '') == _fold(expected);
  }

  static String _fold(dynamic v) => '$v'.trim().toLowerCase();



  ({bool matched, dynamic value}) _mapValue(
    Map<String, dynamic> map,
    String value, {
    bool caseSensitive = false,
  }) {


    final prefix = map['prefix'];
    if (prefix is Map) {
      var probe = value.toLowerCase();
      final strip = (map['strip'] as List?)?.cast<String>() ?? const [];
      for (final s in strip) {
        probe = probe.replaceAll(s, '');
      }


      final keys = prefix.keys.cast<String>().toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      for (final k in keys) {
        if (probe.startsWith(k.toLowerCase())) {
          return (matched: true, value: prefix[k]);
        }
      }
      return (matched: false, value: value);
    }
    if (map.containsKey(value)) return (matched: true, value: map[value]);





    if (caseSensitive) return (matched: false, value: value);
    final folded = value.toLowerCase();
    for (final e in map.entries) {
      if (e.key.toLowerCase() == folded) return (matched: true, value: e.value);
    }
    return (matched: false, value: value);
  }



  dynamic _coerceType(MapperParam p, dynamic value) {
    if (p.list != null) {
      final spec = p.list!;
      final items = <dynamic>[];
      if (value is List) {
        items.addAll(value);
      } else if (value is String) {
        for (final part in value.split(spec.sep)) {
          final t = part.trim();
          if (t.isEmpty) continue;
          items.add(t);
        }
      } else if (spec.coerceScalar) {
        items.add(value);
      }
      if (spec.item == 'int') {
        final ints = <int>[];
        for (final it in items) {
          final n = _asInt(it);
          if (n != null) ints.add(n);
        }
        return ints.isEmpty ? null : ints;
      }
      return items.isEmpty ? null : items;
    }

    switch (p.type) {
      case 'int':
        return _asInt(value);





      case 'bool':
      case 'bool_spelled':



        final s = '$value'.trim().toLowerCase();
        final truthy = s == '1' || s == 'true' || s == 'yes';

        return truthy ? true : null;
      case 'duration':


        return '$value'.trim();
      case 'object':
        if (value is Map) {
          final m = value.cast<String, dynamic>();
          if (!p.sortKeys) return m;


          final keys = m.keys.toList()..sort();
          return {for (final k in keys) k: m[k]};
        }
        return value;
      default:
        if (p.coerceScalarToList && value is! List) return [value];
        if (p.coerceObjectToScalar != null && value is Map) {
          return value[p.coerceObjectToScalar];
        }
        return value;
    }
  }




  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) {
      if (!value.isFinite) return null;
      final n = value.toInt();
      return value == n ? n : null;
    }
    return int.tryParse('$value'.trim());
  }

  String _normalize(String value, String name) {
    switch (name) {
      case 'trim':
        return value.trim();
      case 'trim_lower':
        return value.trim().toLowerCase();








      case 'base64_std':
        final swapped = value.trim().replaceAll('-', '+').replaceAll('_', '/');
        final decoded = _RunDecode.bytes(swapped);
        return decoded == null ? value : _b64.encode(decoded);
      case 'duration_bare_seconds':
        final n = int.tryParse(value.trim());
        return n == null ? value : '${n}s';









      case 'bandwidth_mbps':
        return normalizeBandwidthMbps(value)?.toString() ?? value;
      default:
        return value;
    }
  }






  static List<dynamic> _normalizeList(List<dynamic> items, String name) {
    switch (name) {














      case 'port_range_spec':
        return [
          for (final raw in items)
            if ('$raw'.trim().isNotEmpty)
              () {
                final seg = '$raw'.trim().replaceAll('-', ':');
                final i = seg.indexOf(':');
                if (i < 0) return _kUintRe.hasMatch(seg) ? '$seg:$seg' : '$raw';
                final lo = seg.substring(0, i);
                final hi = seg.substring(i + 1);
                if (!_kUintRe.hasMatch(lo) || !_kUintRe.hasMatch(hi)) {
                  return '$raw';
                }
                return '$lo:$hi';
              }(),
        ];

      case 'cidr_prefix':
        return [
          for (final raw in items)
            if ('$raw'.trim().isNotEmpty)
              () {
                final a = '$raw'.trim();
                if (a.contains('/')) return a;
                return a.contains(':') ? '$a/128' : '$a/32';
              }(),
        ];
      default:
        return items;
    }
  }








  static dynamic _normalizeRange(String value, {required bool swap}) {
    final v = value.trim();
    if (v.isEmpty) return null;



    if (!_kUintRe.hasMatch(v)) {
      final dash = v.indexOf('-');
      if (dash <= 0) return null;
      final lo = _kUintRe.hasMatch(v.substring(0, dash).trim())
          ? int.tryParse(v.substring(0, dash).trim())
          : null;
      final hi = _kUintRe.hasMatch(v.substring(dash + 1).trim())
          ? int.tryParse(v.substring(dash + 1).trim())
          : null;
      if (lo == null || hi == null) return null;
      if (hi < lo) return swap ? '$hi-$lo' : null;
      return '$lo-$hi';
    }
    final single = int.tryParse(v);
    if (single != null) return single;
    final dash = v.indexOf('-');
    if (dash <= 0) return null;
    final lo = int.tryParse(v.substring(0, dash).trim());
    final hi = int.tryParse(v.substring(dash + 1).trim());
    if (lo == null || hi == null) return null;
    if (hi < lo) return swap ? '$hi-$lo' : null;
    return '$lo-$hi';
  }






  static dynamic _mergeInto(dynamic prev, dynamic val, String merge) {
    if (merge != 'append' && merge != 'prepend') return val;
    if (prev is! List || val is! List) return val;
    return merge == 'prepend' ? [...val, ...prev] : [...prev, ...val];
  }




  void _write(String path, dynamic value, MapperParam? p) {
    if (value == null) return;
    final prio = p?.priority ?? 0;
    final occupied = _writtenBy[path];
    final merge = p?.merge ?? 'keep_first';
    if (occupied != null) {

      if (merge == 'keep_first' && occupied <= prio) {
        _trace?.add(
          stage: TraceStage.field,
          mapper: _mapperId,
          entry: p?.name ?? r'$sets',
          val: value,
          path: path,
          act: TraceAct.skip,
          why: TraceWhy.lowerPriority(_writtenByName[path] ?? '-'),
        );
        return;
      }

      value = _mergeInto(_read(path), value, merge);
    }
    final was = occupied != null;
    _writtenBy[path] = prio;
    _writtenByName[path] = p?.name ?? r'$sets';
    _put(path, value);
    _trace?.add(
      stage: TraceStage.field,
      mapper: _mapperId,
      entry: p?.name ?? r'$sets',
      val: value,
      path: path,
      act: was ? TraceAct.override : TraceAct.write,
    );
  }


  final Map<String, String> _writtenByName = {};

  void _writeIfAbsent(String path, dynamic value, MapperParam? p) {
    if (value == null || _read(path) != null) return;
    _write(path, value, p);
  }


  void _erase(String path) {
    _trace?.add(
      stage: TraceStage.sets,
      mapper: _mapperId,
      entry: r'$sets',
      path: path,
      act: TraceAct.remove,
    );
    final segs = _segments(path);
    Map<String, dynamic>? cur = body;
    for (var i = 0; i < segs.length - 1; i++) {
      final seg = segs[i];

      if (seg.endsWith('[]')) {
        final list = cur![seg.substring(0, seg.length - 2)];
        if (list is! List || list.isEmpty || list.first is! Map) return;
        cur = (list.first as Map).cast<String, dynamic>();
        continue;
      }
      final next = cur![seg];
      if (next is! Map) return;
      cur = next.cast<String, dynamic>();
    }
    cur!.remove(segs.last);
    _writtenBy.remove(path);
  }





  void _put(String path, dynamic value) {
    final segs = _segments(path);
    var cur = body;
    for (var i = 0; i < segs.length - 1; i++) {
      final seg = segs[i];





      if (seg.endsWith('[]')) {
        final key = seg.substring(0, seg.length - 2);
        final existing = cur[key];
        if (existing is List && existing.isNotEmpty &&
            existing.first is Map<String, dynamic>) {
          cur = existing.first as Map<String, dynamic>;
        } else {
          final fresh = <String, dynamic>{};
          cur[key] = [fresh];
          cur = fresh;
        }
        continue;
      }
      final next = cur[seg];
      if (next is Map<String, dynamic>) {
        cur = next;
      } else {
        final fresh = <String, dynamic>{};
        cur[seg] = fresh;
        cur = fresh;
      }
    }
    cur[segs.last] = value;
  }

  dynamic _read(String path) {
    dynamic cur = body;
    for (final seg in _segments(path)) {
      if (cur is! Map) return null;

      if (seg.endsWith('[]')) {
        final list = cur[seg.substring(0, seg.length - 2)];
        if (list is! List || list.isEmpty) return null;
        cur = list.first;
        continue;
      }
      cur = cur[seg];
      if (cur == null) return null;
    }
    return cur;
  }







  String _label() {




    final byForm = section.label.sourceByForm;
    final sources = byForm.isNotEmpty
        ? (byForm[space.formId] ?? const <String>[])
        : section.label.source;





    for (final src in sources) {
      final v = _readSourceBare(src) ?? _readLabelBodyPath(src);



      final s = v is String ? v : (v == null ? '' : '$v');
      if (s.isEmpty) continue;





      if (src == 'path' && s == '/') continue;
      final label = _normalizeLabel(s, fromFragment: src == 'fragment');
      if (label.isNotEmpty) return label;
    }





    final tpl = section.label.fallbackTemplate;
    if (tpl != null && !tpl.contains('{')) return tpl;
    return '';
  }










  Object? _readLabelBodyPath(String src) {
    if (space.scheme.isEmpty || !src.contains('[]')) return null;
    return _read(src);
  }








  String _normalizeLabel(String raw, {bool fromFragment = true}) {
    var label =
        fromFragment ? percentDecodeOnce(raw, mode: DecodeMode.path) : raw;
    for (final n in section.label.normalize) {
      switch (n) {
        case 'strip_control':
          label = _stripControl(label);
        case 'trim':
          label = label.trim();
      }
    }



    final froms = section.label.valueMap.keys.toList()
      ..sort((a, b) {
        final byLen = b.length.compareTo(a.length);
        return byLen != 0 ? byLen : a.compareTo(b);
      });
    for (final from in froms) {
      label = label.replaceAll(from, '${section.label.valueMap[from]}');
    }
    return label;
  }



  static String _stripControl(String s) {
    if (s.isEmpty) return s;
    final buf = StringBuffer();
    for (final r in s.runes) {
      if (r == 9 || r == 10 || r == 13) {
        buf.writeCharCode(r);
        continue;
      }
      if (r <= 0x1F || r == 0x7F) continue;
      buf.writeCharCode(r);
    }
    return buf.toString();
  }








  void _reportUnknown() {
    final code = section.unknownKeyCode;
    if (code == null) return;
    for (final name in space.query.names) {
      if (_declared.contains(name.toLowerCase())) continue;







      if (_declaredJson.contains(name.toLowerCase())) continue;
      if (_labelKeys.contains(name.toLowerCase())) continue;





      if (section.ignoredKeys.contains(name)) continue;
      warnings.add(_unknownWarning(code, name));
      _trace?.add(
        stage: TraceStage.unknown,
        mapper: _mapperId,
        entry: name,
        src: 'query.$name',
        act: TraceAct.skip,
        why: TraceWhy.notDeclared,
      );
    }

    _reportUnknownIni(code);








    final json = space.json;
    if (json == null) return;
    for (final e in json.entries) {
      if (_consumed.contains('json.${e.key}'.toLowerCase())) continue;
      if (section.ignoredKeys.contains(e.key)) continue;








      if (_consumed.contains(e.key.toLowerCase())) continue;







      if (_labelKeys.contains(e.key.toLowerCase())) continue;
      warnings.add(_unknownWarning(code, e.key));
      if (section.unknownKeyAction == 'keep' && !body.containsKey(e.key)) {
        body[e.key] = e.value;
      }
    }

    _reportUnknownNested(code, json);
  }
























  void _reportUnknownNested(String code, Map<String, dynamic> json) {
    if (section.ignoredKeys.isEmpty) return;







    final found = <String>[];
    for (final e in json.entries) {
      if (!section.ignoredKeys.contains(e.key)) continue;
      final v = e.value;
      if (v is! Map && v is! List) continue;
      _walkNested(code, e.key, v, 1, found);
    }
    found.sort();
    for (final path in found) {
      warnings.add(_unknownWarning(code, path));
    }
  }




  static const int _kNestedUnknownMaxDepth = 12;

  void _walkNested(
    String code,
    String path,
    Object? node,
    int depth,
    List<String> found,
  ) {
    if (depth >= _kNestedUnknownMaxDepth) return;
    if (_nestedQuiet(path)) return;

    if (node is Map) {



      if (node.isEmpty) return;
      for (final e in node.cast<String, dynamic>().entries) {
        _walkNested(code, '$path.${e.key}', e.value, depth + 1, found);
      }
      return;
    }
    if (node is List) {

      if (node.isEmpty) return;
      for (var i = 0; i < node.length; i++) {
        _walkNested(code, '$path.$i', node[i], depth + 1, found);
      }
      return;
    }

    _noteNestedUnknown(path, found);
  }


  bool _nestedQuiet(String path) {
    final low = path.toLowerCase();
    for (final q in section.nestedQuiet) {
      final ql = q.toLowerCase();
      if (low == ql || low.startsWith('$ql.')) return true;
    }
    return false;
  }

  void _noteNestedUnknown(String path, List<String> found) {
    final low = path.toLowerCase();

    if (_declaredJsonPaths.contains(low)) return;



    for (final d in _declaredJsonPaths) {
      if (low.startsWith('$d.')) return;
    }
    found.add(path);
  }






  late final Set<String> _declaredJsonPaths = () {
    final out = <String>{};
    void add(String src) {
      if (!src.startsWith('json.')) return;
      final path = _resolveBase(src.substring('json.'.length));



      for (final p in expandSelectorPaths(space.json, path)) {
        out.add(p.toLowerCase());
      }
    }

    for (final p in section.params.values) {
      for (final src in p.source) {
        add(src);
      }
      for (final l in p.sourceByForm.values) {
        for (final src in l) {
          add(src);
        }
      }
    }
    for (final o in section.overlays) {
      for (final src in o.source) {
        add(src);
      }
    }
    for (final src in section.label.source) {
      add(src);
    }
    for (final l in section.label.sourceByForm.values) {
      for (final src in l) {
        add(src);
      }
    }
    return out;
  }();













  static RegistryWarning _unknownWarning(String code, String name) =>
      RegistryWarning(
        code: code,
        path: name,
        value: '',
        params: {'query_name': name},
      );











  void _reportUnknownIni(String code) {
    final ini = space.ini;
    if (ini == null || ini.isEmpty) return;
    final keys = ini.keys.toList()..sort();
    for (final key in keys) {


      if (key.startsWith(r'$')) continue;
      if (_declaredIni.contains(key)) continue;



      final dot = key.indexOf('.');
      final short = dot < 0 ? key : key.substring(dot + 1);
      if (section.ignoredKeys.contains(key) ||
          section.ignoredKeys.contains(short)) {
        continue;
      }
      warnings.add(_unknownWarning(code, key));
      _trace?.add(
        stage: TraceStage.unknown,
        mapper: _mapperId,
        entry: key,
        src: 'ini.$key',
        act: TraceAct.skip,
        why: TraceWhy.notDeclared,
      );
    }
  }









  Set<String> get _declaredIni => _plan.declaredIni;









  Set<String> get _declared => _plan.declared;














  Set<String> get _declaredJson => _plan.declaredJson;







  Set<String> get _labelKeys => _plan.labelKeys;











  static RegExp _regex(String re) => _regexCache.putIfAbsent(
        re,
        () => RegExp(re.replaceAll('(?P<', '(?<')),
      );

  static final Map<String, RegExp> _regexCache = {};

  static dynamic _lookupFold(Map<String, dynamic> map, String key) {
    if (map.containsKey(key)) return map[key];
    final folded = key.trim().toLowerCase();
    for (final e in map.entries) {
      if (e.key.toLowerCase() == folded) return e.value;
    }
    return null;
  }

  static String? _tryBase64(String raw) => _RunDecode.base64(raw);
}

const _b64 = Base64Codec();
