import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import 'package:lxbox/services/l10n/plural_resolver.dart';

















const Set<String> _localizerNames = {'getLocalText', 't', 'loc'};


class UiKeyUse {
  UiKeyUse({
    required this.file,
    required this.line,
    required this.key,
    required this.formIndex,
    required this.isPlural,
  });

  final String file;
  final int line;




  final String key;


  final int formIndex;


  final bool isPlural;
}


class DynamicKeyUse {
  DynamicKeyUse(this.file, this.line, this.isPlural);
  final String file;
  final int line;
  final bool isPlural;
}


class UiScanResult {
  final List<UiKeyUse> uses = [];
  final List<DynamicKeyUse> dynamicKeys = [];
}



UiScanResult scanForUiKeys({required String path, required String content}) {
  final parsed =
      parseString(content: content, path: path, throwIfDiagnostics: false);
  final res = UiScanResult();
  parsed.unit
      .accept(_UiVisitor(path, parsed.lineInfo, res));
  return res;
}

class _UiVisitor extends RecursiveAstVisitor<void> {
  _UiVisitor(this.file, this.lineInfo, this.res);

  final String file;
  final LineInfo lineInfo;
  final UiScanResult res;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if ((name == 's' || name == 'plural') && _isLocalizer(node.target)) {
      _handle(node, isPlural: name == 'plural');
    }
    super.visitMethodInvocation(node);
  }



  bool _isLocalizer(Expression? target) {
    if (target == null) return false;
    if (target is SimpleIdentifier) return _localizerNames.contains(target.name);

    if (target is PrefixedIdentifier) {
      return target.prefix.name == 'GetLocalText' &&
          target.identifier.name == 'en';
    }

    if (target is PropertyAccess) {
      return target.propertyName.name == 'en' &&
          target.target?.toSource() == 'GetLocalText';
    }
    return false;
  }

  void _handle(MethodInvocation node, {required bool isPlural}) {


    final args = node.argumentList.arguments;
    if (args.isEmpty) return;
    final line = lineInfo.getLocation(node.methodName.offset).lineNumber;


    var idx = 0;
    var formIndex = 0;
    final first = args[0];
    if (first is IntegerLiteral && first.value != null) {
      formIndex = first.value!;
      idx = 1;
    }
    if (idx >= args.length) {


      res.dynamicKeys.add(DynamicKeyUse(file, line, isPlural));
      return;
    }
    final keyExpr = args[idx];
    final key = _literalKey(keyExpr);
    if (key == null) {
      res.dynamicKeys.add(DynamicKeyUse(file, line, isPlural));
      return;
    }
    res.uses.add(UiKeyUse(
      file: file,
      line: line,
      key: key,
      formIndex: formIndex,
      isPlural: isPlural,
    ));
  }





  String? _literalKey(Expression e) {
    if (e is SimpleStringLiteral) return e.value;
    if (e is AdjacentStrings) {

      final buf = StringBuffer();
      for (final s in e.strings) {
        if (s is SimpleStringLiteral) {
          buf.write(s.value);
        } else {
          return null;
        }
      }
      return buf.toString();
    }

    return null;
  }
}







Set<int> placeholderSlots(String template) {
  final slots = <int>{};
  var seq = 0;
  var i = 0;
  while (i < template.length) {
    if (template[i] != '%') {
      i++;
      continue;
    }
    if (i + 1 >= template.length) break;
    final next = template[i + 1];
    if (next == '%') {
      i += 2;
      continue;
    }
    if (_isDigit(next)) {
      var j = i + 1;
      while (j < template.length && _isDigit(template[j])) {
        j++;
      }
      if (j + 1 < template.length && template[j] == r'$') {
        slots.add(int.parse(template.substring(i + 1, j)));
        i = j + 2;
        continue;
      }

      i++;
      continue;
    }
    if (next == 's' || next == 'd') {
      seq++;
      slots.add(seq);
      i += 2;
      continue;
    }
    i++;
  }
  return slots;
}

bool _isDigit(String c) {
  final u = c.codeUnitAt(0);
  return u >= 0x30 && u <= 0x39;
}




class UiFinding {
  UiFinding(this.kind, this.message);
  final UiFindingKind kind;
  final String message;
}

enum UiFindingKind {

  missing,


  orphan,



  orphanSpecial,


  usageConflict,



  shape,


  arity,
}


class UiValidation {
  final List<UiFinding> findings = [];
  int keys = 0;
  int missing = 0;
  int orphan = 0;
  int arityErrors = 0;
  int dynamicSkipped = 0;

  bool get hasFail => findings.any((f) =>
      f.kind == UiFindingKind.usageConflict ||
      f.kind == UiFindingKind.shape ||
      f.kind == UiFindingKind.arity);
}





UiValidation validateUiKeys({
  required List<UiKeyUse> uses,
  required int dynamicCount,
  required Map<String, dynamic> dict,
  required Set<String> forms,
}) {
  final v = UiValidation();
  v.dynamicSkipped = dynamicCount;


  final asS = <String>{};
  final asPlural = <String>{};

  final usedIndices = <String, Set<int>>{};
  for (final u in uses) {
    (u.isPlural ? asPlural : asS).add(u.key);
    usedIndices.putIfAbsent(u.key, () => {}).add(u.formIndex);
  }
  final allKeys = {...asS, ...asPlural};
  v.keys = allKeys.length;


  for (final k in asS.intersection(asPlural)) {
    v.findings.add(UiFinding(UiFindingKind.usageConflict,
        'key "$k" is invoked both as .s and .plural — pick one'));
  }


  for (final k in (allKeys.toList()..sort())) {
    if (!dict.containsKey(k)) {
      v.missing++;
      v.findings.add(UiFinding(
          UiFindingKind.missing, 'key "$k" is missing from the dictionary'));
    }
  }


  for (final k in (dict.keys.toList()..sort())) {
    if (!allKeys.contains(k)) {
      v.orphan++;
      v.findings.add(UiFinding(
          UiFindingKind.orphan, 'dictionary key "$k" is never referenced in code'));
    }
  }


  for (final k in (allKeys.toList()..sort())) {
    final entry = dict[k];
    if (entry is! Map) continue;

    final wantsPlural = asPlural.contains(k);
    final wantsString = asS.contains(k);
    final rootValue = entry['value'];


    final indices = usedIndices[k] ?? const <int>{};
    final keySlots = placeholderSlots(k);

    if (indices.contains(0)) {
      _checkForm(
        v: v,
        key: k,
        label: 'value',
        value: rootValue,
        wantsPlural: wantsPlural,
        wantsString: wantsString,
        forms: forms,
        keySlots: keySlots,
      );
    }


    final special = entry['special'];
    final specialMap = special is Map ? special : const {};
    for (final idx in indices.where((i) => i >= 1)) {
      final form = specialMap['$idx'];
      if (form is! Map || !form.containsKey('value')) {
        v.findings.add(UiFinding(UiFindingKind.shape,
            'key "$k" uses special form $idx but dictionary has no special["$idx"].value'));
        continue;
      }
      _checkForm(
        v: v,
        key: k,
        label: 'special[$idx]',
        value: form['value'],

        wantsPlural: wantsPlural,
        wantsString: wantsString,
        forms: forms,
        keySlots: keySlots,
      );
    }


    for (final sk in specialMap.keys) {
      final n = int.tryParse('$sk');
      if (n == null) continue;
      if (!indices.contains(n)) {
        v.findings.add(UiFinding(UiFindingKind.orphanSpecial,
            'key "$k" defines special form $sk but code never uses that index'));
      }
    }
  }

  v.arityErrors =
      v.findings.where((f) => f.kind == UiFindingKind.arity).length;
  return v;
}



void _checkForm({
  required UiValidation v,
  required String key,
  required String label,
  required Object? value,
  required bool wantsPlural,
  required bool wantsString,
  required Set<String> forms,
  required Set<int> keySlots,
}) {

  if (wantsPlural) {
    if (value is! Map) {
      v.findings.add(UiFinding(UiFindingKind.shape,
          'key "$key" is used as .plural but $label is not a plural object'));
      return;
    }
    final have = value.keys.map((e) => '$e').toSet();
    final missingForms = forms.difference(have);
    if (missingForms.isNotEmpty) {
      v.findings.add(UiFinding(UiFindingKind.shape,
          'key "$key" $label plural object is missing forms: '
          '{${(missingForms.toList()..sort()).join(', ')}}'));
    }

    for (final f in (forms.intersection(have).toList()..sort())) {
      final formStr = value[f];
      if (formStr is! String) {
        v.findings.add(UiFinding(UiFindingKind.shape,
            'key "$key" $label plural form "$f" is not a string'));
        continue;
      }
      _checkArity(v, key, '$label.$f', keySlots, formStr);
    }
    return;
  }


  if (wantsString) {
    if (value is! String) {
      v.findings.add(UiFinding(UiFindingKind.shape,
          'key "$key" is used as .s but $label is not a string'));
      return;
    }
    _checkArity(v, key, label, keySlots, value);
  }
}

void _checkArity(
    UiValidation v, String key, String label, Set<int> keySlots, String value) {
  final valueSlots = placeholderSlots(value);
  if (!(keySlots.length == valueSlots.length &&
      keySlots.containsAll(valueSlots))) {
    v.findings.add(UiFinding(
        UiFindingKind.arity,
        'key "$key" placeholder arity mismatch in $label: '
        'key {${(keySlots.toList()..sort()).join(', ')}} vs '
        'value {${(valueSlots.toList()..sort()).join(', ')}}'));
  }
}


Set<String> ruForms() => const RuPluralResolver().forms;




Set<String> formsForTag(String tag) => switch (tag) {
      'ru' => const RuPluralResolver().forms,
      'zh' => const ZhPluralResolver().forms,
      _ => const EnPluralResolver().forms,
    };
