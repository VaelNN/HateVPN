import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import '../contract_paths.dart';
import 'package:lxbox/models/parser_config.dart';
import 'package:lxbox/services/builder/if_engine.dart';
























class _Case {
  _Case({
    required this.name,
    required this.vars,
    required this.config,
    required this.changed,
    required this.varValues,
    required this.expected,
  });

  final String name;
  final List<WizardVar> vars;
  final dynamic config;



  final String changed;


  final Map<String, String?> varValues;

  final Map<String, dynamic> expected;
}

_Case _loadCase(String base) {
  final tpl = jsonDecode(File('$base.template.json').readAsStringSync())
      as Map<String, dynamic>;
  final varsRaw = jsonDecode(File('$base.vars.json').readAsStringSync())
      as Map<String, dynamic>;
  final expected = jsonDecode(File('$base.expected.json').readAsStringSync())
      as Map<String, dynamic>;

  final vars = <WizardVar>[
    for (final v in (tpl['vars'] as List? ?? const []))
      WizardVar.fromJson(v as Map<String, dynamic>),
  ];

  return _Case(
    name: base,
    vars: vars,
    config: tpl['config'],
    changed: (tpl['_changed'] as String?) ?? '',
    varValues: {
      for (final e in varsRaw.entries) e.key: e.value as String?,
    },
    expected: expected,
  );
}






VarResolver _canonResolver(_Case c) {
  final nodes = {for (final v in c.vars) v.name: v};
  final declared = nodes.keys.toSet();

  return (String name) {
    if (!declared.contains(name)) {
      return null;
    }
    final raw = c.varValues[name];
    if (raw == null) {

      final fallback = nodes[name]?.defaultValue ?? '';
      if (fallback.isEmpty && c.varValues.containsKey(name)) {
        return Dropped.instance;
      }
      if (fallback.isEmpty) return Dropped.instance;
      return coerceVarValue(fallback, nodes[name]!.type, name: name);
    }
    return coerceVarValue(raw, nodes[name]!.type, name: name);
  };
}


Map<String, dynamic> _runCase(_Case c) {
  final warns = TemplateWarnings();



  final state = <String, String>{
    for (final e in c.varValues.entries)
      if (e.value != null) e.key: e.value!,
  };



  if (c.changed.isNotEmpty) {
    collectTemplateWarnings(
        warns, () => _applyOnChange(c.changed, c.vars, state));
  }

  final caseWithState = _Case(
    name: c.name,
    vars: c.vars,
    config: c.config,
    changed: c.changed,
    varValues: {
      for (final e in c.varValues.entries)
        e.key: e.value == null ? null : state[e.key],
      for (final e in state.entries) e.key: e.value,
    },
    expected: c.expected,
  );


  final resolved = collectTemplateWarnings(
    warns,
    () => walk(_deepCopy(c.config), _canonResolver(caseWithState)),
  );

  final out = <String, dynamic>{
    'config': identical(resolved, Dropped.instance) ? {} : resolved,
    'warnings': warns.codes,
  };
  if (c.changed.isNotEmpty) out['vars_after'] = state;
  return out;
}



void _applyOnChange(
  String changed,
  List<WizardVar> vars,
  Map<String, String> state, {
  int depth = 0,
}) {
  if (depth > 16) return;
  final node = vars.where((v) => v.name == changed).firstOrNull;
  final set = (node?.onChange?['#set'] ?? node?.onChange?['set']) as Map<String, dynamic>?;
  if (set == null) return;

  final nodes = {for (final v in vars) v.name: v};
  for (final entry in set.entries) {
    final target = entry.key.startsWith('@') ? entry.key.substring(1) : entry.key;
    final tree = entry.value;
    if (tree is! Map<String, dynamic>) continue;

    final resolve = makeResolver(state, nodes);
    final value = evalIfScalar(tree, resolve);
    if (value == null) continue;


    if (state[target] == value) continue;
    state[target] = value;
    _applyOnChange(target, vars, state, depth: depth + 1);
  }
}

dynamic _deepCopy(dynamic node) => jsonDecode(jsonEncode(node));


bool _jsonEqual(dynamic a, dynamic b) =>
    const DeepCollectionEquality().equals(a, b);









void _runDepsCorpus(Directory root) {
  final bases = root
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.cond.json'))
      .map((f) => f.path.substring(0, f.path.length - '.cond.json'.length))
      .toList()
    ..sort();

  group('contract corpus: cond deps', () {
    for (final base in bases) {
      final name = base.substring(root.path.length + 1);
      test(name, () {
        final cond = jsonDecode(File('$base.cond.json').readAsStringSync());
        final expected = jsonDecode(File('$base.expected.json').readAsStringSync())
            as Map<String, dynamic>;
        final want = ((expected['deps'] as List?) ?? const []).cast<String>();
        expect(condDeps(cond), want, reason: 'deps для ${jsonEncode(cond)}');
      });
    }
  });
}

void main() {
  if (corpusSuiteUnavailable('test/contract/template_contract_test.dart')) return;

  final root = Directory('$kVendorRoot/corpus/template');
  if (!root.existsSync()) {


    return;
  }

  final bases = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.template.json'))
      .map((f) => f.path.substring(0, f.path.length - '.template.json'.length))
      .toList()
    ..sort();

  final depsRoot = Directory('$kVendorRoot/corpus/template/deps');
  if (depsRoot.existsSync()) _runDepsCorpus(depsRoot);

  group('contract corpus: template engine', () {
    for (final base in bases) {
      final name = base.substring(root.path.length + 1);
      test(name, () {
        final c = _loadCase(base);
        final got = _runCase(c);

        final expectedWarnings =
            ((c.expected['warnings'] as List?) ?? const []).cast<String>().toList()
              ..sort();

        expect(
          _jsonEqual(got['config'], c.expected['config']),
          isTrue,
          reason: 'config: получено ${jsonEncode(got['config'])}, '
              'ожидалось ${jsonEncode(c.expected['config'])}',
        );
        expect(got['warnings'], expectedWarnings, reason: 'warnings');
        if (c.changed.isNotEmpty) {
          expect(got['vars_after'], c.expected['vars_after'],
              reason: 'vars_after');
        }
      });
    }
  });
}
