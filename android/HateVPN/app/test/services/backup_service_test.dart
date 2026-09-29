import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lxbox/services/backup_service.dart';
import 'package:lxbox/services/settings_storage.dart';



void main() {
  late Directory tmp;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = await Directory.systemTemp.createTemp('lxbox_backup_test_');
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
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });



  Map<String, dynamic> sampleSnapshot() => {
        'storage_version': 1,
        'vars': {
          'log_level': 'info',
          'auto_update_subs': 'true',
          'auto_record_wifi_history': 'true',
          'wifi_history':
              '[{"ssid":"Home","bssid":"aa:bb:cc:dd:ee:ff","last_seen":"2026-05-10T12:00:00Z"}]',
          'debug_enabled': 'true',
          'debug_token': 'secret-token-xyz',
          'debug_port': '9269',
        },
        'rules': [
          {
            'kind': 'inline',
            'id': 'rule-1',
            'name': 'Ru Apps',
            'enabled': true,
            'body': {
              'package_name': ['ru.tinkoff.investing', 'com.vkontakte.android'],
              'outbound': 'vpn-2',
            },
          },
        ],
        'tun_apps': {
          'mode': 'allow',
          'packages': ['com.example.app'],
        },
        'sources': [
          {
            'kind': 'subscription',
            'id': 'src-1',
            'name': 'My subs',
            'enabled': true,
            'url': 'https://example.com/sub',
            'update': {'interval_hours': 24},
          },
        ],
        'route_final': 'vpn-1',

        'directions': [
          {'tag': 'vpn-1', 'label': 'Main', 'enabled': true},
          {'tag': 'vpn-2', 'label': 'Backup', 'enabled': true},
        ],
        'directions_migrated': true,
        'enabled_groups': ['group-a'],
        'dns': {
          'servers': [
            {
              'kind': 'user',
              'tag': 'cloudflare',
              'enabled': true,
              'body': {'type': 'udp', 'server': '1.1.1.1'},
            },
          ],
        },
      };

  Future<void> seedStorage(Map<String, dynamic> snapshot) async {
    await SettingsStorage.replaceRaw(snapshot);
  }

  test('exportRaw returns deep copy of full storage', () async {
    final snap = sampleSnapshot();
    await seedStorage(snap);
    final raw = await SettingsStorage.exportRaw();
    expect(raw['vars'], isA<Map<String, dynamic>>());
    expect((raw['rules'] as List).length, 1);

    raw['vars']['log_level'] = 'debug';
    final fresh = await SettingsStorage.exportRaw();
    expect(fresh['vars']['log_level'], 'info');
  });

  test('replaceRaw with merge=false overwrites everything', () async {
    await seedStorage(sampleSnapshot());
    await SettingsStorage.replaceRaw({
      'vars': {'log_level': 'warn'},
    });
    expect(await SettingsStorage.getVar('log_level', ''), 'warn');
    final cr = await SettingsStorage.getCustomRules();
    expect(cr, isEmpty);
  });



  test('replaceRaw merge=false keeps device Debug API keys absent in snapshot',
      () async {
    await seedStorage(sampleSnapshot());
    await SettingsStorage.replaceRaw({
      'vars': {'log_level': 'warn'},
    });
    expect(await SettingsStorage.getVar('log_level', ''), 'warn');
    expect(await SettingsStorage.getVar('debug_enabled', ''), 'true');
    expect(await SettingsStorage.getVar('debug_token', ''), 'secret-token-xyz');
    expect(await SettingsStorage.getVar('debug_port', ''), '9269');
    expect(await SettingsStorage.getVar('auto_update_subs', ''), '',
        reason: 'остальные vars заменены целиком, как и раньше');
  });

  test('replaceRaw merge=false: Debug API keys from snapshot win', () async {
    await seedStorage(sampleSnapshot());
    await SettingsStorage.replaceRaw({
      'vars': {'debug_port': '8642', 'debug_enabled': 'false'},
    });
    expect(await SettingsStorage.getVar('debug_port', ''), '8642');
    expect(await SettingsStorage.getVar('debug_enabled', ''), 'false');
    expect(await SettingsStorage.getVar('debug_token', ''), 'secret-token-xyz',
        reason: 'отсутствующий в файле ключ переносится');
  });




  test('replaceRaw merge=false keeps startup prompt flags', () async {
    await seedStorage(sampleSnapshot());
    for (final k in SettingsStorage.startupPromptVarKeys) {
      await SettingsStorage.setVar(k, '1');
    }
    await SettingsStorage.replaceRaw({
      'vars': {
        'log_level': 'warn',
        SettingsStorage.addTilePromptVar: '0',
        SettingsStorage.notificationPromptVar: '0',
      },
    });
    expect(await SettingsStorage.getVar(SettingsStorage.batteryPromptVar, ''),
        '1');
    expect(await SettingsStorage.getVar(SettingsStorage.updateCheckPromptVar, ''),
        '1');
    expect(await SettingsStorage.getVar(SettingsStorage.addTilePromptVar, ''),
        '1', reason: 'wizard_* из файла не импортируется — остаётся флаг устройства');
    expect(
        await SettingsStorage.getVar(SettingsStorage.notificationPromptVar, ''),
        '0',
        reason: 'ключ из allowlist, который в файле есть, побеждает');
  });

  test('replaceRaw with merge=true preserves untouched keys', () async {
    await seedStorage(sampleSnapshot());
    await SettingsStorage.replaceRaw(
      {
        'vars': {'log_level': 'warn'},
      },
      merge: true,
    );
    expect(await SettingsStorage.getVar('log_level', ''), 'warn');
    expect(await SettingsStorage.getVar('auto_update_subs', ''), 'true');
    final cr = await SettingsStorage.getCustomRules();
    expect(cr.length, 1, reason: 'custom_rules must be preserved on merge');
  });

  group('BackupService.buildExport', () {
    test('full export contains storage + metadata, no vpn_settings without toggle',
        () async {
      await seedStorage(sampleSnapshot());
      final svc = const BackupService();
      final json = await svc.buildExport(include: {
        BackupCategory.serverLists,
        BackupCategory.routing,
        BackupCategory.appSettings,
        BackupCategory.debugConfig,
      });
      final parsed = jsonDecode(json) as Map<String, dynamic>;
      expect(parsed['app'], 'lxbox');
      expect(parsed['kind'], 'backup');
      expect(parsed['created_at'], isA<String>());
      expect(parsed.containsKey('version'), isFalse,
          reason: 'new format does not use schema version');
      expect(parsed['storage'], isA<Map>());
      expect(parsed.containsKey('vpn_settings'), isFalse);
      final st = parsed['storage'] as Map<String, dynamic>;
      expect(st['rules'], isA<List>());
      expect(st['storage_version'], 1);
      expect(st['tun_apps'], isA<Map>());
      expect(st['vars']['debug_token'], 'secret-token-xyz');
    });

    test('without debugConfig — debug-keys are stripped from vars', () async {
      await seedStorage(sampleSnapshot());
      final svc = const BackupService();
      final json = await svc.buildExport(include: {
        BackupCategory.serverLists,
        BackupCategory.routing,
        BackupCategory.appSettings,
      });
      final parsed = jsonDecode(json) as Map<String, dynamic>;
      final vars = (parsed['storage'] as Map<String, dynamic>)['vars']
          as Map<String, dynamic>;
      expect(vars.containsKey('debug_token'), isFalse);
      expect(vars.containsKey('debug_port'), isFalse);
      expect(vars.containsKey('debug_enabled'), isFalse);
      expect(vars['log_level'], 'info');
    });

    test('only debugConfig — keeps only debug-keys', () async {
      await seedStorage(sampleSnapshot());
      final svc = const BackupService();
      final json =
          await svc.buildExport(include: {BackupCategory.debugConfig});
      final parsed = jsonDecode(json) as Map<String, dynamic>;
      final vars = (parsed['storage'] as Map<String, dynamic>)['vars']
          as Map<String, dynamic>;
      expect(vars.keys.toSet(),
          {'debug_enabled', 'debug_token', 'debug_port'});
      expect((parsed['storage'] as Map).containsKey('rules'), isFalse);
      expect((parsed['storage'] as Map).containsKey('sources'), isFalse);
      expect((parsed['storage'] as Map)['storage_version'], 1,
          reason: 'признак формы едет при любом наборе категорий');
    });

    test('only routing — top-level routing keys + no vars', () async {
      await seedStorage(sampleSnapshot());
      final svc = const BackupService();
      final json =
          await svc.buildExport(include: {BackupCategory.routing});
      final parsed = jsonDecode(json) as Map<String, dynamic>;
      final st = parsed['storage'] as Map<String, dynamic>;
      expect(st.containsKey('rules'), isTrue);
      expect(st.containsKey('tun_apps'), isTrue);
      expect(st.containsKey('route_final'), isTrue);
      expect(st.containsKey('enabled_groups'), isTrue);
      expect(st.containsKey('dns'), isTrue);

      expect((st['sources'] as List? ?? const []), isEmpty);
      expect(st.containsKey('vars'), isFalse);
    });

    test('§221 — ключи directions + directions_migrated экспортируются в routing',
        () async {
      await seedStorage(sampleSnapshot());
      final svc = const BackupService();
      final json = await svc.buildExport(include: {BackupCategory.routing});
      final st = (jsonDecode(json) as Map<String, dynamic>)['storage']
          as Map<String, dynamic>;


      expect(st.containsKey('directions'), isTrue,
          reason: 'directions обязаны попадать в backup (§125 модель роутинга)');
      expect((st['directions'] as List), hasLength(2));
      expect(st.containsKey('directions_migrated'), isTrue,
          reason: 'guard миграции — иначе миграция пере-сработает поверх restore');

      expect(st.containsKey('channels'), isFalse);
      expect(st.containsKey('channels_migrated'), isFalse);
    });




    test('§221 — allowlist ⊆ export (все категории)', () async {

      final snap = <String, dynamic>{};
      for (final k in SettingsStorage.allowedTopLevelKeys) {
        snap[k] = switch (k) {
          'vars' => {'log_level': 'info'},
          'storage_version' => 1,
          'sources' => [
              {'kind': 'subscription', 'id': 's', 'name': 'n', 'url': 'http://x'},
              {'kind': 'chain', 'tag': 'c', 'hops': []},
            ],
          'dns' || 'tun_apps' || 'vpn_mode' || 'ping_options' ||
          'warp_account' || 'masque_account' =>
            {'_probe': 1},
          'directions' || 'rules' || 'node_manual_order' || 'enabled_groups' =>
            ['_probe'],
          'directions_migrated' || 'presets_migrated' ||
          'interrupt_connections_on_switch' =>
            true,
          _ => '_probe',
        };
      }
      await seedStorage(snap);
      final svc = const BackupService();
      final json = await svc.buildExport(include: {
        BackupCategory.serverLists,
        BackupCategory.routing,
        BackupCategory.appSettings,
        BackupCategory.debugConfig,
        BackupCategory.vpnSettings,
      });
      final st = (jsonDecode(json) as Map<String, dynamic>)['storage']
          as Map<String, dynamic>;



      final missing = SettingsStorage.allowedTopLevelKeys
          .where((k) => !st.containsKey(k))
          .toList();
      for (final k in const ['channels', 'channels_migrated']) {
        expect(st.containsKey(k), isFalse,
            reason: 'легаси-ключ $k не должен попадать в новый архив');
      }
      expect(missing, isEmpty,
          reason: 'ключи в allowlist restore, но НЕ в export → потеря при '
              'backup. Добавь в _topLevelRoutingKeys/_topLevelAppKeys '
              '(backup_service.dart): $missing');
    });




    test('§349 — auto_ping_on_start ∈ appFeatureFlagVars allowlist', () {
      expect(
          SettingsStorage.allowedVarKeys(const [])
              .contains('auto_ping_on_start'),
          isTrue,
          reason: 'настройка обязана переживать restore (§221-симметрия)');
    });



    test('§279 — app_language ∈ appFeatureFlagVars allowlist', () {
      expect(SettingsStorage.allowedVarKeys(const []).contains('app_language'),
          isTrue,
          reason: 'app_language обязан переживать restore (§221-симметрия: '
              'export vars нефильтрован, import — по allowlist)');
    });





    test('§279 — app_language ∉ NativePrefsKeys.all (derived cache)', () {
      expect(NativePrefsKeys.all.contains('app_language'), isFalse);
    });


    test('§279 — app_language переживает export→import round-trip', () async {
      await seedStorage({
        'vars': {'app_language': 'ru'},
      });
      final exported = await SettingsStorage.exportRaw();
      SettingsStorage.resetCacheForTesting();
      await SettingsStorage.replaceRaw(exported);
      expect(await SettingsStorage.getAppLanguage(), 'ru');
    });
  });

  group('BackupService.parseImport', () {
    test('rejects non-JSON', () async {
      final svc = const BackupService();
      await expectLater(svc.parseImport('not json'),
          throwsA(isA<FormatException>()));
    });

    test('rejects file without app/kind markers', () async {
      final svc = const BackupService();
      await expectLater(
          svc.parseImport(jsonEncode({'storage': {}})),
          throwsA(isA<FormatException>()));
    });

    test('rejects legacy format (no storage key)', () async {
      final svc = const BackupService();
      final legacy = {
        'app': 'lxbox',
        'kind': 'backup',
        'version': 1,
        'vars': {'log_level': 'info'},
      };
      await expectLater(
          svc.parseImport(jsonEncode(legacy)),
          throwsA(isA<FormatException>().having(
              (e) => e.message, 'message', contains('Unsupported'))));
    });

    test('parses minimal valid backup', () async {
      final svc = const BackupService();
      final raw = jsonEncode({
        'app': 'lxbox',
        'kind': 'backup',
        'created_at': '2026-05-10T12:00:00Z',
        'storage': {
          'vars': {'log_level': 'debug'},
        },
      });
      final c = await svc.parseImport(raw);
      expect(c.storage, isNotNull);
      expect(c.vpnSettings, isNull);
      expect(c.createdAt?.year, 2026);
    });
  });

  test('round-trip: export → reset → import → bytewise equal', () async {
    final original = sampleSnapshot();
    await seedStorage(original);
    final svc = const BackupService();
    final exported = await svc.buildExport(include: {
      BackupCategory.serverLists,
      BackupCategory.routing,
      BackupCategory.appSettings,
      BackupCategory.debugConfig,
    });


    await SettingsStorage.replaceRaw({});
    expect(await SettingsStorage.getCustomRules(), isEmpty);


    final contents = await svc.parseImport(exported);
    final apply = await svc.applyImport(
      contents,
      merge: false,
      include: {
        BackupCategory.serverLists,
        BackupCategory.routing,
        BackupCategory.appSettings,
        BackupCategory.debugConfig,
      },
    );
    expect(apply.errors, isEmpty);
    expect(apply.serverListsApplied, 1);


    final restored = await SettingsStorage.exportRaw();
    expect(restored['rules'], original['rules']);
    expect(restored['tun_apps'], original['tun_apps']);
    expect(restored['route_final'], original['route_final']);
    expect(restored['enabled_groups'], original['enabled_groups']);
    expect(restored['dns'], original['dns']);
    expect(restored['storage_version'], 1);
    expect((restored['vars'] as Map)['log_level'], 'info');
    expect((restored['vars'] as Map)['debug_token'], 'secret-token-xyz');
    expect((restored['vars'] as Map)['wifi_history'],
        original['vars']['wifi_history']);
    expect(restored['sources'], original['sources']);
  });

  test('§248 — detour-роль Направления переживает backup round-trip', () async {



    await seedStorage({
      'directions': [
        {'tag': 'vpn-1', 'label': 'Main', 'enabled': true},
        {'tag': 'vpn-2', 'label': 'Relay', 'enabled': true, 'detour': true},
      ],
      'directions_migrated': true,
    });
    final svc = const BackupService();
    final exported = await svc.buildExport(include: {BackupCategory.routing});

    final st = (jsonDecode(exported) as Map<String, dynamic>)['storage']
        as Map<String, dynamic>;
    expect(((st['directions'] as List)[1] as Map)['detour'], isTrue);


    await SettingsStorage.replaceRaw({});
    final contents = await svc.parseImport(exported);
    final apply = await svc.applyImport(contents,
        merge: false, include: {BackupCategory.routing});
    expect(apply.errors, isEmpty);

    final restored = await SettingsStorage.getDirections();
    final vpn2 = restored.firstWhere((c) => c.tag == 'vpn-2');
    expect(vpn2.isDetour, isTrue,
        reason: 'detour-роль не должна теряться при restore');
    expect(restored.firstWhere((c) => c.tag == 'vpn-1').isDetour, isFalse);
  });

  test('§274 — detour+include_block переживают round-trip оба', () async {



    await seedStorage({
      'directions': [
        {'tag': 'vpn-1', 'label': 'Main', 'enabled': true},
        {
          'tag': 'vpn-2',
          'label': 'Relay',
          'enabled': true,
          'detour': true,
          'include_block': true,
        },
      ],
      'directions_migrated': true,
    });
    final svc = const BackupService();
    final exported = await svc.buildExport(include: {BackupCategory.routing});

    await SettingsStorage.replaceRaw({});
    final contents = await svc.parseImport(exported);
    final apply = await svc.applyImport(contents,
        merge: false, include: {BackupCategory.routing});
    expect(apply.errors, isEmpty);

    final restored = await SettingsStorage.getDirections();
    final vpn2 = restored.firstWhere((c) => c.tag == 'vpn-2');
    expect(vpn2.isDetour, isTrue);
    expect(vpn2.includeBlock, isTrue,
        reason: 'include_block у detour-Направления не должен коэрситься (§274)');
  });

  group('§159 — allowlist (default-deny) на импорте', () {
    test('replaceRaw отбрасывает чужеродный top-level ключ', () async {
      final dropped = await SettingsStorage.replaceRaw({
        'storage_version': 1,
        'vars': {'log_level': 'info'},
        'rules': [],
        'totally_random_field_12345': {'nested': 'garbage'},
        'another_alien_key': 'x',
      });
      expect(dropped, containsAll(['totally_random_field_12345', 'another_alien_key']));
      final raw = await SettingsStorage.exportRaw();
      expect(raw.containsKey('totally_random_field_12345'), isFalse,
          reason: 'чужеродный top-level ключ не должен попасть в storage');
      expect(raw.containsKey('another_alien_key'), isFalse);

      expect((raw['vars'] as Map)['log_level'], 'info');
    });

    test('replaceRaw отбрасывает чужой vars-подключ, оставляет известные',
        () async {
      final dropped = await SettingsStorage.replaceRaw({
        'vars': {
          'log_level': 'debug',
          'auto_update_subs': 'false',
          'haptic_enabled': 'false',
          'alien_var_xyz': 'should_be_dropped',
        },
      });
      expect(dropped, contains('vars.alien_var_xyz'));
      final raw = await SettingsStorage.exportRaw();
      final vars = raw['vars'] as Map;
      expect(vars['log_level'], 'debug');
      expect(vars['auto_update_subs'], 'false');
      expect(vars['haptic_enabled'], 'false');
      expect(vars.containsKey('alien_var_xyz'), isFalse,
          reason: 'неизвестный var отбрасывается allowlist\'ом');
    });

    test('§219 — warp_account/masque_account переживают restore', () async {
      final dropped = await SettingsStorage.replaceRaw({
        'warp_account': {'private_key': 'wp'},
        'masque_account': {'priv_key_der': 'mp', 'endpoint': 'e'},
      });

      expect(dropped, isNot(contains('warp_account')));
      expect(dropped, isNot(contains('masque_account')));
      final raw = await SettingsStorage.exportRaw();
      expect(raw.containsKey('warp_account'), isTrue);
      expect(raw.containsKey('masque_account'), isTrue,
          reason: 'masque_account не должен теряться при restore (§130)');
    });

    test('merge=true тоже фильтрует чужие ключи', () async {
      await seedStorage({
        'vars': {'log_level': 'warn'},
      });
      final dropped = await SettingsStorage.replaceRaw(
        {
          'vars': {'alien_var': 'x', 'auto_check_updates': 'false'},
          'bogus_top': 1,
        },
        merge: true,
      );
      expect(dropped, containsAll(['vars.alien_var', 'bogus_top']));
      final raw = await SettingsStorage.exportRaw();
      expect((raw['vars'] as Map)['log_level'], 'warn',
          reason: 'merge сохраняет существующее');
      expect((raw['vars'] as Map)['auto_check_updates'], 'false');
      expect((raw['vars'] as Map).containsKey('alien_var'), isFalse);
      expect(raw.containsKey('bogus_top'), isFalse);
    });

    test('чистый бэкап (наш) ничего не отбрасывает', () async {
      final dropped = await SettingsStorage.replaceRaw(sampleSnapshot());
      expect(dropped, isEmpty,
          reason: 'все ключи sampleSnapshot валидны → drop пуст');
    });

    test('legacy top-level ключи отбрасываются (миграции удалены §159)',
        () async {
      const deadKeys = [
        'proxy_sources',
        'app_rules',
        'enabled_rules',
        'rule_outbounds',
        'node_overrides',
      ];
      Map<String, dynamic> snapshot() => {
            'vars': {'log_level': 'info'},
            'proxy_sources': [
              {'url': 'x'}
            ],
            'app_rules': [
              {
                'packages': ['a']
              }
            ],
            'enabled_rules': ['r1'],
            'rule_outbounds': {'r1': 'vpn-1'},
            'node_overrides': {'x': 1},
          };


      final droppedLegacy = await SettingsStorage.replaceRaw(snapshot());
      expect(droppedLegacy, isEmpty);
      for (final k in deadKeys) {
        expect((await SettingsStorage.exportRaw()).containsKey(k), isFalse,
            reason: '$k не должен попасть в storage');
      }

      final dropped = await SettingsStorage.replaceRaw(
          {'storage_version': 1, ...snapshot()});
      expect(dropped, containsAll(deadKeys));
      final raw = await SettingsStorage.exportRaw();
      for (final k in [
        'proxy_sources',
        'app_rules',
        'enabled_rules',
        'rule_outbounds',
        'node_overrides'
      ]) {
        expect(raw.containsKey(k), isFalse, reason: '$k должен быть отброшен');
      }
    });
  });

  test(
      'partial restore: routing-only keeps existing app vars + adds custom_rules',
      () async {

    await seedStorage({
      'vars': {'log_level': 'warn'},
    });

    final backup = jsonEncode({
      'app': 'lxbox',
      'kind': 'backup',
      'storage': {
        'custom_rules': [
          {
            'id': 'rule-x',
            'name': 'X',
            'enabled': true,
            'kind': 'preset',
            'presetId': 'ru-direct',
          },
        ],
      },
    });
    final svc = const BackupService();
    final c = await svc.parseImport(backup);
    final apply = await svc.applyImport(c,
        merge: true, include: {BackupCategory.routing});
    expect(apply.errors, isEmpty);


    expect(await SettingsStorage.getVar('log_level', ''), 'warn');

    final cr = await SettingsStorage.getCustomRules();
    expect(cr.length, 1);
    expect(cr.first.name, 'X');
  });









  group('§393 A2 restore→migrate', () {

    String legacyArchive() => jsonEncode({
          'app': 'lxbox',
          'kind': 'backup',
          'storage': {
            'route_final': 'vpn-2',
            'channels': [
              {'tag': 'vpn-1', 'label': 'Main', 'enabled': true},
              {
                'tag': 'vpn-2',
                'label': 'Relay',
                'enabled': true,
                'detour': true,
                'node_filter': 'DE',
              },
            ],
            'channels_migrated': true,
          },
        });

    Future<Map<String, dynamic>> rawStorage() async =>
        await SettingsStorage.exportRaw();

    test('старый архив: Направления читаются, легаси-ключей в storage нет',
        () async {
      await SettingsStorage.replaceRaw({});
      final svc = const BackupService();
      final contents = await svc.parseImport(legacyArchive());
      final apply = await svc.applyImport(contents,
          merge: false, include: {BackupCategory.routing});
      expect(apply.errors, isEmpty);

      expect(apply.droppedKeys, isEmpty);


      final restored = await SettingsStorage.getDirections();
      expect(restored.map((c) => c.tag), ['vpn-1', 'vpn-2']);
      expect(restored[1].isDetour, isTrue);
      expect(restored[1].nodeFilter, 'DE');
      expect(await SettingsStorage.getRouteFinal(), 'vpn-2');


      final raw = await rawStorage();
      expect(raw.containsKey('channels'), isFalse);
      expect(raw.containsKey('channels_migrated'), isFalse);
      expect(raw['directions_migrated'], true);
    });

    test('старый архив, merge поверх ЖИВЫХ Направлений — архив побеждает',
        () async {




      await SettingsStorage.replaceRaw({
        'directions': [
          {'tag': 'vpn-1', 'label': 'LIVE-Home', 'enabled': true},
          {'tag': 'vpn-4', 'label': 'LIVE-Work', 'enabled': true},
        ],
        'directions_migrated': true,
      });
      final svc = const BackupService();
      final contents = await svc.parseImport(legacyArchive());
      final apply = await svc.applyImport(contents,
          merge: true, include: {BackupCategory.routing});
      expect(apply.errors, isEmpty);

      final restored = await SettingsStorage.getDirections();


      expect(restored.map((c) => c.label), ['Main', '⚙ Relay'],
          reason: 'юзер восстанавливает архив РАДИ его Направлений — они '
              'обязаны заменить живой список, а не молча проиграть ему');
      final raw = await rawStorage();
      expect(raw.containsKey('channels'), isFalse);
      expect(raw.containsKey('channels_migrated'), isFalse);
    });

    test('новый архив, merge поверх живых Направлений — архив побеждает',
        () async {
      await SettingsStorage.replaceRaw({
        'directions': [
          {'tag': 'vpn-1', 'label': 'LIVE', 'enabled': true},
        ],
        'directions_migrated': true,
      });
      final svc = const BackupService();
      final archive = jsonEncode({
        'app': 'lxbox',
        'kind': 'backup',
        'storage': {
          'directions': [
            {'tag': 'vpn-1', 'label': 'ARCHIVE-Main', 'enabled': true},
            {'tag': 'vpn-2', 'label': 'ARCHIVE-Relay', 'enabled': true},
          ],
          'directions_migrated': true,
        },
      });
      await svc.applyImport(await svc.parseImport(archive),
          merge: true, include: {BackupCategory.routing});
      expect((await SettingsStorage.getDirections()).map((c) => c.label),
          ['ARCHIVE-Main', 'ARCHIVE-Relay']);
    });

    test('re-export после restore старого архива пишет только новые ключи',
        () async {
      await SettingsStorage.replaceRaw({});
      final svc = const BackupService();
      await svc.applyImport(await svc.parseImport(legacyArchive()),
          merge: false, include: {BackupCategory.routing});

      final st = (jsonDecode(
                  await svc.buildExport(include: {BackupCategory.routing}))
              as Map<String, dynamic>)['storage'] as Map<String, dynamic>;
      expect(st.containsKey('directions'), isTrue);
      expect((st['directions'] as List), hasLength(2));
      expect(st.containsKey('channels'), isFalse);
      expect(st.containsKey('channels_migrated'), isFalse);
    });

    test('round-trip нового архива: Направления идентичны', () async {
      await SettingsStorage.replaceRaw({
        'directions': [
          {'tag': 'vpn-1', 'label': 'Main', 'enabled': true},
          {'tag': 'vpn-2', 'label': 'Work', 'enabled': false, 'node_filter': 'NL'},
          {'tag': 'vpn-3', 'label': 'Relay', 'enabled': true, 'detour': true},
        ],
        'directions_migrated': true,
        'route_final': 'vpn-3',
      });
      final before = await SettingsStorage.getDirections();

      final svc = const BackupService();
      final exported = await svc.buildExport(include: {BackupCategory.routing});
      await SettingsStorage.replaceRaw({});
      final apply = await svc.applyImport(await svc.parseImport(exported),
          merge: false, include: {BackupCategory.routing});
      expect(apply.errors, isEmpty);
      expect(apply.droppedKeys, isEmpty);

      final after = await SettingsStorage.getDirections();
      expect(after.map((c) => c.toJson()), before.map((c) => c.toJson()));
      expect(await SettingsStorage.getRouteFinal(), 'vpn-3');
      final raw = await rawStorage();
      expect(raw['directions_migrated'], true);
      expect(raw.containsKey('channels'), isFalse);
    });
  });
}
