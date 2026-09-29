

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lxbox/controllers/subscription_controller.dart';
import 'package:lxbox/models/server_list.dart';
import 'package:lxbox/services/settings_storage.dart';
import 'package:lxbox/services/subscription/http_cache.dart';
import 'package:lxbox/services/subscription/sources.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../parser/engine_test_setup.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempRoot;
  _FakePathProvider(this.tempRoot);
  @override
  Future<String?> getApplicationSupportPath() async => '$tempRoot/support';
  @override
  Future<String?> getApplicationDocumentsPath() async => '$tempRoot/docs';
}


void main() {


  setUpAll(loadEngineSections);

  late Directory tempDir;

  const bodyA = 'vless://uuid-1@h1.example:443?type=ws&security=tls#A1\n'
      'vless://uuid-2@h2.example:443?type=ws&security=tls#A2\n';
  const bodyB = 'vless://uuid-3@h3.example:443?type=ws&security=tls#B1\n';

  SubscriptionServers sub(String id, String url, {int lastNodeCount = 0}) =>
      SubscriptionServers(
        id: id,
        name: id,
        enabled: true,
        tagPrefix: '',
        detourPolicy: DetourPolicy.defaults,
        url: url,
        lastNodeCount: lastNodeCount,
      );

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('rehydrate_race_');

    await Directory('${tempDir.path}/docs').create();
    await Directory('${tempDir.path}/support').create();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    SettingsStorage.resetCacheForTesting();


    fetchBackoffsForTesting = const [Duration.zero, Duration.zero];
  });

  tearDown(() async {
    fetchBackoffsForTesting = null;


    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } on FileSystemException {

    }
  });

  group('§101 — rehydrationDone', () {
    test('init → rehydrationDone восстанавливает ноды из кеша', () async {
      await SettingsStorage.saveServerLists(
          [sub('s1', 'http://x/a', lastNodeCount: 2)]);
      await HttpCache.save('http://x/a', bodyA, const {});

      final c = SubscriptionController();
      await c.init();
      await c.rehydrationDone;

      expect(c.entries.single.list.nodes, hasLength(2));
      expect(c.entries.single.status?.renderEn(), '2 nodes (cached)');
    });

    test('кеш парсится в 0 нод → ноды пусты, completer завершён', () async {
      await SettingsStorage.saveServerLists(
          [sub('s1', 'http://x/a', lastNodeCount: 5)]);
      await HttpCache.save('http://x/a', '<html>blocked</html>', const {});

      final c = SubscriptionController();
      await c.init();
      await c.rehydrationDone;

      expect(c.entries.single.list.nodes, isEmpty);
    });

    test('без подписок rehydrationDone завершается сразу', () async {
      final c = SubscriptionController();
      await c.init();
      await c.rehydrationDone.timeout(const Duration(seconds: 5));
    });
  });

  group('§101 — reorder во время rehydrate (by-ref guard)', () {
    test('moveEntry в полёте не подменяет list чужой entry', () async {
      await SettingsStorage.saveServerLists([
        sub('sa', 'http://x/a'),
        sub('sb', 'http://x/b'),
      ]);
      await HttpCache.save('http://x/a', bodyA, const {});
      await HttpCache.save('http://x/b', bodyB, const {});

      final c = SubscriptionController();
      await c.init();


      await c.moveEntry(1, 0);
      await c.rehydrationDone;

      expect(c.entries, hasLength(2));
      expect(c.entries.map((e) => e.id).toSet(), {'sa', 'sb'});
      final byUrl = {for (final e in c.entries) e.url: e.list};
      expect(byUrl['http://x/a']!.nodes.map((n) => n.label), ['A1', 'A2']);
      expect(byUrl['http://x/b']!.nodes.map((n) => n.label), ['B1']);
    });
  });

  group('§101 — пустой fetch не затирает рабочее состояние', () {
    test('200 с мусорным телом → nodes/кеш/lastNodeCount сохранены, failed',
        () async {
      await SettingsStorage.saveServerLists(
          [sub('s1', 'http://x/a', lastNodeCount: 2)]);
      await HttpCache.save('http://x/a', bodyA, const {});

      final c = SubscriptionController();
      await c.init();
      await c.rehydrationDone;
      expect(c.entries.single.list.nodes, hasLength(2));

      c.httpClientForTesting =
          MockClient((req) async => http.Response('<html>stub</html>', 200));
      await c.refreshEntry(c.entries.single);

      final list = c.entries.single.list as SubscriptionServers;
      expect(list.nodes, hasLength(2), reason: 'in-memory ноды сохранены');
      expect(list.lastNodeCount, 2);
      expect(list.lastUpdateStatus, UpdateStatus.failed);
      expect(list.consecutiveFails, 1);
      expect(c.entries.single.status?.renderEn(),
          contains('update failed: 0 parsed'));
      expect(await HttpCache.loadBody('http://x/a'), bodyA,
          reason: 'кеш на диске не перезаписан мусором');
    });

    test('HTTP 500 → старое поведение: nodes сохранены, failed (regression)',
        () async {
      await SettingsStorage.saveServerLists(
          [sub('s1', 'http://x/a', lastNodeCount: 2)]);
      await HttpCache.save('http://x/a', bodyA, const {});

      final c = SubscriptionController();
      await c.init();
      await c.rehydrationDone;

      c.httpClientForTesting =
          MockClient((req) async => http.Response('boom', 500));
      await c.refreshEntry(c.entries.single);

      final list = c.entries.single.list as SubscriptionServers;
      expect(list.nodes, hasLength(2));
      expect(list.lastUpdateStatus, UpdateStatus.failed);
      expect(list.consecutiveFails, 1);
      expect(await HttpCache.loadBody('http://x/a'), bodyA);
    });

    test('успешный fetch с нодами обновляет кеш и состояние', () async {
      await SettingsStorage.saveServerLists([sub('s1', 'http://x/a')]);
      await HttpCache.save('http://x/a', bodyA, const {});

      final c = SubscriptionController();
      await c.init();
      await c.rehydrationDone;

      c.httpClientForTesting =
          MockClient((req) async => http.Response(bodyB, 200));
      await c.refreshEntry(c.entries.single);


      await c.lastCacheSaveForTesting;

      final list = c.entries.single.list as SubscriptionServers;
      expect(list.nodes.map((n) => n.label), ['B1']);
      expect(list.lastUpdateStatus, UpdateStatus.ok);
      expect(list.consecutiveFails, 0);
      expect(await HttpCache.loadBody('http://x/a'), bodyB);
    });
  });
}
