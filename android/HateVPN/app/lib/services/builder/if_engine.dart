import 'dart:async';
import 'dart:convert';

import '../../models/parser_config.dart';




















class Dropped {
  const Dropped._();
  static const instance = Dropped._();
}




const int _intMax = 65535;














dynamic coerceVarValue(String raw, String type, {String? name}) {
  switch (type) {
    case 'bool':





      return raw.trim().toLowerCase() == 'true';
    case 'int':



      final n = int.tryParse(raw.trim());
      if (n == null) {
        if (name != null) {
          reportTemplateWarning(
              templateWarnIntInvalid, {'name': name, 'value': raw});
        }
        return raw;
      }
      if (name != null && (n < 0 || n > _intMax)) {
        reportTemplateWarning(
            templateWarnIntClamped, {'name': name, 'value': raw});
      }
      return n.clamp(0, _intMax);
    case 'text_list':




      return splitTextList(raw);
    default:
      return raw;
  }
}



List<String> splitTextList(String raw) => [
      for (final line in raw.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];





const String templateWarnUnknownDirective = 'template_unknown_directive';
const String templateWarnVarUndeclared = 'template_var_undeclared';
const String templateWarnIntClamped = 'template_int_clamped';
const String templateWarnIntInvalid = 'template_int_invalid';
const String templateWarnFragmentDropped = 'template_fragment_dropped';


class TemplateWarning {
  const TemplateWarning(this.code, [this.params = const {}]);

  final String code;
  final Map<String, String> params;


  String get dedupKey {
    final keys = params.keys.toList()..sort();
    return jsonEncode([code, for (final k in keys) [k, params[k]]]);
  }

  @override
  bool operator ==(Object other) =>
      other is TemplateWarning && other.dedupKey == dedupKey;

  @override
  int get hashCode => dedupKey.hashCode;

  @override
  String toString() => params.isEmpty ? code : '$code $params';
}




class TemplateWarnings {
  final List<TemplateWarning> _items = [];
  final Set<String> _seen = {};

  void add(String code, [Map<String, String> params = const {}]) {
    final w = TemplateWarning(code, Map.unmodifiable(params));
    if (_seen.add(w.dedupKey)) _items.add(w);
  }

  List<TemplateWarning> get items => List.unmodifiable(_items);

  bool get isEmpty => _items.isEmpty;


  List<String> get codes => (_items.map((w) => w.code).toSet().toList())..sort();
}




final Object _warningsZoneKey = Object();



R collectTemplateWarnings<R>(TemplateWarnings sink, R Function() body) =>
    runZoned(body, zoneValues: {_warningsZoneKey: sink});



void reportTemplateWarning(String code,
    [Map<String, String> params = const {}]) {
  final sink = Zone.current[_warningsZoneKey];
  if (sink is TemplateWarnings) sink.add(code, params);
}





const String _runtimePrefix = 'runtime.';




const Set<String> _runtimeFields = {'platform', 'arch', 'target'};


bool isRuntimeRef(String name) => name.startsWith(_runtimePrefix);


bool isKnownRuntimeGlobal(String name) =>
    isRuntimeRef(name) &&
    _runtimeFields.contains(name.substring(_runtimePrefix.length));








dynamic _resolveRef(String name, VarResolver resolve) {
  if (isRuntimeRef(name)) {
    if (isKnownRuntimeGlobal(name)) return Dropped.instance;
    reportTemplateWarning(templateWarnVarUndeclared, {'name': name});
    return null;
  }
  final v = resolve(name);
  if (v == null) {
    reportTemplateWarning(templateWarnVarUndeclared, {'name': name});
  }
  return v;
}




final Map<String, RegExp> _matchCache = {};

RegExp _regexpFor(String pattern) =>
    _matchCache[pattern] ??= RegExp(pattern);




typedef VarResolver = dynamic Function(String name);



VarResolver makeResolver(
  Map<String, String> vars,
  Map<String, WizardVar> nodes,
) {
  return (String name) {
    final raw = vars[name];
    if (raw == null) return null;
    final node = nodes[name];
    return coerceVarValue(raw, node?.type ?? 'text', name: name);
  };
}












bool isIfKey(String k) => k == '#if' || k.startsWith('#if');




List<String> ifKeysSorted(Map<String, dynamic> m) {
  final keys = m.keys.where(isIfKey).toList();
  keys.sort();
  return keys;
}







dynamic walk(dynamic node, VarResolver resolve) {
  if (node is String) {
    if (!node.startsWith('@')) return node;
    final name = node.substring(1);


    final v = _resolveRef(name, resolve);
    if (v == null) {

      return node;
    }


    if (identical(v, Dropped.instance)) return Dropped.instance;
    return v;
  }

  if (node is Map<String, dynamic>) {

    if (node.containsKey(tplKey)) return evalTpl(node, resolve);


    return _walkMap(node, resolve);
  }

  if (node is List) {
    return _walkList(node, resolve);
  }

  return node;
}


const String tplKey = '#tpl';


final RegExp _tplSlot = RegExp(r'@\{([^{}]+)\}');








dynamic evalTpl(Map<String, dynamic> node, VarResolver resolve) {
  final pattern = node[tplKey];
  if (node.length != 1 || pattern is! String) {
    reportTemplateWarning(templateWarnUnknownDirective, {'key': tplKey});
    return Dropped.instance;
  }
  var dropped = false;
  final out = pattern.replaceAllMapped(_tplSlot, (m) {
    if (dropped) return '';
    final v = _resolveRef(m.group(1)!.trim(), resolve);
    final text = (v is String || v is num || v is bool) ? _scalar(v) : '';
    if (text.isEmpty) dropped = true;
    return text;
  });
  return dropped ? Dropped.instance : out;
}










dynamic condKey(Map<String, dynamic> m, String word) =>
    m.containsKey('#$word') ? m['#$word'] : m[word];

bool hasCondKey(Map<String, dynamic> m, String word) =>
    m.containsKey('#$word') || m.containsKey(word);



bool condFormValid(dynamic cond) {
  if (cond is String || cond is List) return true;
  if (cond is Map<String, dynamic>) {
    final hasAnd = hasCondKey(cond, 'and');
    final hasOr = hasCondKey(cond, 'or');
    if (hasAnd && hasOr) return false;
    if (hasAnd || hasOr) return true;
    return cond.length == 1;
  }
  return false;
}




const String enableKey = '#enable';

dynamic _walkMap(Map<String, dynamic> obj, VarResolver resolve) {







  if (obj.containsKey(enableKey)) {
    final gate = obj.remove(enableKey);


    if (!condFormValid(gate)) {
      reportTemplateWarning(templateWarnUnknownDirective, {'key': enableKey});
    }
    if (!evalCond(gate, resolve)) return Dropped.instance;
  }




  final ifKeys = ifKeysSorted(obj);
  final unknownBang = <String>[];
  for (final k in obj.keys) {
    if (!k.startsWith('#')) continue;
    if (isIfKey(k)) continue;
    unknownBang.add(k);
  }
  for (final k in unknownBang) {
    obj.remove(k);



    reportTemplateWarning(templateWarnUnknownDirective, {'key': k});
  }


  final toRemove = <String>[];
  for (final k in obj.keys.toList()) {
    if (isIfKey(k)) continue;
    final replaced = walk(obj[k], resolve);
    if (identical(replaced, Dropped.instance)) {
      toRemove.add(k);
    } else {
      obj[k] = replaced;
    }
  }
  for (final k in toRemove) {
    obj.remove(k);
  }




  for (final key in ifKeys) {
    final raw = obj[key];
    obj.remove(key);
    if (raw is! Map<String, dynamic>) {

      reportTemplateWarning(templateWarnUnknownDirective, {'key': key});
      continue;
    }
    final branch = _selectBranch(raw, resolve, key);
    if (branch != null) {

      branch.forEach((k, v) {
        obj[k] = v;
      });
    }
  }

  return obj;
}

dynamic _walkList(List<dynamic> list, VarResolver resolve) {
  final out = <dynamic>[];
  for (final elem in list) {


    if (elem is Map<String, dynamic> && elem.length == 1) {
      final key = elem.keys.first;
      if (isIfKey(key)) {
        final body = elem[key];
        if (body is Map<String, dynamic>) {
          final taken = _selectArrayBranch(body, resolve, key);
          if (identical(taken, Dropped.instance)) continue;






          if (taken is List) {
            out.addAll(taken);
          } else {
            out.add(taken);
          }
          continue;
        }
      }
    }





    if (elem is String && elem.startsWith('@')) {
      final value = walk(elem, resolve);
      if (identical(value, Dropped.instance)) continue;
      if (value is List) {
        out.addAll(value);
      } else {
        out.add(value);
      }
      continue;
    }
    final replaced = walk(elem, resolve);
    if (identical(replaced, Dropped.instance)) continue;
    out.add(replaced);
  }
  list
    ..clear()
    ..addAll(out);
  return list;
}



Map<String, dynamic>? _selectBranch(
  Map<String, dynamic> body,
  VarResolver resolve,
  String key,
) {
  final ok = _evalCondition(body, resolve, key: key);
  final picked = ok ? condKey(body, 'value') : condKey(body, 'else');
  if (picked == null) {



    if (ok) reportTemplateWarning(templateWarnUnknownDirective, {'key': key});
    return null;
  }

  final walked = walk(_clone(picked), resolve);
  return walked is Map<String, dynamic> ? walked : null;
}



dynamic _selectArrayBranch(
  Map<String, dynamic> body,
  VarResolver resolve, [
  String key = '#if',
]) {
  final ok = _evalCondition(body, resolve, key: key);
  if (ok) {
    return walk(_clone(condKey(body, 'value')), resolve);
  }
  if (hasCondKey(body, 'else')) {
    return walk(_clone(condKey(body, 'else')), resolve);
  }
  return Dropped.instance;
}









String? evalIfScalar(Map<String, dynamic> node, VarResolver resolve) {
  if (node.length != 1) return null;
  final key = node.keys.first;
  if (!isIfKey(key)) return null;
  final body = node[key];
  if (body is! Map<String, dynamic>) return null;
  final picked = _selectArrayBranch(body, resolve, key);
  return picked is String ? picked : null;
}






bool _evalCondition(
  Map<String, dynamic> body,
  VarResolver resolve, {
  String key = '#if',
}) {
  final and = condKey(body, 'and');
  final or = condKey(body, 'or');



  if ((and is List) == (or is List)) {
    reportTemplateWarning(templateWarnUnknownDirective, {'key': key});
    return false;
  }
  if (and is List) {
    for (final p in and) {


      if (!evalCond(p, resolve)) return false;
    }
    return true;
  }
  for (final p in or as List) {
    if (evalCond(p, resolve)) return true;
  }
  return false;
}








bool evalCond(dynamic cond, VarResolver resolve) {
  if (cond is List) {
    for (final e in cond) {
      if (!evalCond(e, resolve)) return false;
    }
    return true;
  }
  if (cond is Map<String, dynamic>) {



    if (hasCondKey(cond, 'and') || hasCondKey(cond, 'or')) {
      return _evalCondition(cond, resolve);
    }
  }
  return _evalPredicate(cond, resolve);
}







bool _evalPredicate(dynamic pred, VarResolver resolve) {

  if (pred is String) {



    final parsed = parseJsonPredicateString(pred);
    if (parsed != null) return evalCond(parsed, resolve);
    final name = _varName(pred);
    if (name == null) return false;

    if (isKnownRuntimeGlobal(name)) return false;

    return _scalar(_resolveRef(name, resolve)).trim().toLowerCase() == 'true';
  }

  if (pred is Map<String, dynamic>) {

    final notInner = pred['#not'];
    if (pred.containsKey('#not')) {

      return !evalCond(notInner, resolve);
    }


    if (pred.length == 1) {
      final key = pred.keys.first;
      final name = _varName(key);
      if (name == null) return false;


      if (isKnownRuntimeGlobal(name)) return false;
      final arg = pred[key];
      final resolvedValue = _resolveRef(name, resolve);
      final scalar = _scalar(resolvedValue);

      if (arg is String) {




        if (arg == '#notEmpty') return _isNotEmptyTyped(resolvedValue, scalar);
        if (arg == '#isEmpty') return !_isNotEmptyTyped(resolvedValue, scalar);


        return scalar.trim() == _substRhs(arg, resolve);
      }
      if (arg is Map<String, dynamic> && arg.length == 1) {
        final op = arg.keys.first;
        final opArg = arg[op];
        switch (op) {
          case '#in':
            return _inList(scalar.trim(), opArg, resolve);
          case '#notIn':
            return !_inList(scalar.trim(), opArg, resolve);
          case '#matches':
            if (opArg is! String) return false;
            return _regexpFor(_substRhs(opArg, resolve))
                .hasMatch(scalar.trim());
        }
      }
    }
  }
  return false;
}



dynamic parseJsonPredicateString(String s) {
  final t = s.trim();
  if (!t.startsWith('{')) return null;
  try {
    return jsonDecode(t);
  } catch (_) {
    return null;
  }
}


String? _varName(String ref) =>
    ref.startsWith('@') ? ref.substring(1) : null;





String _substRhs(String rhs, VarResolver resolve) {
  final name = _varName(rhs);
  if (name == null) return rhs;
  final v = _resolveRef(name, resolve);
  if (v == null || identical(v, Dropped.instance)) return rhs;
  return _scalar(v).trim();
}




bool _isNotEmptyTyped(dynamic value, String scalar) {
  if (value == null || identical(value, Dropped.instance)) return false;
  if (value is bool) return value;
  if (value is List) return value.isNotEmpty;
  return scalar.trim().isNotEmpty;
}




bool _inList(String needle, dynamic arg, VarResolver resolve) {
  if (arg is List) {
    for (final e in arg) {
      if (e is String && _substRhs(e, resolve) == needle) return true;
      if (e is! String && _scalar(e).trim() == needle) return true;
    }
    return false;
  }
  if (arg is String) {

    final name = _varName(arg);
    if (name == null) return arg.trim() == needle;
    final v = _resolveRef(name, resolve);
    if (v is List) return v.map((e) => _scalar(e).trim()).contains(needle);
    if (v == null || identical(v, Dropped.instance)) return false;
    return _scalar(v).trim() == needle;
  }
  return false;
}



String _scalar(dynamic v) {
  if (v == null || identical(v, Dropped.instance)) return '';
  if (v is bool) return v ? 'true' : 'false';
  return v.toString();
}



dynamic _clone(dynamic node) {
  if (node is Map) {
    return <String, dynamic>{
      for (final e in node.entries) e.key as String: _clone(e.value),
    };
  }
  if (node is List) {
    return <dynamic>[for (final e in node) _clone(e)];
  }
  return node;
}








class TemplateIfError implements Exception {
  final String message;
  TemplateIfError(this.message);
  @override
  String toString() => 'TemplateIfError: $message';
}



const _noArgPredicates = {'#notEmpty', '#isEmpty'};
const _argPredicates = {'#in', '#notIn', '#matches'};





void validateIfConstructs(
  dynamic node,
  Map<String, WizardVar> byName, {
  String path = 'config',
}) {
  if (node is Map<String, dynamic>) {

    if (node.containsKey(tplKey)) {
      if (node.length != 1) {
        throw TemplateIfError('$path: `#tpl` не допускает других ключей');
      }
      if (node[tplKey] is! String) {
        throw TemplateIfError('$path: `#tpl` ожидает строку');
      }
      return;
    }
    for (final entry in node.entries) {
      final k = entry.key;
      if (isIfKey(k)) {
        _validateIfBody(entry.value, byName, '$path.$k');

        continue;
      }
      if (k == enableKey) {







        validateCondNode(entry.value, byName, '$path.$k');
        continue;
      }
      if (k.startsWith('#')) {


        continue;
      }
      validateIfConstructs(entry.value, byName, path: '$path.$k');
    }
    return;
  }
  if (node is List) {
    for (var i = 0; i < node.length; i++) {
      validateIfConstructs(node[i], byName, path: '$path[$i]');
    }
  }
}








void validateCondNode(
  dynamic cond,
  Map<String, WizardVar> byName,
  String path,
) {

  if (cond is List) {
    if (cond.isEmpty) {
      throw TemplateIfError('$path: список предикатов должен быть непустым');
    }
    for (var i = 0; i < cond.length; i++) {
      _validatePredicate(cond[i], byName, '$path[$i]');
    }
    return;
  }
  if (cond is Map<String, dynamic>) {
    if (hasCondKey(cond, 'and') || hasCondKey(cond, 'or')) {
      _validateCondObjLists(cond, byName, path);
      return;
    }
    _validatePredicate(cond, byName, path);
    return;
  }


  _validatePredicate(cond, byName, path);
}




void _validateCondObjLists(
  Map<String, dynamic> body,
  Map<String, WizardVar> byName,
  String path,
) {



  final hasAnd = hasCondKey(body, 'and');
  final hasOr = hasCondKey(body, 'or');
  if (hasAnd == hasOr) {
    throw TemplateIfError(
        '$path: ровно один из `and`/`or` обязателен (есть оба или ни одного)');
  }
  final word = hasAnd ? 'and' : 'or';
  final list = condKey(body, word);
  if (list is! List || list.isEmpty) {
    throw TemplateIfError('$path: `$word` должен быть непустым списком');
  }
  for (var i = 0; i < list.length; i++) {
    _validatePredicate(list[i], byName, '$path.$word[$i]');
  }
}

void _validateIfBody(
  dynamic body,
  Map<String, WizardVar> byName,
  String path,
) {
  if (body is! Map<String, dynamic>) {
    throw TemplateIfError('$path: тело #if должно быть объектом');
  }
  _validateCondObjLists(body, byName, path);
  if (!hasCondKey(body, 'value')) {
    throw TemplateIfError('$path: `value` обязателен');
  }


  const allowed = {
    'and', 'or', 'value', 'else',
    '#and', '#or', '#value', '#else',
  };
  for (final k in body.keys) {
    if (!allowed.contains(k)) {
      throw TemplateIfError(
          '$path: неизвестный inner-ключ `$k` (схема тела #if закрыта: '
          '#and/#or/#value/#else, легаси — без `#`)');
    }
  }

  validateIfConstructs(condKey(body, 'value'), byName, path: '$path.value');
  if (hasCondKey(body, 'else')) {
    validateIfConstructs(condKey(body, 'else'), byName, path: '$path.else');
  }
}

void _validatePredicate(
  dynamic pred,
  Map<String, WizardVar> byName,
  String path,
) {

  if (pred is String) {



    final parsed = parseJsonPredicateString(pred);
    if (parsed != null) {
      validateCondNode(parsed, byName, path);
      return;
    }
    final name = _varName(pred);
    if (name == null) {
      throw TemplateIfError('$path: предикат-строка должна быть `@var`-формой');
    }
    final node = _requireVar(byName, name, path);
    if (node.type != 'bool') {
      throw TemplateIfError(
          '$path: bare-предикат `@$name` допустим только для bool-var (тип `${node.type}`)');
    }
    return;
  }

  if (pred is Map<String, dynamic>) {




    if (hasCondKey(pred, 'and') || hasCondKey(pred, 'or')) {
      _validateCondObjLists(pred, byName, path);
      return;
    }

    if (pred.containsKey('#not')) {
      if (pred.length != 1) {
        throw TemplateIfError('$path: `#not` должен быть единственным ключом');
      }


      validateCondNode(pred['#not'], byName, '$path.#not');
      return;
    }
    if (pred.length != 1) {
      throw TemplateIfError(
          '$path: предикат-объект должен иметь ровно один ключ `@var`');
    }
    final key = pred.keys.first;
    final name = _varName(key);
    if (name == null) {
      throw TemplateIfError('$path: ключ предиката `$key` должен быть `@var`');
    }
    final node = _requireVar(byName, name, path);
    final arg = pred[key];

    if (arg is String) {
      if (_noArgPredicates.contains(arg)) {

        return;
      }
      if (arg.startsWith('#')) {
        throw TemplateIfError(
            '$path: неизвестный no-arg предикат-оператор `$arg`');
      }

      if (node.type == 'bool') {
        throw TemplateIfError(
            '$path: equality `{@$name: "$arg"}` не для bool-var (используй bare `@$name`)');
      }
      return;
    }
    if (arg is Map<String, dynamic> && arg.length == 1) {
      final op = arg.keys.first;
      if (!_argPredicates.contains(op)) {
        throw TemplateIfError('$path: неизвестный предикат-оператор `$op`');
      }
      if (node.type == 'bool') {
        throw TemplateIfError('$path: `$op` не для bool-var `@$name`');
      }
      final opArg = arg[op];
      if (op == '#matches') {
        if (opArg is! String) {
          throw TemplateIfError('$path: `#matches` ожидает строку-regexp');
        }
        try {
          _regexpFor(opArg);
        } on FormatException catch (e) {
          throw TemplateIfError('$path: невалидный `#matches` regexp: $e');
        }
      } else if (opArg is String) {





        final ref = _varName(opArg);
        if (ref != null) _requireVar(byName, ref, path);
      } else if (opArg is! List) {
        throw TemplateIfError('$path: `$op` ожидает список аргументов');
      }
      return;
    }
    throw TemplateIfError('$path: нераспознанная форма предиката');
  }
  throw TemplateIfError('$path: предикат должен быть строкой или объектом');
}

WizardVar _requireVar(
  Map<String, WizardVar> byName,
  String name,
  String path,
) {
  final node = byName[name];
  if (node == null && isKnownRuntimeGlobal(name)) {



    return WizardVar(name: name, type: 'text', defaultValue: '');
  }
  if (node == null) {
    throw TemplateIfError(
        '$path: предикат ссылается на необъявленную var `@$name` (нужна WizardVar-нода)');
  }
  return node;
}





















List<String> condDeps(dynamic cond) {
  final set = <String>{};
  _collectCondDeps(cond, set);
  final out = set.toList()..sort();
  return out;
}

void _collectCondDeps(dynamic cond, Set<String> set) {
  if (cond is List) {
    for (final e in cond) {
      _collectCondDeps(e, set);
    }
    return;
  }
  if (cond is Map<String, dynamic>) {
    final and = condKey(cond, 'and');
    if (and is List) {
      for (final e in and) {
        _collectCondDeps(e, set);
      }
      return;
    }
    final or = condKey(cond, 'or');
    if (or is List) {
      for (final e in or) {
        _collectCondDeps(e, set);
      }
      return;
    }
    _collectPredicateDeps(cond, set);
    return;
  }
  if (cond is String) {

    final parsed = parseJsonPredicateString(cond);
    if (parsed != null) {
      _collectCondDeps(parsed, set);
      return;
    }
    _noteVarName(cond, set);
  }
}

void _collectPredicateDeps(Map<String, dynamic> p, Set<String> set) {
  p.forEach((k, v) {
    if (k == '#not') {
      _collectCondDeps(v, set);
      return;
    }
    _noteVarName(k, set);
    _collectRhsDeps(v, set);
  });
}



void _collectRhsDeps(dynamic rhs, Set<String> set) {
  if (rhs is String) {

    if (!rhs.startsWith('#')) _noteVarName(rhs, set);
    return;
  }
  if (rhs is List) {
    for (final e in rhs) {
      _collectRhsDeps(e, set);
    }
    return;
  }
  if (rhs is Map<String, dynamic>) {
    for (final arg in rhs.values) {
      _collectRhsDeps(arg, set);
    }
  }
}

void _noteVarName(String ref, Set<String> set) {
  if (!ref.startsWith('@')) return;
  final name = ref.substring(1);
  if (name.isEmpty || name.contains('@')) return;
  set.add(name);
}
