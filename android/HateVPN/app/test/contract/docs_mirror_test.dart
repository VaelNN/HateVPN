import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';















const _docsRoot = '../docs/contract';
const _assetsRoot = 'assets/contract';
















const _awaitingLauncherGendocs = <String>{};

void main() {
  final warningsMd = File('$_docsRoot/warnings.md');
  final readme = File('$_docsRoot/README.md');
  final registry = File('$_assetsRoot/registry/warnings.json');


  final skip = warningsMd.existsSync() && registry.existsSync()
      ? null
      : 'зеркало документации не синхронизировано (tool/sync_contract.sh)';

  group('§460 W2b — зеркало документации контракта', () {
    test('у каждого кода реестра есть якорь в warnings.md', () {
      final codes = ((jsonDecode(registry.readAsStringSync())
              as Map<String, dynamic>)['warnings'] as Map<String, dynamic>)
          .keys
          .toList()
        ..sort();
      expect(codes, isNotEmpty, reason: 'реестр без кодов — так не бывает');





      final text = warningsMd.readAsStringSync();
      final anchors = RegExp(r'<a id="([^"]+)"></a>')
          .allMatches(text)
          .map((m) => m.group(1)!)
          .toSet();

      final missing = codes
          .where((c) =>
              !anchors.contains(c) && !_awaitingLauncherGendocs.contains(c))
          .toList();
      expect(missing, isEmpty,
          reason: 'коды реестра без якоря в docs/contract/warnings.md: '
              '$missing — ссылка «Learn more» по ним уведёт в начало страницы. '
              'Пересоберите зеркало: bash app/tool/sync_contract.sh');



      final stale =
          _awaitingLauncherGendocs.where(anchors.contains).toList()..sort();
      expect(stale, isEmpty,
          reason: 'якорь у этих кодов в зеркале УЖЕ есть — уберите их из '
              '_awaitingLauncherGendocs: $stale');
    });

    test('версия в README зеркала равна assets/contract/VERSION', () {
      final version = File('$_assetsRoot/VERSION').readAsStringSync().trim();
      expect(version, isNotEmpty);
      expect(readme.existsSync(), isTrue,
          reason: 'README зеркала пишет sync_contract.sh — его нет');
      expect(readme.readAsStringSync(), contains('`$version`'),
          reason: 'README зеркала называет не ту версию контракта, что едет в '
              'APK: страницы и реестр разъехались');
    });
  }, skip: skip);
}
