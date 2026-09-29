import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lxbox/models/codec/rule_record.dart';
import 'package:lxbox/models/codec/source_record.dart';
import 'package:lxbox/models/direction.dart';
import 'package:lxbox/models/custom_rule.dart';
import 'package:lxbox/models/node_link.dart';
import 'package:lxbox/models/server_list.dart';
import 'package:lxbox/services/settings_storage.dart';









void main() {
  late Directory tmp;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  String mainPath() => '${tmp.path}/lxbox_settings.json';

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = await Directory.systemTemp.createTemp('lxbox_detour_heal_');
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
    } catch (_) {}
  });

  String memberRaw(String name) =>
      'vless://u-$name@h.com:443?type=ws&security=tls#$name';




  Future<void> seedDetourRefsOnVpn3({bool vpn3Detour = true}) async {
    final data = {
      'directions_migrated': true,
      'directions': [
        const Direction(tag: 'vpn-1', label: 'Main').toJson(),
        Direction(tag: 'vpn-3', label: 'Relay', isDetour: vpn3Detour).toJson(),
      ],
      'storage_version': 1,
      'sources': [
        sourceToRecord(UserServer(
          id: 'u1',
          name: 'Solo',
          enabled: true,
          tagPrefix: '',
          detourPolicy: const DetourPolicy(overrideDetour: NodeLink(tag: 'vpn-3')),
          origin: UserSource.paste,
          rawBody: memberRaw('solo-node'),
        )),
        sourceToRecord(SubscriptionServers(
          id: 's1',
          name: 'Sub',
          enabled: true,
          tagPrefix: '',
          detourPolicy: const DetourPolicy(overrideDetour: NodeLink(tag: 'vpn-3-auto')),
          url: 'https://example.com/sub',
        )),
        sourceToRecord(FolderServers(
          id: 'f1',
          name: 'Folder',
          enabled: true,
          tagPrefix: '',
          detourPolicy: const DetourPolicy(overrideDetour: NodeLink(tag: 'vpn-3')),
          members: [
            FolderMember(
                raw: memberRaw('node-a'), detour: const NodeLink(tag: 'vpn-3')),
            FolderMember(raw: memberRaw('node-b')),
          ],
        )),


        sourceToRecord(FolderServers(
          id: 'f2',
          name: 'Homonym',
          enabled: true,
          tagPrefix: 'hm-',
          detourPolicy: const DetourPolicy(
              overrideDetour: NodeLink(folderId: 'f2', tag: 'vpn-3')),
          members: [
            FolderMember(raw: memberRaw('vpn-3')),
            FolderMember(
                raw: memberRaw('node-c'),
                detour: const NodeLink(folderId: 'f2', tag: 'vpn-3')),
          ],
        )),
      ],
    };
    await File(mainPath()).writeAsString(jsonEncode(data));
    SettingsStorage.resetCacheForTesting();
  }

  Future<Direction> vpn3() async => (await SettingsStorage.getDirections())
      .firstWhere((c) => c.tag == 'vpn-3');

  Future<ServerList> listById(String id) async =>
      (await SettingsStorage.getServerLists()).firstWhere((l) => l.id == id);

  test('flag-unset: все четыре вида detour-ссылок → \'\', омонимы целы',
      () async {
    await seedDetourRefsOnVpn3();

    final res = await SettingsStorage.updateDirection(
        (await vpn3()).copyWith(isDetour: false));

    expect((await listById('u1')).detourPolicy.overrideDetour, NodeLink.none);
    expect((await listById('s1')).detourPolicy.overrideDetour, NodeLink.none);
    final f1 = await listById('f1') as FolderServers;
    expect(f1.detourPolicy.overrideDetour, NodeLink.none);
    expect(f1.members.first.detour, NodeLink.none);

    const member = NodeLink(folderId: 'f2', tag: 'vpn-3');
    final f2 = await listById('f2') as FolderServers;
    expect(f2.detourPolicy.overrideDetour, member);
    expect(f2.members[1].detour, member);

    expect(res.detours, 4);
    expect(res.rules, 0);
  });

  test('flag-unset необратим: повторная установка не воскрешает ссылки',
      () async {
    await seedDetourRefsOnVpn3();
    await SettingsStorage.updateDirection(
        (await vpn3()).copyWith(isDetour: false));

    await SettingsStorage.updateDirection(
        (await vpn3()).copyWith(isDetour: true));

    expect((await listById('u1')).detourPolicy.overrideDetour, NodeLink.none);
  });

  test('disable detour-Направления лечит detour-ссылки', () async {
    await seedDetourRefsOnVpn3();

    final res = await SettingsStorage.updateDirection(
        (await vpn3()).copyWith(enabled: false));

    expect((await listById('u1')).detourPolicy.overrideDetour, NodeLink.none);
    expect(res.detours, 4);
  });

  test('delete detour-Направления лечит detour-ссылки', () async {
    await seedDetourRefsOnVpn3();

    final res = await SettingsStorage.deleteDirection('vpn-3');

    expect((await listById('u1')).detourPolicy.overrideDetour, NodeLink.none);
    expect((await listById('s1')).detourPolicy.overrideDetour, NodeLink.none);
    expect(res.detours, 4);
  });


  group('§274 — flag-set НЕ лечит rules-ссылки', () {
    Future<void> seedRulesRefsOnVpn3({String routeFinal = 'vpn-3'}) async {
      final data = {
        'directions_migrated': true,
        'directions': [
          const Direction(tag: 'vpn-1', label: 'Main').toJson(),
          const Direction(tag: 'vpn-3', label: 'Aux').toJson(),
        ],
        'route_final': routeFinal,
        'storage_version': 1,
        'rules': [
          ruleToRecord(CustomRuleInline(
                  name: 'r1', domains: const ['x.com'], outbound: 'vpn-3')),
          ruleToRecord(CustomRulePreset(
            name: 'Block Ads',
            presetId: 'block-ads',
            varsValues: const {'outbound': 'vpn-3'},
          )),
          ruleToRecord(CustomRuleSrs(
            name: 'GeoIP RU',
            srsUrl: 'https://example.com/geoip-ru.srs',
            outbound: 'vpn-3',
          )),
        ],
      };
      await File(mainPath()).writeAsString(jsonEncode(data));
      SettingsStorage.resetCacheForTesting();
    }

    test('route_final + inline + preset varsValues + srs целы, счётчики 0',
        () async {
      await seedRulesRefsOnVpn3();

      final res = await SettingsStorage.updateDirection(
          (await vpn3()).copyWith(isDetour: true));

      expect(await SettingsStorage.getRouteFinal(), 'vpn-3');
      final rules = await SettingsStorage.getCustomRules();
      expect(rules.map((r) => r.outbound), everyElement('vpn-3'));

      expect(rules.whereType<CustomRuleSrs>().single.outbound, 'vpn-3');
      expect(res.rules, 0);
      expect(res.detours, 0);
    });

    test('route_final на auto-двойник тоже цел', () async {
      await seedRulesRefsOnVpn3(routeFinal: 'vpn-3-auto');

      await SettingsStorage.updateDirection(
          (await vpn3()).copyWith(isDetour: true));

      expect(await SettingsStorage.getRouteFinal(), 'vpn-3-auto');
    });
  });
}
