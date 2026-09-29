

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/controllers/home_controller.dart';
import 'package:lxbox/models/home_state.dart';
import 'package:lxbox/services/haptic_service.dart';
import 'package:lxbox/services/probe/probe_lifecycle.dart';
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
  late List<String> methodCalls;

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
    tempDir = await Directory.systemTemp.createTemp('probe_halt_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    HapticService.I.enabled = false;
    methodCalls = <String>[];
    for (final ch in [methods, ccStatus, ccGroups]) {
      messenger.setMockMethodCallHandler(ch, (call) async {
        methodCalls.add(call.method);
        return null;
      });
    }
    controller = HomeController();
    ProbeLifecycle.I.haltAll();
  });

  tearDown(() async {
    controller.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    for (final ch in [methods, ccStatus, ccGroups]) {
      messenger.setMockMethodCallHandler(ch, null);
    }
    ProbeLifecycle.I.haltAll();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });


  bool Function() armProbe() {
    var cancelled = false;
    ProbeLifecycle.I.register(() => cancelled = true);
    return () => cancelled;
  }

  test('disconnected отменяет активную folder-probe', () {
    controller.debugHandleStatusEvent(event(TunnelStatus.connecting));
    final wasCancelled = armProbe();

    controller.debugHandleStatusEvent(event(TunnelStatus.disconnected));

    expect(wasCancelled(), isTrue);
    expect(controller.massPingRunning, isFalse);
    expect(ProbeLifecycle.I.isProbing, isFalse);
  });

  test('revoked отменяет активную folder-probe', () {
    controller.debugHandleStatusEvent(event(TunnelStatus.connecting));
    final wasCancelled = armProbe();

    controller.debugHandleStatusEvent(event(TunnelStatus.revoked));

    expect(wasCancelled(), isTrue);
    expect(ProbeLifecycle.I.isProbing, isFalse);
  });

  test('сворачивание приложения (onAppPaused) отменяет активную folder-probe',
      () {
    final wasCancelled = armProbe();

    controller.onAppPaused();

    expect(wasCancelled(), isTrue);
    expect(ProbeLifecycle.I.isProbing, isFalse);
  });





  test('сворачивание приложения НЕ отменяет mass-ping', () async {
    controller.debugHandleStatusEvent(event(TunnelStatus.connected));
    unawaited(controller.runMassUrltest(order: const ['a', 'b', 'c']));
    expect(controller.massPingRunning, isTrue, reason: 'прогон должен идти');
    methodCalls.clear();

    controller.onAppPaused();

    expect(controller.massPingRunning, isTrue);
    expect(methodCalls, isNot(contains('ccCancelPing')));
  });


  test('disconnected отменяет идущий mass-ping', () async {
    controller.debugHandleStatusEvent(event(TunnelStatus.connected));
    unawaited(controller.runMassUrltest(order: const ['a', 'b', 'c']));
    expect(controller.massPingRunning, isTrue);
    methodCalls.clear();

    controller.debugHandleStatusEvent(event(TunnelStatus.disconnected));

    expect(controller.massPingRunning, isFalse);
    expect(methodCalls, contains('ccCancelPing'));
  });
}
