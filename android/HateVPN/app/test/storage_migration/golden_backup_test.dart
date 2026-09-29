import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'golden_harness.dart';

import '../parser/engine_test_setup.dart';



















void main() {


  setUpAll(loadEngineSections);

  for (final name in kStorageFixtures) {
    test('$name: экспорт LX Backup и круг экспорт → импорт → конфиг', () async {
      final source = await StorageSandbox.create();
      addTearDown(source.dispose);
      await source.seed(name);
      final exported = await exportGoldenLxBackup();
      expectGolden('$name.backup.json', _withSplitIdsMasked(exported.json));

      final target = await StorageSandbox.create();
      addTearDown(target.dispose);
      await target.seed(name, storage: false);
      final parsed = await importGoldenLxBackup(exported.json);
      final rebuilt = await buildGoldenConfig(target);

      final golden = goldenFile('$name.config.json');
      final expectedConfig = golden.existsSync()
          ? jsonDecode(golden.readAsStringSync())
          : null;
      expect(expectedConfig, isNotNull,
          reason: 'нет ${golden.path}: сначала golden_config_test');

      final roundtrip = {
        'export_warnings': [for (final w in exported.warnings) warningLine(w)],
        'import_warnings': [for (final w in parsed.warnings) warningLine(w)],
        'config_diff': jsonDiff(expectedConfig, rebuilt.config),
      };
      expectGolden('$name.backup_roundtrip.json', prettyJson(roundtrip));
    });
  }
}


const _kSplitPartId = '<split-part-id>';




String _withSplitIdsMasked(String json) {
  final doc = jsonDecode(json) as Map<String, dynamic>;
  final rules = doc['rules'];
  if (rules is List) {
    final split = RegExp(r' #\d+$');
    for (final r in rules) {
      if (r is Map &&
          r['id'] is String &&
          r['name'] is String &&
          split.hasMatch(r['name'] as String)) {
        r['id'] = _kSplitPartId;
      }
    }
  }
  return prettyJson(doc);
}
