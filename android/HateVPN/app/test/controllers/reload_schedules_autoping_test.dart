

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/controllers/home_controller.dart';
import 'package:lxbox/services/haptic_service.dart';
import 'package:lxbox/services/settings_storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.tempRoot);
  final String tempRoot;
  @override
  Future<String?> getApplicationDocumentsPath() async => tempRoot;
  @override
  Future<String?> getApplicationSupportPath() async => tempRoot;
}






void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methods = MethodChannel('com.leadaxe.lxbox/methods');
  const ccStatus = MethodChannel('lxbox/cc/status');
  const ccGroups = MethodChannel('lxbox/cc/groups');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory tempDir;
  late HomeController controller;
  late List<String> calls;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reload_autoping_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    SettingsStorage.resetCacheForTesting();
    HapticService.I.enabled = false;
    calls = <String>[];
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call.method);

      if (call.method == 'reloadVPN') return true;
      return null;
    });
    for (final ch in [ccStatus, ccGroups]) {
      messenger.setMockMethodCallHandler(ch, (call) async => null);
    }
    controller = HomeController();
  });

  tearDown(() async {
    controller.cancelMassPing();
    controller.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    for (final ch in [methods, ccStatus, ccGroups]) {
      messenger.setMockMethodCallHandler(ch, null);
    }
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });




  Future<void> waitUntil(bool Function() cond,
      {Duration timeout = const Duration(seconds: 5)}) async {
    final sw = Stopwatch()..start();
    while (!cond() && sw.elapsed < timeout) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

  }

  test('reloadVpn при живом туннеле планирует автопинг', () async {
    controller.debugSeedNodeState(group: 'vpn-1', activeNode: 'n1');

    await controller.reloadVpn();
    await waitUntil(() => controller.autoPingScheduledForTesting);

    expect(calls, contains('reloadVPN'), reason: 'сам reload должен произойти');
    expect(controller.autoPingScheduledForTesting, isTrue,
        reason: 'новый состав узлов обязан получить замеры без действий юзера');



    expect(calls, contains('ccGetGroups'),
        reason: 'состав узлов обязан обновиться от ядра ДО планирования пинга');
    expect(calls.indexOf('ccGetGroups'), greaterThan(calls.indexOf('reloadVPN')),
        reason: 'группы тянем уже после reload, иначе снимем доreload-состав');
  });

  test('галка auto_ping_on_start=false — автопинг не планируется', () async {
    await SettingsStorage.setVar('auto_ping_on_start', 'false');
    controller.debugSeedNodeState(group: 'vpn-1', activeNode: 'n1');

    await controller.reloadVpn();




    await waitUntil(() => calls.contains('ccGetGroups'));
    final hold = Stopwatch()..start();
    while (hold.elapsedMilliseconds < 200) {
      expect(controller.autoPingScheduledForTesting, isFalse,
          reason: 'выключенная галка обязана уважаться и на этом пути');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(calls, contains('reloadVPN'));
  });
}
