import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lxbox/services/settings_storage.dart';






void main() {
  late Directory tmp;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  String mainPath() => '${tmp.path}/lxbox_settings.json';
  String bakPath() => '${tmp.path}/lxbox_settings.json.bak';


  String tmpPath() => '${tmp.path}/lxbox_settings.json.tmp';
  int orphanTmpCount() => tmp
      .listSync()
      .whereType<File>()
      .where((f) {
        final name = f.uri.pathSegments.last;
        return name.startsWith('lxbox_settings.json.') && name.endsWith('.tmp');
      })
      .length;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = await Directory.systemTemp.createTemp('lxbox_settings_storage_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory' ||
          call.method == 'getApplicationDocumentsPath') {
        return tmp.path;
      }
      return null;
    });
    SettingsStorage.resetCacheForTesting();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);





    try {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    } on FileSystemException {

    }
  });

  group('§072 — round-trip', () {
    test('setVar + read back в пределах сессии', () async {
      await SettingsStorage.setVar('alpha', '1');
      expect(await SettingsStorage.getVar('alpha', 'def'), '1');
    });

    test('setVar + resetCacheForTesting + read back с диска', () async {
      await SettingsStorage.setVar('alpha', '1');
      SettingsStorage.resetCacheForTesting();
      expect(await SettingsStorage.getVar('alpha', 'def'), '1');
    });

    test('§044 profiler retention — default + round-trip + персист', () async {

      expect(await SettingsStorage.getProfilerRetentionSec(),
          SettingsStorage.profilerRetentionDefaultSec);
      await SettingsStorage.setProfilerRetentionSec(3600);
      expect(await SettingsStorage.getProfilerRetentionSec(), 3600);

      SettingsStorage.resetCacheForTesting();
      expect(await SettingsStorage.getProfilerRetentionSec(), 3600);
    });
  });

  group('§072 — corruption recovery', () {
    test('main битый, .bak валидный → recovery из .bak', () async {

      await SettingsStorage.setVar('alpha', '1');
      await SettingsStorage.setVar('alpha', '2');

      await File(mainPath()).writeAsString('{this is not valid json');

      expect(File(bakPath()).existsSync(), isTrue,
          reason: '.bak должен быть создан вторым save');

      SettingsStorage.resetCacheForTesting();
      expect(await SettingsStorage.getVar('alpha', 'def'), isNotEmpty,
          reason: 'данные восстанавливаются из .bak');

      expect(SettingsStorage.mainIsCorruptedForTesting, isFalse);
    });

    test('main битый, .bak отсутствует → return {}, sticky flag', () async {
      await File(mainPath()).writeAsString('not a json');
      expect(File(bakPath()).existsSync(), isFalse);


      expect(await SettingsStorage.getVar('alpha', 'default'), 'default');
      expect(SettingsStorage.mainIsCorruptedForTesting, isTrue);

      expect(File(mainPath()).readAsStringSync(), 'not a json');
    });

    test('main = 0 bytes (truncate) → не считается valid empty settings',
        () async {

      await SettingsStorage.setVar('alpha', '1');
      await SettingsStorage.setVar('alpha', '2');

      await File(mainPath()).writeAsString('');

      SettingsStorage.resetCacheForTesting();

      expect(await SettingsStorage.getVar('alpha', 'def'), isNotEmpty);
      expect(SettingsStorage.mainIsCorruptedForTesting, isFalse);
    });

    test('main 0 bytes + .bak нет → drop с corruption flag', () async {
      await File(mainPath()).writeAsString('');
      expect(File(bakPath()).existsSync(), isFalse);
      expect(await SettingsStorage.getVar('any', 'def'), 'def');
      expect(SettingsStorage.mainIsCorruptedForTesting, isTrue);
    });
  });

  group('§072 — atomic save artifacts', () {
    test('после успешного _save() .tmp не остаётся', () async {
      await SettingsStorage.setVar('alpha', '1');
      expect(File(tmpPath()).existsSync(), isFalse,
          reason: 'rename() консумирует .tmp');
    });

    test('после drop + setVar — main перезаписан, sticky flag сброшен',
        () async {



      await File(mainPath()).writeAsString('garbage');
      expect(await SettingsStorage.getVar('any', 'def'), 'def');
      expect(SettingsStorage.mainIsCorruptedForTesting, isTrue);

      await SettingsStorage.setVar('new', 'x');
      expect(SettingsStorage.mainIsCorruptedForTesting, isFalse,
          reason: 'atomic save сбрасывает flag');

      SettingsStorage.resetCacheForTesting();
      expect(await SettingsStorage.getVar('new', 'def'), 'x');
    });

    test('stale .tmp от прошлого crashed save → удаляется в _load()',
        () async {



      await File(mainPath()).writeAsString(jsonEncode({'vars': {'a': '1'}}));
      await File(tmpPath()).writeAsString('{"vars":{"a":"PARTIAL');
      await File('${tmp.path}/lxbox_settings.json.7.tmp')
          .writeAsString('{"vars":{"a":"PARTIAL2');

      SettingsStorage.resetCacheForTesting();
      expect(await SettingsStorage.getVar('a', 'def'), '1',
          reason: 'main валидный → читаем оттуда');

      expect(orphanTmpCount(), 0,
          reason: '.tmp от прошлых crashed save удалены');
    });

    test('§141 P1.5 — конкурентные _save() не оставляют сирот и не бросают',
        () async {




      await SettingsStorage.setVar('warm', '0');





      await Future.wait([
        SettingsStorage.setVar('a', '1'),
        SettingsStorage.setVar('b', '2'),
        SettingsStorage.setVar('c', '3'),
      ]);

      SettingsStorage.resetCacheForTesting();
      expect(await SettingsStorage.getVar('a', 'def'), '1');
      expect(await SettingsStorage.getVar('b', 'def'), '2');
      expect(await SettingsStorage.getVar('c', 'def'), '3');

      expect(orphanTmpCount(), 0, reason: 'нет residual .tmp после гонки');
    });

    test('.bak создаётся только из валидного main', () async {

      await SettingsStorage.setVar('alpha', '1');
      expect(File(bakPath()).existsSync(), isFalse,
          reason: 'до первого save main отсутствовал → .bak не создаётся');



      await SettingsStorage.setVar('alpha', '2');
      expect(File(bakPath()).existsSync(), isTrue);
      final bakContent =
          jsonDecode(await File(bakPath()).readAsString()) as Map;
      expect(((bakContent['vars'] as Map)['alpha']), '1',
          reason: '.bak = состояние main до второго save');
    });

    test('.bak не пишется если main битый', () async {

      await File(mainPath()).writeAsString('garbage');
      await File(bakPath())
          .writeAsString(jsonEncode({'vars': {'old': 'value'}}));

      SettingsStorage.resetCacheForTesting();

      expect(await SettingsStorage.getVar('old', 'def'), 'value');






      await SettingsStorage.setVar('new', 'x');





      final bakAfter =
          jsonDecode(await File(bakPath()).readAsString()) as Map;
      expect((bakAfter['vars'] as Map)['old'], 'value',
          reason: '.bak остался с предыдущим валидным state');
    });
  });

  group('§159 — legacy proxy_sources больше не мигрирует', () {
    test('proxy_sources игнорируется (миграция удалена)', () async {


      final legacy = {
        'proxy_sources': [
          {
            'url': 'https://example.com/sub.txt',
            'enabled': true,
            'name': 'Test sub',
          },
        ],
      };
      await File(mainPath()).writeAsString(jsonEncode(legacy));

      SettingsStorage.resetCacheForTesting();
      final lists = await SettingsStorage.getServerLists();
      expect(lists, isEmpty,
          reason: 'миграция proxy_sources удалена (§159) — legacy игнорируется');
    });
  });
}
