
















library;

import 'dart:convert' show base64, base64Url;
import 'dart:io' show InternetAddress, InternetAddressType;
import 'dart:typed_data' show Uint8List;

import '../../models/node_warning.dart';
import '../app_log.dart';
import '../parser/uri_utils.dart'
    show decodeBase64Lenient, normalizeSingboxDuration, urlPathOk;
import 'registry.dart';

























enum BodySource {



  singbox('singbox'),


  uri('uri'),


  xray('xray'),


  wgconf('wgconf'),


  amnezia('amnezia'),





  other('');

  const BodySource(this.registryName);


  final String registryName;






  static BodySource byRegistryName(String? name) {
    if (name == null || name.isEmpty) return other;
    for (final v in values) {
      if (v.registryName == name) return v;
    }
    return other;
  }
}


final class SanitizeResult {
  const SanitizeResult(
    this.body,
    this.warnings, {
    this.explicitDropNode = false,
    this.hardPaths = const [],
    this.dropFrom = -1,
    this.partial,
  });


  final Map<String, dynamic>? body;

  final List<RegistryWarning> warnings;

















  final bool explicitDropNode;




  final List<String> hardPaths;




  final int dropFrom;



  final Map<String, dynamic>? partial;
}






const _kBuildManagedKeys = {'type', 'tag', 'detour'};



const _kDefaultInvalidCode = 'type_invalid';



const _kWarningValueMax = 64;





String? fieldByRole(String singboxType, String role) {
  final schema = ContractRegistry.I.schemaFor(singboxType);
  if (schema == null) return null;
  for (final e in schema.fields.entries) {
    if (e.value.raw['role'] == role) return e.key;
  }
  return null;
}



String credentialByRegistry(Map<String, dynamic> body) {
  final f = fieldByRole('${body['type'] ?? ''}', 'credential');
  final v = f == null ? null : body[f];
  return v is String ? v : '';
}




bool carriesPrivateKeyByRegistry(Map<String, dynamic> body) {
  final f = fieldByRole('${body['type'] ?? ''}', 'private_key');
  if (f == null) return false;
  final v = body[f];
  if (v is String) return v.isNotEmpty;
  if (v is List) return v.any((e) => e is String && e.isNotEmpty);
  return false;
}








bool fieldAllowedOn(Map<String, dynamic> body, String path) {
  final type = '${body['type'] ?? ''}';
  final schema = ContractRegistry.I.schemaFor(type);
  if (schema == null) return true;
  final segs = path.split('.');
  Map<String, FieldSchema>? fields = schema.fields;
  FieldSchema? f;
  for (final seg in segs) {
    f = fields?[seg];
    if (f == null) return false;
    if (f.forbiddenFor?.contains(type) ?? false) return false;
    final allowed = f.allowedFor;
    if (allowed != null && !allowed.contains(type)) return false;
    fields = f.fields;
  }
  final parent = segs.sublist(0, segs.length - 1);
  Object? at(String p) {
    if (p.contains('.') || parent.isEmpty) return _Ctx.finalAt(body, p);
    return _Ctx.finalAt(body, [...parent, p].join('.')) ??
        _Ctx.finalAt(body, p);
  }

  for (final c in f!.conflicts) {
    final withPath = c['with'];
    if (withPath is! String) continue;
    final when = c['when'];
    if (when != null && !_Ctx.conditionOnFinalBody(when, body)) continue;
    if (!_Ctx._meaningful(at(withPath))) continue;
    final unless = c['unless_set'];
    if (unless is List &&
        unless.any((u) => u is String && _Ctx._meaningful(at(u)))) {
      continue;
    }
    return false;
  }
  return true;
}







List<RegistryWarning> yieldToManaged(
    Map<String, dynamic> body, String managed) {
  final target = body[managed];
  if (!_Ctx._meaningful(target)) return const [];
  final schema = ContractRegistry.I.schemaFor('${body['type'] ?? ''}');
  if (schema == null) return const [];
  final out = <RegistryWarning>[];
  void walk(Map<String, FieldSchema> fields, Map<String, dynamic> obj,
      String prefix) {
    for (final e in fields.entries) {
      if (!obj.containsKey(e.key)) continue;
      final path = prefix.isEmpty ? e.key : '$prefix.${e.key}';
      final v = obj[e.key];
      final nested = e.value.fields;
      if (nested != null && v is Map<String, dynamic>) {
        walk(nested, v, path);
        continue;
      }
      for (final c in e.value.conflicts) {
        if (c['with'] != managed) continue;
        final when = c['when'];
        if (when != null && !_Ctx.conditionOnFinalBody(when, body)) continue;
        final unless = c['unless_set'];
        if (unless is List &&
            unless.any((u) =>
                u is String && _Ctx._meaningful(_Ctx.finalAt(body, u)))) {
          continue;
        }
        obj.remove(e.key);
        out.add(RegistryWarning(
          code: '${c['code'] ?? 'field_conflict'}',
          path: path,
          params: {
            'tag': '${body['tag'] ?? ''}',
            'target': '$target',
            'with': managed,
          },
          ownerTag: '${body['tag'] ?? ''}',
        ));
        break;
      }
    }
  }

  walk(schema.fields, body, '');
  return out;
}




bool exitCapableByRegistry(Map<String, dynamic> body) {
  final when = ContractRegistry.I.schemaFor('${body['type'] ?? ''}')
      ?.exitCapableWhen;
  if (when == null) return true;
  return _Ctx.conditionOnFinalBody(when, body);
}

final class RegistrySanitizer {
  const RegistrySanitizer._();






























  static SanitizeResult sanitize(
    Map<String, dynamic> body, {
    required String scheme,
    required String coreVersion,
    String platform = 'android',
    bool applyCoreGates = true,
    BodySource source = BodySource.other,
    Set<String> kinds = const {},
  }) {
    final schema = ContractRegistry.I.schemaFor(scheme);


    if (schema == null || schema.fieldsUnchecked) {
      return SanitizeResult(body, const []);
    }

    final ctx = _Ctx(
      scheme: scheme,
      coreVersion: coreVersion,
      platform: platform,
      applyCoreGates: applyCoreGates,
      source: source,
      kinds: kinds,
      root: body,
    );
    final out = ctx.sanitizeObject(body, schema.order, schema.fields, '');









    if (!ctx.dropNode) ctx.applyBodyRelations(out, schema.relations);



    if (!ctx.dropNode) ctx.applyRepairs(out);
    if (ctx.dropNode) {
      return SanitizeResult(null, ctx.warnings,
          explicitDropNode: ctx.explicitDropNode,
          hardPaths: ctx.hardPaths,
          dropFrom: ctx.dropFrom < 0 ? 0 : ctx.dropFrom,
          partial: out);
    }
    return SanitizeResult(out, ctx.warnings, hardPaths: ctx.hardPaths);
  }
















  static String renderWarningValue(Object value, {bool secret = false}) {
    if (secret) return '***';
    return _truncateWarningValue(_renderWarningScalar(value));
  }
}


String _renderWarningScalar(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => '$k').toList()..sort();
    return 'map[${[
      for (final k in keys) '$k:${_renderWarningScalar(value[k])}',
    ].join(' ')}]';
  }
  if (value is List) {
    return '[${[for (final e in value) _renderWarningScalar(e)].join(' ')}]';
  }
  return value is String ? value : '$value';
}




String _truncateWarningValue(String s) {
  final runes = s.runes.toList(growable: false);
  if (runes.length <= _kWarningValueMax) return s;
  return '${String.fromCharCodes(runes.take(_kWarningValueMax))}…';
}




final class _Ctx {
  _Ctx({
    required this.scheme,
    required this.coreVersion,
    required this.platform,
    required this.applyCoreGates,
    required this.source,
    required this.kinds,
    required this.root,
  });

  final String scheme;
  final String coreVersion;
  final String platform;


  final BodySource source;













  final Set<String> kinds;



  final bool applyCoreGates;
  final Map<String, dynamic> root;

  final warnings = <RegistryWarning>[];

  bool _dropNode = false;



  int dropFrom = -1;

  bool get dropNode => _dropNode;
  set dropNode(bool v) {
    if (v && !_dropNode) {
      dropFrom = warnings.isEmpty ? 0 : warnings.length - 1;
    }
    _dropNode = v;
  }


  final hardPaths = <String>[];



  bool explicitDropNode = false;








  bool dropObject = false;







  final sanitized = <String, Object?>{};















  final explainedDrops = <String>{};











  final switchedOff = <String>{};








  final _building = <String, Map<String, Object?>>{};




  final _repairs = <_Repair>[];


  final _fieldEnd = <String, int>{};


  void _relWarn(List<String> order, int i, String prefix, String code,
      {String? path, Map<String, String> params = const {}}) {
    final me = _join(prefix, order[i]);
    final pos = _fieldEnd[me] ?? warnings.length;
    warnings.insert(
        pos, RegistryWarning(code: code, path: path, params: params));
    final later = {for (final k in order.skip(i)) _join(prefix, k)};
    for (final e in _fieldEnd.entries.toList()) {
      if (e.value > pos || (e.value == pos && later.contains(e.key))) {
        _fieldEnd[e.key] = e.value + 1;
      }
    }
    for (final r in _repairs) {
      if (r.index >= pos) r.index++;
    }
  }

  void warn(
    String code, {
    String? path,
    Object? value,
    bool secret = false,
    Map<String, String> params = const {},
  }) {
    warnings.add(RegistryWarning(
      code: code,
      path: path,
      value: value == null
          ? null
          : RegistrySanitizer.renderWarningValue(value, secret: secret),
      params: params,
    ));
  }










  Map<String, String> _requiredParams(Map<String, dynamic> src) {
    final type = src['type'];
    return type is String && type.isNotEmpty ? {'type': type} : const {};
  }



  Map<String, dynamic> sanitizeObject(
    Map<String, dynamic> src,
    List<String> order,
    Map<String, FieldSchema> fields,
    String prefix,
  ) {
    final out = <String, dynamic>{};













    for (final key in src.keys.toList()..sort()) {
      if (fields.containsKey(key)) continue;
      if (prefix.isEmpty && _kBuildManagedKeys.contains(key)) continue;
      warn('unknown_key', path: _join(prefix, key), value: src[key]);
    }



    final kept = <String, Object?>{};
    _building[prefix] = kept;
    try {
      return _sanitizeObjectBody(src, order, fields, prefix, kept, out);
    } finally {
      _building.remove(prefix);
    }
  }

  Map<String, dynamic> _sanitizeObjectBody(
    Map<String, dynamic> src,
    List<String> order,
    Map<String, FieldSchema> fields,
    String prefix,
    Map<String, Object?> kept,
    Map<String, dynamic> out,
  ) {
    String? prevPath;
    for (final key in order) {


      if (prevPath != null) _fieldEnd[prevPath] = warnings.length;
      prevPath = _join(prefix, key);
      final f = fields[key];
      if (f == null) continue;
      final unset = !src.containsKey(key) || _unsetForDefault(src[key], f);
      if (unset && src.containsKey(key)) {







        final dw = f.defaultWhen;
        final fires = dw != null &&
            dw['absent'] == true &&
            _conditionHolds(dw['when'], src);
        if (!fires) {
          final v = src[key];
          if (v is String && v.isEmpty) continue;
          final path = _join(prefix, key);
          final res = _sanitizeValue(v, f, path);
          if (dropNode) return out;
          if (res.keep) kept[key] = res.value;
          continue;
        }
      }
      if (unset) {



















        _minWhenOnAbsent(f, prefix, key);
        if (dropNode) return out;
        final dw = f.defaultWhen;
        if (dw != null &&
            dw['absent'] == true &&
            _conditionHolds(dw['when'], src)) {
          kept[key] = dw['value'];
          final code = dw['code'] as String?;
          if (code != null) {
            warn(code, path: _join(prefix, key));
          } else if (dw['core_rejects'] == true) {
            hardPaths.add(_join(prefix, key));
          }
          continue;
        }




















        if (f.required) {
          final own = f.code;
          if (own == null) {
            warn('field_missing', params: {'field': _join(prefix, key)});
          } else {
            warn(own, path: _join(prefix, key), params: _requiredParams(src));
          }
          if (prefix.isEmpty) {
            dropNode = true;
          } else {
            dropObject = true;
            return out;
          }
        }
        continue;
      }
      final path = _join(prefix, key);
      final res = _sanitizeValue(src[key], f, path);
      if (dropNode) return out;









      if (!res.keep && f.required) {
        if (prefix.isEmpty) {
          dropNode = true;
        } else {
          dropObject = true;
        }
        return out;
      }
      if (res.keep) {
        kept[key] = res.value;
        _recordCoerceWhen(f, path, res.value);
      }
    }








    if (prevPath != null) _fieldEnd[prevPath] = warnings.length;
    final written = <String, String>{};
    for (final e in kept.entries) {
      final path = _join(prefix, e.key);
      written[e.key] = path;
      sanitized[path] = e.value;
    }



    _applyRelations(kept, order, fields, prefix);


    for (final e in written.entries) {
      if (!kept.containsKey(e.key)) sanitized.remove(e.value);
    }












    for (final key in src.keys) {
      if (kept.containsKey(key)) {
        out[key] = kept[key];
      } else if (prefix.isEmpty && _kBuildManagedKeys.contains(key)) {
        out[key] = src[key];
      }
    }


    for (final e in kept.entries) {
      if (!out.containsKey(e.key)) out[e.key] = e.value;
    }
    return out;
  }




  static bool _unsetForDefault(Object? v, FieldSchema f) {
    if (v is! String) return false;
    if (v.isEmpty) return !f.required && f.raw['tristate'] != true;
    final absent = f.absentValues;
    if (absent == null) return false;
    final norm = f.normalize;
    final n = norm == null ? v : _normalizeString(v, norm);
    return absent.contains(n);
  }




  bool _gated(FieldSchema f, String path, Object? value) {












    final forbidden = f.forbiddenFor;
    if (forbidden != null && forbidden.contains(scheme)) {
      warn(f.forbiddenCodeFor(scheme) ?? _kDefaultInvalidCode,
          path: path, value: value, secret: f.secret);
      return true;
    }
    final allowed = f.allowedFor;
    if (allowed != null && !allowed.contains(scheme)) {
      warn(f.code ?? _kDefaultInvalidCode,
          path: path, value: value, secret: f.secret);
      return true;
    }



    if (!applyCoreGates) return false;
    final minCore = f.minCore;
    if (minCore != null && !coreAtLeast(coreVersion, minCore)) return true;

    final plat = f.platform;
    if (plat != null && plat != platform) return true;
    return false;
  }

  _Value _sanitizeValue(Object? value, FieldSchema f, String path) {
    if (_gated(f, path, value)) return const _Value.drop();

















    final absentWhen = f.absentWhen;
    if (absentWhen != null &&
        value is Map &&
        _absentWhenHolds(absentWhen, value)) {
      switchedOff.add(path);
      return const _Value.drop();
    }

    switch (f.type) {
      case 'object':
        if (f.variants != null) return _sanitizeVariantObject(value, f, path);
        return _sanitizeObjectField(value, f, path);
      case 'array':
        return _sanitizeArray(value, f, path);
      case 'ref':



        return _Value.keep(value);
      default:
        return _sanitizeScalar(value, f, path);
    }
  }




  _Value _sanitizeVariantObject(Object? value, FieldSchema f, String path) {
    if (value is! Map) return _invalid(f, path, value);
    final disc = f.discriminator ?? 'type';
    final map = value.cast<String, dynamic>();
    final type = map[disc];
    if (type is! String) {

      return _invalid(f, path, value);
    }
    final variant = f.variants![type];
    if (variant == null) return _invalid(f, path, type);


    final inner = Map<String, dynamic>.from(map)..remove(disc);
    final cleaned = sanitizeObject(
        inner, variant.order ?? const [], variant.fields ?? const {}, path);
    return _Value.keep(<String, dynamic>{disc: type, ...cleaned});
  }






  _Value _sanitizeObjectField(Object? value, FieldSchema f, String path) {
    if (value is! Map) return _invalid(f, path, value);
    final map = value.cast<String, dynamic>();
    final fields = f.fields;


    if (fields == null) return _Value.keep(map);




    dropObject = false;
    final cleaned = sanitizeObject(map, f.order ?? const [], fields, path);
    if (dropNode) return const _Value.drop();
    if (dropObject) {
      dropObject = false;
      return const _Value.drop();
    }











    return _Value.keep(cleaned);
  }

  _Value _sanitizeArray(Object? value, FieldSchema f, String path) {
    if (value is! List) return _invalid(f, path, value);
    final items = f.items;
    if (items == null) return _Value.keep(value);
    final out = <Object?>[];
    for (var i = 0; i < value.length; i++) {





      final item = value[i];
      final itemFields = items.fields;
      if (item is Map && itemFields != null) {
        dropObject = false;
        final cleaned = sanitizeObject(item.cast<String, dynamic>(),
            items.order ?? const [], itemFields, '$path[$i]');
        if (dropNode) return const _Value.drop();
        if (dropObject) {
          dropObject = false;
          dropNode = true;
          return const _Value.drop();
        }
        out.add(cleaned);
        continue;
      }
      final res = _sanitizeValue(item, items, '$path[$i]');
      if (dropNode) return const _Value.drop();
      if (res.keep) out.add(res.value);
    }

    final len = f.len;
    if (len != null && out.length != len) return _invalid(f, path, value);
    return _Value.keep(out);
  }

  _Value _sanitizeScalar(Object? value, FieldSchema f, String path) {






    var value0 = value;
    if (f.normalize == 'range_order' && value0 is String) {
      value0 = _normalizeString(value0, 'range_order');
    }
    final coerced = _coerceType(value0, f.type);
    if (coerced == null) return _invalid(f, path, value);
    var v = coerced.value;



    final norm = f.normalize;
    if (norm != null && v is String) {
      v = _normalizeString(v, norm);
    }

    if (norm != null && v is List) {
      v = [
        for (final e in v)
          if (e is String) _normalizeString(e, norm) else e,
      ];
    }


    final itemForbidden = f.raw['item_forbidden'];
    if (itemForbidden is Map && v is List) {
      final banned =
          ((itemForbidden['values'] as List?) ?? const []).map((e) => '$e');
      final kept0 = [];
      for (var i = 0; i < v.length; i++) {
        final e = v[i];
        if (banned.contains('$e')) {
          warn(itemForbidden['code'] as String? ?? _kDefaultInvalidCode,
              path: '$path[$i]', value: e);
        } else {
          kept0.add(e);
        }
      }
      if (kept0.isEmpty) return const _Value.drop();
      v = kept0;
    }


















    final absent = f.absentValues;
    if (absent != null && v is String && absent.contains(v)) {
      switchedOff.add(path);
      return const _Value.drop();
    }

















    final normCode = f.normalizeCode;
    if (normCode != null && v != _foldForNormalizeCode(coerced.value)) {
      warn(normCode, path: path, value: coerced.value, secret: f.secret);
    }



    final values = f.values;
    if (values != null) {
      final bad = v is List
          ? v.where((e) => !values.contains(e)).toList()
          : (values.contains(v) ? const [] : [v]);
      if (bad.isNotEmpty) return _invalid(f, path, bad.first, secret: f.secret);
    }


    final violation = _checkConstraints(v, f);
    if (violation != null) {
      return _invalid(f, path, violation, secret: f.secret);
    }















    final pattern = f.pattern;
    if (pattern != null && v is String) {
      final re = _compilePattern(pattern);
      if (re != null && !re.hasMatch(v)) {
        return _invalid(f, path, coerced.value, secret: f.secret);
      }
    }
























    final itemPattern = f.itemPattern;
    if (itemPattern != null && v is List) {
      final re = _compilePattern(itemPattern);
      final onItem = f.onItemInvalid;
      final action = onItem?['action'] as String?;
      final itemCode = onItem?['code'] as String?;
      if (re != null && itemCode != null) {
        if (action == 'drop_item') {
          final kept = <dynamic>[];
          for (var i = 0; i < v.length; i++) {
            final e = v[i];








            if (e is! String || !re.hasMatch(e)) {
              warn(itemCode,
                  path: '$path[$i]', value: e, secret: f.secret);
              continue;
            }
            kept.add(e);
          }




          if (kept.isEmpty) return const _Value.drop();
          v = kept;
        } else if (action != null) {
          _logUnknownExpression('on_item_invalid.action', action);
        }
      }
    }





    v = _applyMaxWhen(v, f, path);



    if (_applyMinWhen(v, f, path)) return const _Value.drop();
















    for (final a in f.advisory) {
      final code = a['code'] as String?;
      if (code == null) continue;
      final vals = (a['values'] as List?)?.cast<Object?>();
      final except = (a['except'] as List?)?.cast<Object?>();
      if (vals != null && !vals.contains(v)) continue;


      if (except != null && (except.contains(v) || v == null || v == '')) {
        continue;
      }
      if (!_advisoryWhen(a['when'])) continue;
      warn(code,
          path: path,
          value: v,
          secret: f.secret,
          params: _advisoryParams(code, v));
    }

    return _Value.keep(v);
  }













  Map<String, String> _advisoryParams(String code, Object? v) {
    final declared = ContractRegistry.I.textFor(code)?.params ?? const [];
    final text = v is String ? v : '$v';
    return {
      for (final p in declared)
        if (p != 'path' && p != 'value') p: text,
    };
  }




















  Object? _applyMaxWhen(Object? v, FieldSchema f, String path) {
    final rule = f.maxWhen;
    if (rule == null) return v;
    final ceiling = rule['max'];
    if (v is! num || ceiling is! num) return v;
    if (v <= ceiling) return v;
    if (!_conditionHolds(rule['when'], root)) return v;

    final except = (rule['except_sources'] as List?)?.map((e) => '$e');
    if (except != null && except.contains(source.registryName)) {
      final note = rule['note_code'] as String?;


      if (note != null) warn(note, path: path, value: v, secret: f.secret);
      return v;
    }

    final code = rule['code'] as String?;

    if (code != null) warn(code, path: path, value: v, secret: f.secret);
    return ceiling;
  }











  static bool _absentWhenHolds(Map<String, dynamic> rule, Map<Object?, Object?> obj) {
    if (rule.isEmpty) return false;
    for (final e in rule.entries) {
      if (!obj.containsKey(e.key)) return false;
      if ('${obj[e.key]}' != '${e.value}') return false;
    }
    return true;
  }





















  void applyBodyRelations(
      Map<String, dynamic> clean, List<Map<String, dynamic>> relations) {
    for (final rel in relations) {
      final kind = rel['kind'];
      if (kind == 'cooccurrence') {
        _applyCooccurrence(clean, rel);
        continue;
      }
      if (kind == 'ordered') {
        _applyOrdered(clean, rel);
        continue;
      }
      if (kind != 'ranges_disjoint') {
        _logUnknownExpression('relation', '$kind');
        continue;
      }
      final paths = ((rel['paths'] as List?) ?? const []).map((e) => '$e');
      final defaults = (rel['defaults'] as List?) ?? const [];
      final spans = <String, (int, int)>{};
      var i = -1;
      for (final p in paths) {
        i++;
        final raw = clean.containsKey(p)
            ? clean[p]
            : (i < defaults.length ? defaults[i] : null);
        final span = _rangeSpan(raw);
        if (span != null) spans[p] = span;
      }
      final names = spans.keys.toList();
      for (var a = 0; a < names.length; a++) {
        for (var b = a + 1; b < names.length; b++) {
          final x = spans[names[a]]!;
          final y = spans[names[b]]!;
          if (x.$1 > y.$2 || y.$1 > x.$2) continue;
          final code = rel['code'] as String?;
          if (code != null) {


            warn(code,
                path: names[a],
                value: '${names[a]}=${clean[names[a]] ?? ''} '
                    '${names[b]}=${clean[names[b]] ?? ''}'.trim());
          }
          if (rel['action'] == 'drop_node') {
            dropNode = true;
            explicitDropNode = true;
          }
          return;
        }
      }
    }
  }




















  void _applyOrdered(Map<String, dynamic> clean, Map<String, dynamic> rel) {
    final paths = [
      for (final p in (rel['paths'] as List?) ?? const [])
        if (clean.containsKey('$p') && _rangeSpan(clean['$p']) != null) '$p',
    ];
    for (var i = 0; i + 1 < paths.length; i++) {
      final a = paths[i], b = paths[i + 1];
      if (_rangeSpan(clean[a])!.$2 <= _rangeSpan(clean[b])!.$1) continue;
      final code = rel['code'] as String?;
      if (code != null) {
        warn(code, path: a, params: {
          'a': a,
          'b': b,
          'value': '${clean[a]}',
          'with': '${clean[b]}',
        });
      }
      if (rel['action'] == 'drop_node') {
        dropNode = true;
        explicitDropNode = true;
      } else if (rel['action'] == 'drop') {
        for (final p in (rel['paths'] as List?) ?? const []) {
          clean.remove('$p');
        }
      }
      return;
    }
  }

  void _applyCooccurrence(Map<String, dynamic> clean, Map<String, dynamic> rel) {
    final when = rel['when'];
    if (when is! Map) return;
    for (final e in when.entries) {
      final key = '${e.key}';
      if (key == r'$range_width') {
        if (!_rangeWidthHolds(clean, e.value)) return;
        continue;
      }
      if (!clean.containsKey(key)) return;
      if ('${clean[key]}' != '${e.value}') return;
    }
    final code = rel['code'] as String?;
    if (code == null) return;
    final paths = ((rel['paths'] as List?) ?? const []).map((e) => '$e');
    final path = paths.isEmpty ? null : paths.first;
    if (!_cooccurrenceSeen.add('$code $path')) return;

    warn(code, path: path);
    if (rel['action'] == 'drop_node') {
      dropNode = true;
      explicitDropNode = true;
    }
  }


  final Set<String> _cooccurrenceSeen = <String>{};



  static bool _rangeWidthHolds(Map<String, dynamic> clean, Object? spec) {
    if (spec is! Map) return false;
    final paths = ((spec['paths'] as List?) ?? const []).map((e) => '$e');
    final gt = spec['gt'];
    final lt = spec['lt'];
    for (final p in paths) {
      final span = _rangeSpan(clean[p]);
      if (span == null) continue;
      final width = span.$2 - span.$1;
      if (gt is num && width > gt) return true;
      if (lt is num && width < lt) return true;
    }
    return false;
  }



















  bool _applyMinWhen(Object? v, FieldSchema f, String path) {
    final rule = f.minWhen;
    if (rule == null) return false;
    final floor = rule['min'];
    if (v is! num || floor is! num) return false;
    if (v >= floor) return false;
    if (!_conditionHolds(rule['when'], root)) return false;
    _minWhenViolated(rule, f, path, v);
    return true;
  }







  void _minWhenOnAbsent(FieldSchema f, String prefix, String key) {
    final rule = f.minWhen;
    if (rule == null || rule['absent_is_zero'] != true) return;
    final floor = rule['min'];
    if (floor is! num || floor <= 0) return;
    if (!_conditionHolds(rule['when'], root)) return;
    _minWhenViolated(rule, f, _join(prefix, key), 0);
  }


  void _minWhenViolated(
      Map<String, dynamic> rule, FieldSchema f, String path, Object? value) {
    final code = rule['code'] as String?;
    if (code != null) {
      warn(code,
          path: path,
          value: value,


          params: {'field': path});
    }
    if (rule['action'] == 'drop_node') {
      dropNode = true;
      explicitDropNode = true;
    }
  }























  bool _conditionHolds(Object? when, Map<String, dynamic> body) {
    if (when == null) return true;
    if (when is! Map) return true;
    var known = false;
    var branches = false;

    for (final e in when.entries) {
      final key = '${e.key}';
      if (key == 'any_set' || key == 'source_kind') {
        branches = true;
        continue;
      }
      if (!_valuePredicateHolds(key, e.value)) return false;
    }
    if (!branches) return true;

    final sourceKind = (when['source_kind'] as List?)?.map((e) => '$e');
    if (sourceKind != null) {
      known = true;
      if (sourceKind.any(kinds.contains)) return true;
    }

    final anySet = (when['any_set'] as List?)?.map((e) => '$e');
    if (anySet != null) {
      known = true;
      if (_anySetInBody(anySet, body)) return true;
    }

    if (!known) _logUnknownExpression('when', when.keys.join(','));
    return false;
  }




















  static bool _anySetInBody(Iterable<String> keys, Map<String, dynamic> body) {
    for (final key in keys) {
      if (!body.containsKey(key)) continue;
      final v = body[key];
      if (v is String && v.isEmpty) continue;
      return true;
    }
    return false;
  }











  bool _valuePredicateHolds(String path, Object? want) {
    Object? got;
    var present = false;
    if (!_switchedOff(path) && !explainedDrops.contains(path)) {
      final clean = _cleanAt(path);
      if (clean.$1) {
        got = clean.$2;
        present = true;
      } else {
        got = _rawAt(path);
        present = got != null;
      }
      if (got is String && got.isEmpty) present = false;
    }
    if (want is Map) {
      final inList = want['in'];
      if (inList is List) {
        return present && inList.any((e) => '$e' == '$got');
      }
      final notIn = want['not_in'];
      if (notIn is List) {
        return !present || !notIn.any((e) => '$e' == '$got');
      }
      _logUnknownExpression('when', want.keys.join(','));
      return false;
    }
    return present && '$want' == '$got';
  }






  (bool, Object?) _cleanAt(String path) {
    if (sanitized.containsKey(path)) return (true, sanitized[path]);
    final parts = path.split('.');
    for (var i = parts.length - 1; i >= 0; i--) {
      final m = _building[parts.sublist(0, i).join('.')];
      if (m == null) continue;
      Object? cur = m;
      for (final seg in parts.sublist(i)) {
        if (cur is! Map || !cur.containsKey(seg)) return (false, null);
        cur = cur[seg];
      }
      return (true, cur);
    }
    return (false, null);
  }



  Object? _checkConstraints(Object? v, FieldSchema f) {
    final format = f.format;
    if (format != null && !_formatOk(v, format)) return v;

    final len = f.len;
    final parity = f.lenParity;

    if (v is List) {
      if (len != null && v.length != len) return v;










      final min = f.min;
      final max = f.max;
      if (min != null || max != null) {
        for (final e in v) {
          if (e is! num) continue;
          if (min != null && e < min) return v;
          if (max != null && e > max) return v;
        }
      }
      return null;
    }
    if (v is String) {
      if (len != null && v.length != len) return v;
      if (parity != null) {
        final even = v.length.isEven;
        if ((parity == 'even') != even) return v;
      }



      final min = f.min;
      final max = f.max;
      if (f.type == 'string') {
        if (min != null && v.length < min) return v;
        if (max != null && v.length > max) return v;
      }
    }
    if (v is num) {
      final min = f.min;
      final max = f.max;
      if (min != null && v < min) return v;
      if (max != null && v > max) return v;
    }
    return null;
  }



  _Value _invalid(FieldSchema f, String path, Object? value,
      {bool secret = false}) {
    final rule = f.onInvalid;
    final code = rule?['code'] as String? ?? _kDefaultInvalidCode;
    final action = rule?['action'] as String? ?? 'drop';
    switch (action) {
      case 'coerce':
        warn(code, path: path, value: value, secret: secret || f.secret);
        return _Value.keep(rule?['value']);





      case 'unwrap':
        if (value is! Map) {
          warn(_kDefaultInvalidCode,
              path: path, value: value, secret: secret || f.secret);
          explainedDrops.add(path);
          return const _Value.drop();
        }
        final key = rule?['key'] as String?;
        final member = key == null ? null : value[key];
        if (member != null) {
          final probe = _Ctx(
            scheme: scheme,
            coreVersion: coreVersion,
            platform: platform,
            applyCoreGates: applyCoreGates,
            source: source,
            kinds: kinds,
            root: root,
          );
          final plain = FieldSchema({...f.raw}..remove('on_invalid'));
          final res = probe._sanitizeScalar(member, plain, path);
          final blank = res.value is String && (res.value as String).trim().isEmpty;
          if (res.keep && probe.warnings.isEmpty && !blank) {
            warn(code, path: path, value: member, secret: secret || f.secret);
            return _Value.keep(res.value);
          }
        }
        final params = <String, String>{
          for (final e in value.entries)
            if (e.key != key &&
                (e.value is String || e.value is num || e.value is bool))
              '${e.key}': '${e.value}',
        };
        warn(rule?['else_code'] as String? ?? _kDefaultInvalidCode,
            path: path, params: params);
        explainedDrops.add(path);
        return const _Value.drop();
      case 'drop_node':

        warn(code,
            path: path,
            value: value,
            secret: secret || f.secret,
            params: {'field': path});
        dropNode = true;
        explicitDropNode = true;
        return const _Value.drop();
      default:
        warn(code, path: path, value: value, secret: secret || f.secret);


        explainedDrops.add(path);
        return const _Value.drop();
    }
  }


  void _applyRelations(
    Map<String, Object?> kept,
    List<String> order,
    Map<String, FieldSchema> fields,
    String prefix,
  ) {
















    for (final key in order) {
      if (!kept.containsKey(key)) continue;
      final f = fields[key];
      if (f == null) continue;
      final myPath = _join(prefix, key);
      for (final rel in f.conflicts) {
        final with0 = rel['with'] as String?;
        if (with0 == null) continue;
        if (!_conditionHolds(rel['when'], kept)) continue;



        final rootRival = !with0.contains('.') &&
            prefix.isNotEmpty &&
            !fields.containsKey(with0);
        if (rootRival
            ? !_presentInSource(with0, const {}, '')
            : !_presentInSource(with0, kept, prefix)) {
          continue;
        }
        if (_unlessHolds(rel, kept, prefix)) continue;
        kept.remove(key);
        _relWarn(order, order.indexOf(key), prefix,
            rel['code'] as String? ?? 'field_conflict',
            path: myPath, params: {'with': with0});


        explainedDrops.add(myPath);
        break;
      }
    }







    for (final key in order) {
      if (!kept.containsKey(key)) continue;
      final f = fields[key];
      if (f == null) continue;
      for (final rel in f.requires) {
        final need = rel['path'] as String?;
        if (need == null) continue;


        if (!_conditionHolds(rel['when'], kept)) continue;
        final ok = rel.containsKey('equals')
            ? _valueAt(need, kept, prefix) == rel['equals']
            : _present(need, kept, prefix);
        if (ok) continue;
        if (_unlessHolds(rel, kept, prefix)) continue;



        if (rel.containsKey('set')) {
          final target = need.contains('.') ? need : _join(prefix, need);
          if (_pathAllowed(target)) {
            _repairs.add(_Repair.set(
              index: _fieldEnd[_join(prefix, key)] ?? warnings.length,
              path: _join(prefix, key),
              target: target,
              need: need,
              value: rel['set'],
              code: rel['code'] as String? ?? 'field_requires',
            ));
            continue;
          }
        }
        kept.remove(key);


        if (!explainedDrops.contains(need)) {
          _relWarn(order, order.indexOf(key), prefix,
              rel['code'] as String? ?? 'field_requires',
              path: _join(prefix, key), params: {'requires': need});
        }
        break;
      }
    }
  }



  void _recordCoerceWhen(FieldSchema f, String path, Object? v) {
    final rule = f.raw['coerce_when'];
    if (rule is! Map) return;
    final values = rule['values'];
    if (values is! List || !values.any((e) => '$e' == '$v')) return;
    _repairs.add(_Repair.coerce(
      index: warnings.length,
      path: path,
      original: v,
      value: rule['value'],
      when: rule['when'],
      code: rule['code'] as String?,
    ));
  }



  bool _pathAllowed(String path) {
    Map<String, FieldSchema>? fields =
        ContractRegistry.I.schemaFor(scheme)?.fields;
    for (final seg in path.split('.')) {
      final f = fields?[seg];
      if (f == null) return false;
      if (f.forbiddenFor?.contains(scheme) ?? false) return false;
      final allowed = f.allowedFor;
      if (allowed != null && !allowed.contains(scheme)) return false;
      fields = f.fields;
    }
    return true;
  }



  void applyRepairs(Map<String, dynamic> out) {
    if (_repairs.isEmpty) return;
    final inserts = <(int, RegistryWarning)>[];
    for (final r in _repairs) {
      final w = r.apply(out, this);
      if (w != null) inserts.add((r.index, w));
    }
    for (var i = inserts.length - 1; i >= 0; i--) {
      warnings.insert(inserts[i].$1, inserts[i].$2);
    }
  }


  bool finalConditionHolds(Object? when, Map<String, dynamic> body) =>
      conditionOnFinalBody(when, body, kinds: kinds);





  static bool conditionOnFinalBody(
    Object? when,
    Map<String, dynamic> body, {
    Set<String> kinds = const {},
  }) {
    if (when is! Map) return true;
    var branches = false;
    for (final e in when.entries) {
      final key = '${e.key}';
      if (key == 'any_set' || key == 'source_kind') {
        branches = true;
        continue;
      }
      final got = finalAt(body, key);
      final present = got != null && !(got is String && got.isEmpty);
      final want = e.value;
      if (want is Map) {
        final inList = want['in'];
        final notIn = want['not_in'];
        if (inList is List) {
          if (!(present && inList.any((x) => '$x' == '$got'))) return false;
        } else if (notIn is List) {
          if (present && notIn.any((x) => '$x' == '$got')) return false;
        } else if (want.containsKey('type_of')) {
          if (!_typeOf(got, '${want['type_of']}')) return false;
        } else {
          return false;
        }
      } else if (!(present && '$want' == '$got')) {
        return false;
      }
    }
    if (!branches) return true;
    final sourceKind = (when['source_kind'] as List?)?.map((e) => '$e');
    if (sourceKind != null && sourceKind.any(kinds.contains)) return true;
    final anySet = (when['any_set'] as List?)?.map((e) => '$e');
    if (anySet != null) {
      for (final k in anySet) {
        final v = finalAt(body, k);
        if (v != null && !(v is String && v.isEmpty)) return true;
      }
    }
    return false;
  }

  static bool _typeOf(Object? v, String t) => switch (t) {
        'object' => v is Map,
        'array' => v is List,
        'string' => v is String,
        'number' => v is num,
        'bool' => v is bool,
        _ => false,
      };


  static Object? finalAt(Map<String, dynamic> body, String path) {
    Object? cur = body;
    for (final seg in path.split('.')) {
      if (cur is! Map || !cur.containsKey(seg)) return null;
      cur = cur[seg];
    }
    return cur;
  }







  Object? _valueAt(String path, Map<String, Object?> siblings, String prefix) {
    final last = path.split('.').last;
    if (siblings.containsKey(last)) return siblings[last];
    if (sanitized.containsKey(path)) return sanitized[path];
    Object? cur = root;
    for (final seg in path.split('.')) {
      if (cur is! Map || !cur.containsKey(seg)) return null;
      cur = cur[seg];
    }
    return cur;
  }



  bool _advisoryWhen(Object? when) {
    if (when == null) return true;
    if (when is! Map) return true;
    final path = when['path'] as String?;
    if (path == null) return true;
    final present = _present(path, const {}, '');
    return when['present'] == false ? !present : present;
  }







  bool _present(String path, Map<String, Object?> siblings, String prefix) {
    if (!path.contains('.')) {
      return siblings.containsKey(path) && _meaningful(siblings[path]);
    }


    if (sanitized.containsKey(path)) return _meaningful(sanitized[path]);
    final parent = path.substring(0, path.lastIndexOf('.'));

    if (sanitized.containsKey(parent) || _branchDone(parent)) return false;

    Object? cur = root;
    for (final seg in path.split('.')) {
      if (cur is! Map) return false;
      if (!cur.containsKey(seg)) return false;
      cur = cur[seg];
    }
    return _meaningful(cur);
  }







  bool _unlessHolds(
      Map<String, dynamic> rel, Map<String, Object?> siblings, String prefix) {
    final unless = rel['unless_set'];
    if (unless is! List) return false;
    for (final p in unless) {
      if (p is String && _presentInSource(p, siblings, prefix)) return true;
    }
    return false;
  }


  bool _switchedOff(String path) {
    if (switchedOff.isEmpty) return false;
    var p = path;
    while (true) {
      if (switchedOff.contains(p)) return true;
      final i = p.lastIndexOf('.');
      if (i < 0) return false;
      p = p.substring(0, i);
    }
  }















  bool _presentInSource(String path, Map<String, Object?> siblings, String prefix) {
    if (!path.contains('.')) {
      final abs = _join(prefix, path);




      if (_managedAt(abs)) return false;


      if (siblings.containsKey(path)) return _meaningful(siblings[path]);
      if (explainedDrops.contains(abs)) return false;
      if (_switchedOff(abs)) return false;
      if (sanitized.containsKey(abs)) return _meaningful(sanitized[abs]);
      return _meaningful(_rawAt(abs));
    }
    if (_managedAt(path)) return false;
    if (explainedDrops.contains(path)) return false;
    if (_switchedOff(path)) return false;
    if (sanitized.containsKey(path)) return _meaningful(sanitized[path]);
    final parent = path.substring(0, path.lastIndexOf('.'));


    if (sanitized.containsKey(parent) || _branchDone(parent)) return false;
    return _meaningful(_rawAt(path));
  }



  bool _managedAt(String path) {
    Map<String, FieldSchema>? fields =
        ContractRegistry.I.schemaFor(scheme)?.fields;
    FieldSchema? f;
    for (final seg in path.split('.')) {
      f = fields?[seg];
      if (f == null) return false;
      fields = f.fields;
    }
    return f?.managed ?? false;
  }


  Object? _rawAt(String path) {
    Object? cur = root;
    for (final seg in path.split('.')) {
      if (cur is! Map || !cur.containsKey(seg)) return null;
      cur = cur[seg];
    }
    return cur;
  }


  bool _branchDone(String prefix) =>
      sanitized.keys.any((k) => k.startsWith('$prefix.'));
















  static bool _meaningful(Object? v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.isNotEmpty && !_allZeroNumeric(v);
    if (v is Iterable) return v.isNotEmpty;
    if (v is Map) return v.isNotEmpty;
    return true;
  }




  static bool _allZeroNumeric(String s) {
    var sawDigit = false;
    for (final unit in s.codeUnits) {
      if (unit == 0x30) {
        sawDigit = true;
        continue;
      }


      if (unit == 0x2D || unit == 0x20) continue;
      return false;
    }
    return sawDigit;
  }

}

String _join(String prefix, String key) => prefix.isEmpty ? key : '$prefix.$key';



String _normalizeString(String v, String norm) {
  switch (norm) {
    case 'trim':
      return v.trim();
    case 'lower':
      return v.toLowerCase();
    case 'trim_lower':
      return v.trim().toLowerCase();



    case 'hex_only':
      final b = StringBuffer();
      for (final r in v.runes) {
        final c = String.fromCharCode(r);
        if (_reHexRune.hasMatch(c)) b.write(c.toLowerCase());
      }
      return b.toString();

















    case 'cidr_masked':
      return _cidrMasked(v);
    case 'range_order':
      final s = v.trim();
      final dash = s.indexOf('-');
      if (dash <= 0) return v;
      final lo = int.tryParse(s.substring(0, dash));
      final hi = int.tryParse(s.substring(dash + 1));
      if (lo == null || hi == null || lo <= hi) return v;
      return '$hi-$lo';










    case 'base64_std':



      final decoded = _decodeB64(v.trim());
      if (decoded == null) return v;
      final canon = base64.encode(decoded);


      _b64Key = canon;
      _b64Bytes = decoded;
      return canon;





















    case 'base64_rawurl':
      final raw = _decodeB64(v.trim());
      if (raw == null || raw.length != 32) return v;
      final canon = base64Url.encode(raw).replaceAll('=', '');
      _b64Key = canon;
      _b64Bytes = raw;
      return canon;



    case 'cidr_prefix':
      final a = v.trim();
      if (a.isEmpty || a.contains('/')) return v;
      return a.contains(':') ? '$a/128' : '$a/32';










    case 'duration_bare_seconds':
      final n = int.tryParse(v.trim());
      return n == null ? v : '${n}s';
    default:
      _logUnknownExpression('normalize', norm);
      return v;
  }
}

final _reHexRune = RegExp(r'^[0-9a-fA-F]$');







final _patternCache = <String, RegExp?>{};






RegExp? _compilePattern(String pattern) => _patternCache.putIfAbsent(pattern, () {
      try {
        return RegExp(pattern);
      } catch (_) {
        _logUnknownExpression('pattern', pattern);
        return null;
      }
    });






Object? _foldForNormalizeCode(Object? raw) =>
    raw is String ? raw.trim().toLowerCase() : raw;




final _seenUnknownExpressions = <String>{};



void _logUnknownExpression(String kind, String name) {
  if (!_seenUnknownExpressions.add('$kind:$name')) return;
  AppLog.I.warning(
      'RegistrySanitizer: неизвестное выражение реестра $kind=$name — '
      'значение оставлено как есть (контракт новее кода)');
}












({Object? value})? _coerceType(Object? value, String type) {
  switch (type) {
    case 'string':
      if (value is String) return (value: value);
      if (value is num || value is bool) return (value: value);
      return null;
    case 'bool':
      if (value is bool) return (value: value);
      if (value is String) {
        if (value == 'true') return (value: true);
        if (value == 'false') return (value: false);
      }
      return null;
    case 'int':
    case 'uint16':
      if (value is int) return (value: value);
      if (value is double && value == value.roundToDouble()) {
        return (value: value.toInt());
      }
      if (value is String) {
        final n = int.tryParse(value.trim());
        if (n != null) return (value: n);
      }
      return null;
    case 'duration':
      if (value is String) return (value: normalizeSingboxDuration(value.trim()));


      if (value is int) return (value: normalizeSingboxDuration('$value'));
      return null;
    case 'listable_string':
      if (value is String) return (value: value);
      if (value is List && value.every((e) => e is String || e is num)) {
        return (value: value);
      }
      return null;
    case 'string_array':



      if (value is List && value.every((e) => e is String || e is num)) {
        return (value: value);
      }
      return null;
    case 'enum':

      if (value is String || value is int) return (value: value);
      return null;












    case 'awg_range':
      if (value is int) return _uint32Ok(value) ? (value: value) : null;
      if (value is double && value == value.roundToDouble()) {
        final n = value.toInt();
        return _uint32Ok(n) ? (value: n) : null;
      }
      if (value is String && _reAwgRange.hasMatch(value.trim())) {
        final s = value.trim();
        final parts = [for (final p in s.split('-')) int.tryParse(p)];
        for (final n in parts) {
          if (n == null || !_uint32Ok(n)) return null;
        }






        if (parts.length == 2 && parts[0]! > parts[1]!) return null;
        return (value: s);
      }
      return null;


    case 'int_array':
      if (value is! List) return null;
      final out = <int>[];
      for (final e in value) {
        if (e is int) {
          out.add(e);
        } else if (e is double && e == e.roundToDouble()) {
          out.add(e.toInt());
        } else if (e is String && int.tryParse(e.trim()) != null) {
          out.add(int.parse(e.trim()));
        } else {
          return null;
        }
      }
      return (value: out);
    default:
      _logUnknownExpression('type', type);
      return (value: value);
  }
}


final _reAwgRange = RegExp(r'^\d+(-\d+)?$');



bool _uint32Ok(int n) => n >= 0 && n <= 0xFFFFFFFF;




String _cidrMasked(String v) {
  final s = v.trim();
  final slash = s.indexOf('/');
  final addrText = slash < 0 ? s : s.substring(0, slash);
  final addr = InternetAddress.tryParse(addrText);
  if (addr == null) return v;
  final bits = addr.rawAddress.length * 8;
  final len = slash < 0 ? bits : int.tryParse(s.substring(slash + 1));
  if (len == null || len < 0 || len > bits) return v;
  final raw = List<int>.of(addr.rawAddress);
  for (var i = 0; i < raw.length; i++) {
    final keep = len - i * 8;
    if (keep >= 8) continue;
    raw[i] = keep <= 0 ? 0 : raw[i] & (0xff << (8 - keep)) & 0xff;
  }
  final masked = InternetAddress.fromRawAddress(
      Uint8List.fromList(raw),
      type: addr.type);
  return '${masked.address}/$len';
}

(int, int)? _rangeSpan(Object? raw) {
  if (raw is int) return (raw, raw);
  if (raw is! String) return null;
  final s = raw.trim();
  final dash = s.indexOf('-');
  if (dash < 0) {
    final n = int.tryParse(s);
    return n == null ? null : (n, n);
  }
  final lo = int.tryParse(s.substring(0, dash));
  final hi = int.tryParse(s.substring(dash + 1));
  if (lo == null || hi == null) return null;
  return lo <= hi ? (lo, hi) : (hi, lo);
}

bool _formatOk(Object? v, String format) {
  if (v is List) return v.every((e) => _formatOk(e, format));
  switch (format) {
    case 'port':
      final n = v is int ? v : int.tryParse('$v');
      return n != null && n >= 1 && n <= 65535;
    case 'uuid':
      return v is String && _reUuid.hasMatch(v);
    case 'hex':
      return v is String && _reHex.hasMatch(v);
    case 'base64':
      return v is String && _reBase64.hasMatch(v);




    case 'base64_32':
      return v is String && _base64Bytes(v) == 32;
    case 'host':
      return v is String && v.isNotEmpty && !v.contains(' ');
    case 'ipv4':
      return v is String && _ipv4Ok(v);



    case 'url_path':
      return v is String && urlPathOk(v);





    case 'cidr':
      return v is String && _cidrOk(v);
    default:
      _logUnknownExpression('format', format);
      return true;
  }
}













int? _base64Bytes(String v) => _decodeB64(v.trim())?.length;





String? _b64Key;
List<int>? _b64Bytes;

List<int>? _decodeB64(String s) {
  if (s == _b64Key) return _b64Bytes;
  final bytes = decodeBase64Lenient(s);
  _b64Key = s;
  _b64Bytes = bytes;
  return bytes;
}

bool _ipv4Ok(String v) {
  final parts = v.split('.');
  if (parts.length != 4) return false;
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255) return false;
  }
  return true;
}



bool _cidrOk(String v) {
  final parts = v.split('/');
  if (parts.length != 2) return false;
  final bits = int.tryParse(parts[1]);
  if (bits == null) return false;
  final host = parts[0];
  if (_ipv4CidrHostOk(host)) return bits >= 0 && bits <= 32;
  if (_ipv6CidrHostOk(host)) return bits >= 0 && bits <= 128;
  return false;
}



bool _ipv4CidrHostOk(String host) {
  final parts = host.split('.');
  if (parts.length != 4) return false;
  for (final p in parts) {
    if (p.isEmpty) return false;
    if (p.length > 1 && p.startsWith('0')) return false;
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255) return false;
  }
  return true;
}



bool _ipv6CidrHostOk(String host) {
  if (host.contains('%')) return false;
  final addr = InternetAddress.tryParse(host);
  return addr != null && addr.type == InternetAddressType.IPv6;
}

final _reUuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
final _reHex = RegExp(r'^[0-9a-fA-F]*$');
final _reBase64 = RegExp(r'^[A-Za-z0-9+/_-]*={0,2}$');



bool coreAtLeast(String version, String required) {
  final a = _parseCore(version);
  final b = _parseCore(required);


  if (a == null) return true;
  if (b == null) return true;
  for (var i = 0; i < 4; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return true;
}

List<int>? _parseCore(String v) {
  if (v.isEmpty) return null;
  final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:-lx\.(\d+))?').firstMatch(v.trim());
  if (m == null) return null;
  return [
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    int.tryParse(m.group(4) ?? '0') ?? 0,
  ];
}



final class _Value {
  const _Value.keep(this.value) : keep = true;
  const _Value.drop()
      : keep = false,
        value = null;

  final bool keep;
  final Object? value;
}



final class _Repair {
  _Repair.set({
    required this.index,
    required this.path,
    required String this.target,
    required String this.need,
    required this.value,
    required this.code,
  })  : original = null,
        when = null;

  _Repair.coerce({
    required this.index,
    required this.path,
    required this.original,
    required this.value,
    required this.when,
    required this.code,
  })  : target = null,
        need = null;

  int index;
  final String path;
  final String? target;
  final String? need;
  final Object? original;
  final Object? value;
  final Object? when;
  final String? code;

  RegistryWarning? apply(Map<String, dynamic> out, _Ctx ctx) {
    final t = target;
    if (t != null) {

      if (!_Ctx._meaningful(_Ctx.finalAt(out, path))) return null;
      if (_Ctx._meaningful(_Ctx.finalAt(out, t))) return null;
      final segs = t.split('.');
      Map<String, dynamic> cur = out;
      for (final seg in segs.sublist(0, segs.length - 1)) {
        final next = cur[seg];
        if (next is Map<String, dynamic>) {
          cur = next;
        } else if (next == null) {
          final m = <String, dynamic>{};
          cur[seg] = m;
          cur = m;
        } else {
          return null;
        }
      }
      cur[segs.last] = value;
      return RegistryWarning(
          code: code ?? 'field_requires', path: path, params: {'requires': need!});
    }
    final got = _Ctx.finalAt(out, path);
    if (got == null || '$got' != '$original') return null;
    if (!ctx.finalConditionHolds(when, out)) return null;
    final segs = path.split('.');
    final parent = segs.length == 1
        ? out
        : _Ctx.finalAt(out, segs.sublist(0, segs.length - 1).join('.'));
    if (parent is! Map) return null;
    parent[segs.last] = value;
    final c = code;
    if (c == null) return null;
    return RegistryWarning(
        code: c,
        path: path,
        value: RegistrySanitizer.renderWarningValue(original as Object));
  }
}
