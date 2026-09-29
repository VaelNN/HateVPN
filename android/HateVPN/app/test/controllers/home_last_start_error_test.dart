

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/controllers/home_controller.dart';
import 'package:lxbox/models/home_state.dart';
import 'package:lxbox/services/debug/serializers/home_state.dart';
import 'package:lxbox/services/haptic_service.dart';
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

  TunnelStatusEvent event(TunnelStatus status, {String? reason}) {



    final raw = switch (status) {
      TunnelStatus.connected => 'Started',
      TunnelStatus.connecting => 'Starting',
      TunnelStatus.disconnected || TunnelStatus.revoked => 'Stopped',
      _ => status.name,
    };
    return TunnelStatusEvent(status: status, raw: raw, errorReason: reason);
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('last_start_error_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);

    HapticService.I.enabled = false;
    for (final ch in [methods, ccStatus, ccGroups]) {
      messenger.setMockMethodCallHandler(ch, (call) async => null);
    }
    controller = HomeController();
  });

  tearDown(() async {


    controller.dispose();

    await Future<void>.delayed(const Duration(milliseconds: 50));
    for (final ch in [methods, ccStatus, ccGroups]) {
      messenger.setMockMethodCallHandler(ch, null);
    }
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('аварийный stop с errorReason → lastStartError + lastStartErrorAt', () {


    controller.debugHandleStatusEvent(event(TunnelStatus.connecting));
    controller.debugHandleStatusEvent(event(TunnelStatus.disconnected,
        reason: 'Failed to start service: X'));

    expect(controller.state.lastStartError,
        'Stopped: Failed to start service: X');
    expect(controller.state.lastStartErrorAt, isNotNull);

    expect(controller.state.lastError?.renderEn(),
        'Stopped: Failed to start service: X');
  });

  test('clearError() чистит lastError, но НЕ трогает lastStartError', () {
    controller.debugHandleStatusEvent(event(TunnelStatus.connecting));
    controller.debugHandleStatusEvent(
        event(TunnelStatus.disconnected, reason: 'boom'));
    final at = controller.state.lastStartErrorAt;

    controller.clearError();

    expect(controller.state.lastError, isNull);
    expect(controller.state.lastStartError, 'Stopped: boom');
    expect(controller.state.lastStartErrorAt, at);
  });

  test('повторный disconnected без errorReason сохраняет lastStartError', () {
    controller.debugHandleStatusEvent(event(TunnelStatus.connecting));
    controller.debugHandleStatusEvent(
        event(TunnelStatus.disconnected, reason: 'boom'));
    final at = controller.state.lastStartErrorAt;


    controller.debugHandleStatusEvent(event(TunnelStatus.disconnected));
    expect(controller.state.lastStartError, 'Stopped: boom');
    expect(controller.state.lastStartErrorAt, at);



    controller.debugHandleStatusEvent(event(TunnelStatus.connecting));
    controller.debugHandleStatusEvent(event(TunnelStatus.disconnected));
    expect(controller.state.lastStartError, 'Stopped: boom');
    expect(controller.state.lastStartErrorAt, at);
  });

  test('успешный старт (connected) — единственная очистка', () {
    controller.debugHandleStatusEvent(event(TunnelStatus.connecting));
    controller.debugHandleStatusEvent(
        event(TunnelStatus.disconnected, reason: 'boom'));
    expect(controller.state.lastStartError, isNotEmpty);

    controller.debugHandleStatusEvent(event(TunnelStatus.connected));

    expect(controller.state.lastStartError, isEmpty);
    expect(controller.state.lastStartErrorAt, isNull);
  });

  test('revoked → lastStartError с текстом про другой VPN', () {
    controller.debugHandleStatusEvent(event(TunnelStatus.connecting));
    controller.debugHandleStatusEvent(event(TunnelStatus.revoked));

    expect(controller.state.lastStartError, contains('Another VPN app'));
    expect(controller.state.lastStartErrorAt, isNotNull);
    expect(controller.state.lastError?.renderEn(),
        controller.state.lastStartError);
  });

  group('serializeHomeState (§250)', () {
    test('пустое состояние → last_start_error="" / last_start_error_at=null',
        () {
      final json = serializeHomeState(HomeState());
      expect(json.containsKey('last_start_error'), isTrue);
      expect(json.containsKey('last_start_error_at'), isTrue);
      expect(json['last_start_error'], '');
      expect(json['last_start_error_at'], isNull);
    });

    test('заполненное состояние → reason + ISO-8601 UTC timestamp', () {
      final json = serializeHomeState(HomeState(
        lastStartError: 'Stopped: Failed to start service: X',
        lastStartErrorAt: DateTime.utc(2026, 7, 6, 12, 30),
      ));
      expect(json['last_start_error'], 'Stopped: Failed to start service: X');
      expect(json['last_start_error_at'], '2026-07-06T12:30:00.000Z');
    });
  });
}
