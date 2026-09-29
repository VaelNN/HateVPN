import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import '../contract_paths.dart';
import 'package:lxbox/models/custom_rule.dart';
import 'package:lxbox/models/parser_config.dart';
import 'package:lxbox/services/builder/if_engine.dart';
import 'package:lxbox/services/builder/preset_expand.dart';

















class _ForEachCase {
  _ForEachCase({
    required this.name,
    required this.presetJson,
    required this.nodes,
    required this.varsValues,
    required this.expected,
  });

  final String name;
  final Map<String, dynamic> presetJson;
  final List<PresetNode> nodes;
  final Map<String, String> varsValues;
  final Map<String, dynamic> expected;
}

_ForEachCase _loadCase(String base) {
  final preset = jsonDecode(File('$base.preset.json').readAsStringSync())
      as Map<String, dynamic>;
  final varsRaw = jsonDecode(File('$base.vars.json').readAsStringSync())
      as Map<String, dynamic>;
  final expected = jsonDecode(File('$base.expected.json').readAsStringSync())
      as Map<String, dynamic>;

  final presetJson = Map<String, dynamic>.from(
      preset['preset'] as Map<String, dynamic>? ?? const {});

  final nodes = <PresetNode>[
    for (final n in (preset['nodes'] as List? ?? const []))
      if ((n as Map<String, dynamic>)['enabled'] != false &&
          n['in_config'] != false)
        PresetNode(
          tag: n['tag'] as String,
          body: Map<String, dynamic>.from(n['body'] as Map),
          skipPresets: n['skip_presets'] as bool? ?? false,
        ),
  ];

  return _ForEachCase(
    name: base,
    presetJson: presetJson,
    nodes: nodes,
    varsValues: {
      for (final e in varsRaw.entries) e.key: e.value as String,
    },
    expected: expected,
  );
}








bool _rejectedOnLoad(Map<String, dynamic> presetJson) {
  final forEachRaw = presetJson['for_each'];
  if (forEachRaw == null) return false;
  return PresetForEach.fromJson(forEachRaw) == null;
}

Map<String, dynamic> _runCase(_ForEachCase c) {
  final wrapped = <String, dynamic>{
    'preset_id': 'corpus-for-each',
    'ui': {'label': 'corpus'},
    ...c.presetJson,
  };

  final rejected = _rejectedOnLoad(c.presetJson);
  if (rejected) {
    return {
      'rules': const [],
      'dns_servers': const [],
      'dns_rules': const [],
      'warnings': const <String>[],
    };
  }

  final preset = SelectableRule.fromJson(wrapped);
  final rule = CustomRulePreset(
    name: 'corpus',
    presetId: 'corpus-for-each',
    varsValues: c.varsValues,
  );

  final warns = TemplateWarnings();
  final fragments = collectTemplateWarnings(
    warns,
    () => expandPreset(rule, preset, nodes: c.nodes),
  );

  return {
    'rules': fragments.routingRules,
    'dns_servers': fragments.dnsServers,
    'dns_rules': fragments.dnsRules,
    'warnings': ({...fragments.warnings, ...warns.codes}.toList()..sort()),
  };
}

bool _jsonEqual(dynamic a, dynamic b) =>
    const DeepCollectionEquality().equals(a, b);

void main() {
  if (corpusSuiteUnavailable('test/contract/template_for_each_corpus_test.dart')) {
    return;
  }

  final root = Directory('$kVendorRoot/corpus/template/for_each');
  if (!root.existsSync()) return;

  final bases = root
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.preset.json'))
      .map((f) => f.path.substring(0, f.path.length - '.preset.json'.length))
      .toList()
    ..sort();

  group('contract corpus: template for_each', () {
    for (final base in bases) {
      final name = base.substring(root.path.length + 1);
      test(name, () {
        final c = _loadCase(base);
        final wantLoad = c.expected['load'] as String?;
        final rejected = _rejectedOnLoad(c.presetJson);

        if (wantLoad == 'reject') {
          expect(rejected, isTrue,
              reason: 'кейс объявлен как load: reject, но for_each валиден');
        } else {
          expect(rejected, isFalse,
              reason: 'for_each отвергнут, а кейс этого не ожидает');
        }

        final got = _runCase(c);

        expect(
          _jsonEqual(got['rules'], c.expected['rules']),
          isTrue,
          reason: 'rules: получено ${jsonEncode(got['rules'])}, '
              'ожидалось ${jsonEncode(c.expected['rules'])}',
        );
        expect(
          _jsonEqual(got['dns_servers'], c.expected['dns_servers']),
          isTrue,
          reason: 'dns_servers: получено ${jsonEncode(got['dns_servers'])}, '
              'ожидалось ${jsonEncode(c.expected['dns_servers'])}',
        );
        expect(
          _jsonEqual(got['dns_rules'], c.expected['dns_rules']),
          isTrue,
          reason: 'dns_rules: получено ${jsonEncode(got['dns_rules'])}, '
              'ожидалось ${jsonEncode(c.expected['dns_rules'])}',
        );

        final expectedWarnings =
            ((c.expected['warnings'] as List?) ?? const [])
                .cast<String>()
                .toList()
              ..sort();
        expect(got['warnings'], expectedWarnings, reason: 'warnings');
      });
    }
  });
}
