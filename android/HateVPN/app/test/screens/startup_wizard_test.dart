import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lxbox/screens/home/home_dialogs.dart';
import 'package:lxbox/services/settings_storage.dart';
import 'package:lxbox/services/platform_channels.dart';
import 'package:lxbox/vpn/box_vpn_client.dart';







void main() {
  late Directory tmp;
  const ppChannel = MethodChannel('plugins.flutter.io/path_provider');
  const vpnChannel = MethodChannel('com.leadaxe.lxbox/methods');
  const utilsChannel = MethodChannel(PlatformChannels.utils);
  final calls = <MethodCall>[];

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = await Directory.systemTemp.createTemp('lxbox_wizard_');
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ppChannel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory' ||
              call.method == 'getApplicationDocumentsPath') {
            return tmp.path;
          }
          return null;
        });
    SettingsStorage.resetCacheForTesting();
  });

  tearDown(() async {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(ppChannel, null);
    m.setMockMethodCallHandler(vpnChannel, null);
    m.setMockMethodCallHandler(utilsChannel, null);
    try {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    } catch (_) {}
  });

  void mockVpn() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vpnChannel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'requestAddTile':
              return 'added';
            case 'isIgnoringBatteryOptimizations':
              return true;
            default:
              return null;
          }
        });
  }










  group('maybeShowAddTilePrompt', () {
    test('first run: calls requestAddTile and sets persist flag', () async {
      mockVpn();
      await maybeShowAddTilePrompt(_FakeContext(), BoxVpnClient());
      expect(calls.where((c) => c.method == 'requestAddTile'), hasLength(1));
      expect(await SettingsStorage.getVar('wizard_addtile_v1', '0'), '1');
    });

    test('second run: flag already set → no native call', () async {
      mockVpn();
      await SettingsStorage.setVar('wizard_addtile_v1', '1');
      await maybeShowAddTilePrompt(_FakeContext(), BoxVpnClient());
      expect(calls.where((c) => c.method == 'requestAddTile'), isEmpty);
    });
  });

  group('maybeShowBatteryOptimizationDialog', () {
    test('whitelisted → early return, no persist flag set', () async {
      mockVpn();
      await maybeShowBatteryOptimizationDialog(_FakeContext(), BoxVpnClient());

      expect(await SettingsStorage.getVar('wizard_battery_v1', '0'), '0');
    });
  });

  test(
    'notifications: native prompt once, with no explanatory dialog',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(utilsChannel, (call) async {
            calls.add(call);
            if (call.method == 'checkNotificationPermission') return false;
            return null;
          });
      await maybeShowNotificationPermissionDialog(_MountedContext());
      await maybeShowNotificationPermissionDialog(_MountedContext());
      expect(
        calls.where((c) => c.method == 'requestNotificationPermission'),
        hasLength(1),
      );
    },
  );
}



class _MountedContext implements BuildContext {
  @override
  bool get mounted => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}





class _FakeContext implements BuildContext {
  @override
  bool get mounted => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
