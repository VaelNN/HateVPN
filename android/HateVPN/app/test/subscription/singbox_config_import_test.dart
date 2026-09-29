

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/codec/source_record.dart';
import 'package:lxbox/controllers/subscription_controller.dart';
import 'package:lxbox/models/node_spec.dart';
import 'package:lxbox/models/server_list.dart';
import 'package:lxbox/services/settings_storage.dart';
import 'package:lxbox/services/subscription/http_cache.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

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
  late Directory tempDir;

  const singleOutbound = '{"type":"vless","tag":"solo",'
      '"server":"a.example","server_port":443,"uuid":"u-1"}';

  const wholeConfig = '''
{
  "log": {"level": "info"},
  "dns": {"servers": [{"tag": "g", "address": "8.8.8.8"}]},
  "inbounds": [{"type": "tun", "tag": "tun-in"}],
  "outbounds": [
    {"type": "vless", "tag": "DE", "server": "de.example", "server_port": 443,
     "uuid": "u-de", "detour": "jump"},
    {"type": "trojan", "tag": "NL", "server": "nl.example", "server_port": 443,
     "password": "p-nl"},
    {"type": "shadowsocks", "tag": "jump", "server": "jump.example",
     "server_port": 8388, "method": "aes-256-gcm", "password": "p-j"},
    {"type": "urltest", "tag": "Fastest", "outbounds": ["DE", "NL"]},
    {"type": "direct", "tag": "direct"}
  ],
  "route": {"rules": [{"protocol": "dns", "outbound": "dns-out"}]}
}
''';

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('sb_import_');
    await Directory('${tempDir.path}/docs').create();
    await Directory('${tempDir.path}/support').create();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    SettingsStorage.resetCacheForTesting();
  });

  tearDown(() async {
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } on FileSystemException {

    }
  });

  group('§368 контейнер по числу узлов', () {
    test('одиночный outbound → UserServer (как было)', () async {
      final c = SubscriptionController();
      await c.addFromInput(singleOutbound);
      expect(c.lastError, isNull);
      final entry = c.entries.single;
      expect(entry.list, isA<UserServer>());
      expect(entry.list.nodes, hasLength(1));
    });

    test('полный конфиг → файловая подписка, а не UserServer', () async {
      final c = SubscriptionController();
      await c.addFromInput(wholeConfig);
      expect(c.lastError, isNull);

      final entry = c.entries.single;
      expect(entry.list, isA<SubscriptionServers>());
      final sub = entry.list as SubscriptionServers;

      expect(sub.url, startsWith('file:'));
      expect(sub.updateIntervalHours, -1);
    });

    test('конфиг: узлы, группа и цепочка доехали', () async {
      final c = SubscriptionController();
      await c.addFromInput(wholeConfig);

      final nodes = c.entries.single.list.nodes;

      expect(nodes, hasLength(3));

      final de = nodes.firstWhere((n) => n.label == 'DE');
      expect(de.chained?.server, 'jump.example');

      final group = nodes.firstWhere((n) => n.isGroup);
      expect(group, isA<AutoSelectSpec>());
      expect(group.label, 'Fastest');
    });

    test('массив outbound\'ов → одна запись со всеми узлами', () async {
      final c = SubscriptionController();
      await c.addFromInput('['
          '{"type":"vless","tag":"a","server":"a.example",'
          '"server_port":443,"uuid":"u-a"},'
          '{"type":"vless","tag":"b","server":"b.example",'
          '"server_port":443,"uuid":"u-b"}'
          ']');
      expect(c.lastError, isNull);

      expect(c.entries, hasLength(1));
      expect(c.entries.single.list.nodes, hasLength(2));
    });

    test('не-JSON → ошибка «не распознано», записей нет', () async {
      final c = SubscriptionController();
      await c.addFromInput('это не конфиг');
      expect(c.lastError, isNotNull);
      expect(c.entries, isEmpty);
    });

    test('JSON без пригодных outbound\'ов → своя ошибка, не «не распознано»',
        () async {
      final c = SubscriptionController();
      await c.addFromInput('{"outbounds":[{"type":"direct","tag":"d"}]}');
      expect(c.lastError, isNotNull);
      expect(c.lastError!.renderEn(),
          contains('No valid outbounds'));
      expect(c.entries, isEmpty);
    });
  });

  group('§437 Tailscale в многоузловой вставке', () {
    const tsEndpoint = '{"type":"tailscale","tag":"home-ts",'
        '"auth_key":"tskey-auth-xxx"}';
    const proxy = '{"type":"vless","tag":"DE","server":"de.example",'
        '"server_port":443,"uuid":"u-de"}';
    const proxy2 = '{"type":"trojan","tag":"NL","server":"nl.example",'
        '"server_port":443,"password":"p-nl"}';



    test('endpoint + прокси → два UserServer, секций нет', () async {
      final c = SubscriptionController();
      await c.addFromInput(
          '{"endpoints":[$tsEndpoint],"outbounds":[$proxy],'
          '"route":{"final":"DE"}}');
      expect(c.lastError, isNull);
      expect(c.entries, hasLength(2));

      final tsEntry = c.entries.firstWhere(
          (e) => e.list.nodes.single is TailscaleSpec);
      expect(tsEntry.list, isA<UserServer>());


      final rest = c.entries.firstWhere((e) => e != tsEntry);
      expect(rest.list, isA<UserServer>());



      expect(rest.list.nodes.single.label, '⚡ DE');
      expect(sourceKindOf((rest.list as UserServer).rawBody),
          'singbox_outbound');
    });

    test('endpoint + два прокси → UserServer (ts) + файловая подписка без ts '
        'в кэше', () async {
      final c = SubscriptionController();
      await c.addFromInput(
          '{"endpoints":[$tsEndpoint],"outbounds":[$proxy,$proxy2]}');
      expect(c.lastError, isNull);
      expect(c.entries, hasLength(2));

      final tsList = c.entries
          .map((e) => e.list)
          .whereType<UserServer>()
          .single;
      expect(tsList.nodes.single, isA<TailscaleSpec>());

      final sub = c.entries
          .map((e) => e.list)
          .whereType<SubscriptionServers>()
          .single;
      expect(sub.nodes.map((n) => n.label), ['DE', 'NL']);


      final cached = await HttpCache.loadBody(sub.url);
      expect(cached, isNotNull);
      expect(cached, isNot(contains('tailscale')));
      expect(cached, contains('"DE"'));
      expect(cached, contains('"NL"'));
    });

    test('endpoint + группа: остаток без узлов — не ошибка', () async {
      final c = SubscriptionController();
      await c.addFromInput('{"endpoints":[$tsEndpoint],"outbounds":['
          '{"type":"selector","tag":"sel","outbounds":["home-ts"]}]}');
      expect(c.lastError, isNull);
      final list = c.entries.single.list as UserServer;
      expect(list.nodes.single, isA<TailscaleSpec>());
    });

    test('многоузловой конфиг со ссылками: связка не извлекается', () async {
      final c = SubscriptionController();
      await c.addFromInput('''
{
  "endpoints": [$tsEndpoint],
  "outbounds": [$proxy],
  "dns": {"servers": [
    {"type": "tailscale", "tag": "ts-dns", "endpoint": "home-ts"}
  ], "rules": [{"domain_suffix": [".ts.net"], "server": "ts-dns"}]},
  "route": {"rules": [
    {"ip_cidr": ["100.64.0.0/10"], "outbound": "home-ts"}
  ], "final": "DE"}
}
''');
      expect(c.lastError, isNull);
      final tsList = c.entries
          .map((e) => e.list)
          .whereType<UserServer>()
          .firstWhere((l) => l.nodes.single is TailscaleSpec);
      expect(tsList.nodes.single, isA<TailscaleSpec>());
    });

    test('голое тело → узел без секций', () async {
      final c = SubscriptionController();
      await c.addFromInput(tsEndpoint);
      expect(c.lastError, isNull);
      final list = c.entries.single.list as UserServer;
      expect(list.nodes.single, isA<TailscaleSpec>());
    });

    test('конфиг с одним ts и route → узел без секций', () async {
      final c = SubscriptionController();
      await c.addFromInput('{"endpoints":[$tsEndpoint],'
          '"route":{"rules":[{"domain":["x"],"outbound":"direct"}]}}');
      expect(c.lastError, isNull);
      expect(c.entries.single.list, isA<UserServer>());
    });

    test('папка: голое тело членом → секций нет', () async {
      final c = SubscriptionController();
      await c.addFolder('tailnet');
      expect(await c.addMembersToFolder(0, tsEndpoint), isNull);
      final folder = c.entries.single.list as FolderServers;
      expect(folder.members.single.node, isA<TailscaleSpec>());
    });

    test('не-Tailscale узел секций по умолчанию не получает', () async {
      final c = SubscriptionController();
      await c.addFromInput(singleOutbound);
      expect(c.entries.single.list, isA<UserServer>());
    });
  });
}
