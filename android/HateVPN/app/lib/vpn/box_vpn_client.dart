import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import '../models/app_info.dart';
import '../models/background_mode.dart';
import '../models/memory_limit_setting.dart';
import '../models/tunnel_status.dart';
import '../services/app_log.dart';
import '../services/l10n/app_language_reconcile.dart'
    show AppLanguageNativeState;
import '../services/platform_channels.dart';



part 'box_vpn_client/method_names.dart';
part 'box_vpn_client/timeouts.dart';


















class BoxVpnClient {



  factory BoxVpnClient() => I;

  BoxVpnClient._({MethodChannel? methods, EventChannel? events})
      : _methods = methods ?? const MethodChannel(_kMethodsChannel),
        _events = events ?? const EventChannel(_kStatusChannel);


  static final BoxVpnClient I = BoxVpnClient._();



  @visibleForTesting
  factory BoxVpnClient.forTest({
    MethodChannel? methods,
    EventChannel? events,
  }) =>
      BoxVpnClient._(methods: methods, events: events);


  static const _kMethodsChannel = PlatformChannels.methods;
  static const _kStatusChannel = PlatformChannels.statusEvents;

  final MethodChannel _methods;
  final EventChannel _events;






  Future<bool> saveConfig(String config) async {
    final ok = await _invoke<bool>(
      _Methods.saveConfig,
      args: {'config': config},
      timeout: _Timeouts.config,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }







  Future<String?> getFilesDir() async {
    try {
      return await _invoke<String>(
        _Methods.getFilesDir,
        timeout: _Timeouts.config,
        onTimeoutValue: null,
      );
    } catch (_) {
      return null;
    }
  }



  Future<String> getConfig() async {
    final cfg = await _invoke<String>(
      _Methods.getConfig,
      timeout: _Timeouts.config,
      onTimeoutValue: '{}',
    );
    return cfg ?? '{}';
  }






  Future<bool> startVPN() async {
    final ok = await _invoke<bool>(
      _Methods.startVPN,
      timeout: _Timeouts.startVpn,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }





  Future<({bool started, bool needsConsent})> startVpnHeadless() async {
    final r = await _invoke<Map<dynamic, dynamic>>(
      _Methods.startVpnHeadless,
      timeout: _Timeouts.startVpn,
      onTimeoutValue: const {'started': false, 'needs_consent': false},
    );
    return (
      started: r?['started'] == true,
      needsConsent: r?['needs_consent'] == true,
    );
  }






  Future<bool> stopVPN() async {
    final ok = await _invoke<bool>(
      _Methods.stopVPN,
      timeout: _Timeouts.stopVpn,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }







  Future<bool> forceStopVPN() async {
    final ok = await _invoke<bool>(
      _Methods.forceStopVPN,
      timeout: _Timeouts.settings,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }













  Future<TunnelStatus> getVpnStatus() async {
    final res = await _invoke<Object>(
      _Methods.getVpnStatus,
      timeout: _Timeouts.status,
      onTimeoutValue: null,
    );
    if (res is Map) {
      final s = res['status']?.toString() ?? '';
      if (s.isEmpty) return TunnelStatus.disconnected;
      return TunnelStatus.fromNative(s, revoked: res['revoked'] == true);
    }
    final s = res?.toString() ?? '';
    if (s.isEmpty) return TunnelStatus.disconnected;
    return TunnelStatus.fromNative(s);
  }




  Future<bool> isForeignVpnActive() async {
    final r = await _invoke<bool>(
      _Methods.isForeignVpnActive,
      timeout: _Timeouts.status,
      onTimeoutValue: false,
    );
    return r ?? false;
  }





  Future<int> getTunnelUptimeMs() async {
    final ms = await _invoke<int>(
      _Methods.getTunnelUptimeMs,
      timeout: _Timeouts.status,
      onTimeoutValue: null,
    );
    return ms ?? 0;
  }






  Future<bool> setNotificationTitle(String title) async {
    final ok = await _invoke<bool>(
      _Methods.setNotificationTitle,
      args: {'title': title},
      timeout: _Timeouts.settings,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }



  Future<bool> setNotificationText(String text) async {
    final ok = await _invoke<bool>(
      _Methods.setNotificationText,
      args: {'text': text},
      timeout: _Timeouts.settings,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }

  Future<bool> setAutoStart(bool enabled) async {
    final ok = await _invoke<bool>(
      _Methods.setAutoStart,
      args: {'enabled': enabled},
      timeout: _Timeouts.settings,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }

  Future<bool> getAutoStart() async {
    final ok = await _invoke<bool>(
      _Methods.getAutoStart,
      timeout: _Timeouts.settings,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }

  Future<bool> setKeepOnExit(bool enabled) async {
    final ok = await _invoke<bool>(
      _Methods.setKeepOnExit,
      args: {'enabled': enabled},
      timeout: _Timeouts.settings,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }

  Future<bool> getKeepOnExit() async {
    final ok = await _invoke<bool>(
      _Methods.getKeepOnExit,
      timeout: _Timeouts.settings,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }




  Future<bool> setCoreLogsEnabled(bool enabled) async {
    final ok = await _invoke<bool>(
      _Methods.setCoreLogsEnabled,
      args: {'enabled': enabled},
      timeout: _Timeouts.settings,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }

  Future<bool> getCoreLogsEnabled() async {
    final ok = await _invoke<bool>(
      _Methods.getCoreLogsEnabled,
      timeout: _Timeouts.settings,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }



  Future<bool> setCoreLogsVerbose(bool enabled) async {
    final ok = await _invoke<bool>(
      _Methods.setCoreLogsVerbose,
      args: {'enabled': enabled},
      timeout: _Timeouts.settings,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }

  Future<bool> getCoreLogsVerbose() async {
    final ok = await _invoke<bool>(
      _Methods.getCoreLogsVerbose,
      timeout: _Timeouts.settings,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }




  Future<bool> setAllowBypass(bool enabled) async {
    final ok = await _invoke<bool>(
      _Methods.setAllowBypass,
      args: {'enabled': enabled},
      timeout: _Timeouts.settings,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }

  Future<bool> getAllowBypass() async {
    final ok = await _invoke<bool>(
      _Methods.getAllowBypass,
      timeout: _Timeouts.settings,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }




  Future<bool> setAutoRedirect(bool enabled) async {
    final ok = await _invoke<bool>(
      _Methods.setAutoRedirect,
      args: {'enabled': enabled},
      timeout: _Timeouts.settings,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }

  Future<bool> getAutoRedirect() async {
    final ok = await _invoke<bool>(
      _Methods.getAutoRedirect,
      timeout: _Timeouts.settings,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }




  Future<bool> setHasTun(bool hasTun) async {
    final ok = await _invoke<bool>(
      _Methods.setHasTun,
      args: {'enabled': hasTun},
      timeout: _Timeouts.settings,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }





  Future<bool> getCurrentSessionAllowBypass() async {
    final ok = await _invoke<bool>(
      _Methods.getCurrentSessionAllowBypass,
      timeout: _Timeouts.settings,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }







  Future<void> quitApp() async {
    await _invoke<bool>(
      _Methods.quitApp,
      timeout: const Duration(milliseconds: 500),
      onTimeoutValue: true,
    );
  }







  Future<List<AppInfo>> getInstalledApps() async {
    final result = await _invoke<List<dynamic>>(
      _Methods.getInstalledApps,
      timeout: _Timeouts.apps,
      onTimeoutValue: const <dynamic>[],
    );
    if (result == null) return const [];
    return result
        .map((e) => AppInfo.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }



  Future<String> getAppIcon(String packageName) async {
    final s = await _invoke<String>(
      _Methods.getAppIcon,
      args: {'packageName': packageName},
      timeout: _Timeouts.app,
      onTimeoutValue: '',
    );
    return s ?? '';
  }




  static const Map<dynamic, dynamic> _appInfoTimeoutMarker = <dynamic, dynamic>{
    '__timeout__': true,
  };













  Future<AppInfo?> getAppInfo(String packageName, {Duration? timeout}) async {
    final r = await _invoke<Map<dynamic, dynamic>>(
      _Methods.getAppInfo,
      args: {'packageName': packageName},
      timeout: timeout ?? _Timeouts.app,
      onTimeoutValue: _appInfoTimeoutMarker,
    );
    if (identical(r, _appInfoTimeoutMarker)) {
      throw TimeoutException('getAppInfo($packageName)');
    }
    if (r == null) {

      throw StateError('getAppInfo($packageName): null reply');
    }
    if (r['notFound'] == true) return null;
    return AppInfo.fromMap(Map<String, dynamic>.from(r));
  }






  Future<bool> isIgnoringBatteryOptimizations() async {
    final ok = await _invoke<bool>(
      _Methods.isIgnoringBatteryOptimizations,
      timeout: _Timeouts.settings,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }


  Future<bool> openBatteryOptimizationSettings() async {
    final ok = await _invoke<bool>(
      _Methods.openBatteryOptimizationSettings,
      timeout: _Timeouts.settings,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }


  Future<bool> openAppDetailsSettings() async {
    final ok = await _invoke<bool>(
      _Methods.openAppDetailsSettings,
      timeout: _Timeouts.settings,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }





  Future<bool> areNotificationsEnabled() async {
    final ok = await _invoke<bool>(
      _Methods.areNotificationsEnabled,
      timeout: _Timeouts.settings,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }


  Future<bool> openNotificationSettings() async {
    final ok = await _invoke<bool>(
      _Methods.openNotificationSettings,
      timeout: _Timeouts.settings,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }




  Future<bool> openVpnSettings() async {
    final ok = await _invoke<bool>(
      _Methods.openVpnSettings,
      timeout: _Timeouts.settings,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }







  Future<BackgroundMode> getBackgroundMode() async {
    final m = await _invoke<String>(
      _Methods.getBackgroundMode,
      timeout: _Timeouts.settings,
      onTimeoutValue: null,
    );
    return BackgroundMode.fromNative(m);
  }

  Future<void> setBackgroundMode(BackgroundMode mode) async {
    await _invoke<void>(
      _Methods.setBackgroundMode,
      args: {'mode': mode.wireValue},
      timeout: _Timeouts.settings,
      onTimeoutValue: null,
    );
  }







  Future<String> getMemoryLimit() async {
    final v = await _invoke<String>(
      _Methods.getMemoryLimit,
      timeout: _Timeouts.settings,
      onTimeoutValue: null,
    );
    return MemoryLimitSetting.normalize(v);
  }

  Future<void> setMemoryLimit(String value) async {
    await _invoke<void>(
      _Methods.setMemoryLimit,
      args: {'value': MemoryLimitSetting.normalize(value)},
      timeout: _Timeouts.settings,
      onTimeoutValue: null,
    );
  }







  Future<void> setAppLanguage(String tag) async {
    await _invoke<void>(
      _Methods.setAppLanguage,
      args: {'tag': tag},
      timeout: _Timeouts.settings,
      onTimeoutValue: null,
    );
  }




  Future<AppLanguageNativeState?> getAppLanguageState() async {
    try {
      final r = await _invoke<Object>(
        _Methods.getAppLanguageState,
        timeout: _Timeouts.settings,
        onTimeoutValue: null,
      );
      if (r is! Map || r['supported'] != true) return null;
      return AppLanguageNativeState(
        applicationLocales: r['applicationLocales']?.toString() ?? '',
        lastPushedLocale: r['lastPushedLocale']?.toString(),
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }











  Future<String> requestAddTile() async {
    final s = await _invoke<String>(
      _Methods.requestAddTile,
      timeout: _Timeouts.requestTile,
      onTimeoutValue: 'error: timeout',
    );
    return s ?? 'error: null';
  }









  Future<String> getCoreVersion() async {
    final v = await _invoke<String>(
      _Methods.getCoreVersion,
      timeout: _Timeouts.settings,
      onTimeoutValue: '',
    );
    return v ?? '';
  }







  Future<MemoryInfo?> getMemoryInfo() async {
    final r = await _invoke<Map<dynamic, dynamic>>(
      _Methods.getMemoryInfo,
      timeout: _Timeouts.settings,
      onTimeoutValue: null,
    );
    if (r == null) return null;
    return MemoryInfo.fromMap(r);
  }












  Future<Uint8List> pprofRaw(
    String pathAndQuery, {
    int blockingSeconds = 0,
  }) async {





    final timeout = blockingSeconds > 0
        ? Duration(seconds: blockingSeconds + _Timeouts.cpuHeadroomSeconds)
        : _Timeouts.goroutineDump;
    final bytes = await _invoke<Uint8List>(
      _Methods.pprofProfile,
      args: {'pathAndQuery': pathAndQuery},
      timeout: timeout,
      onTimeoutValue: Uint8List(0),
    );
    return bytes ?? Uint8List(0);
  }





  Future<String> dumpGoroutines() async {
    try {
      final bytes = await pprofRaw('goroutine?debug=2');
      return bytes.isEmpty
          ? '<goroutine dump unavailable: empty response (timeout?)>'


          : utf8.decode(bytes, allowMalformed: true);
    } on PlatformException catch (e) {
      return '<goroutine dump unavailable: ${e.message ?? e.code}>';
    }
  }




  Future<Uint8List> captureCpuProfile({int durationMs = 10000}) async {
    final seconds = (durationMs ~/ 1000).clamp(1, 60);
    return pprofRaw('profile?seconds=$seconds', blockingSeconds: seconds);
  }





  Future<bool> reloadVPN() async {
    final ok = await _invoke<bool>(
      _Methods.reloadVPN,
      timeout: _Timeouts.reload,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }







  Future<bool> resetNetwork() async {
    final ok = await _invoke<bool>(
      _Methods.resetNetwork,
      timeout: _Timeouts.resetNet,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }







  Future<bool> setQuicKnob(String knob, {required bool disabled}) async {
    final ok = await _invoke<bool>(
      _Methods.setQuicKnob,
      args: {'knob': knob, 'disabled': disabled},
      timeout: _Timeouts.settings,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }






  Future<bool> clearDnsCache() async {
    final ok = await _invoke<bool>(
      _Methods.clearDnsCache,
      timeout: _Timeouts.dnsCache,
      onTimeoutValue: false,
    );
    return ok ?? false;
  }

















  Future<CoreCheck?> checkConfig(String config) async {
    if (config.trim().isEmpty) return null;
    try {
      final r = await _invoke<Map<Object?, Object?>>(
        _Methods.checkConfig,
        args: {'config': config},
        timeout: _Timeouts.checkConfig,
        onTimeoutValue: null,
      );
      if (r == null) return null;
      return CoreCheck(
        ok: r['ok'] == true,
        error: r['error']?.toString() ?? '',
      );
    } on PlatformException catch (e) {
      AppLog.I.debug('checkConfig failed: ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<String?> formatConfig(String config) async {
    if (config.trim().isEmpty) return null;
    try {
      return await _invoke<String>(
        _Methods.formatConfig,
        args: {'config': config},
        timeout: _Timeouts.formatConfig,
        onTimeoutValue: null,
      );
    } on PlatformException catch (e) {
      AppLog.I.debug('formatConfig failed: ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

























  late final Stream<TunnelStatusEvent> _statusStream =
      _events.receiveBroadcastStream().map((event) {
    if (event is Map) return TunnelStatusEvent.fromNative(event);
    return TunnelStatusEvent.unknownEmpty;
  }).handleError((Object e) {






    AppLog.I.error('[vpn] status stream error: $e');
  }).asBroadcastStream();

  Stream<TunnelStatusEvent> get onStatusChanged => _statusStream;









  void Function(String name, Map<String, dynamic> args)? _onAutomationAction;




  void registerAutomationActionHandler(
      void Function(String name, Map<String, dynamic> args) handler) {
    _onAutomationAction = handler;
    _methods.setMethodCallHandler(_handleNativeCall);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == _Methods.automationAction) {
      final handler = _onAutomationAction;
      if (handler == null) return null;
      try {
        final raw = (call.arguments as Map?) ?? const {};
        final name = raw['name'] as String? ?? '';
        final args = raw['args'] is Map
            ? Map<String, dynamic>.from(raw['args'] as Map)
            : <String, dynamic>{};
        if (name.isNotEmpty) handler(name, args);
      } catch (e) {
        AppLog.I.error('[automation] native call dispatch failed: $e');
      }
      return null;
    }
    return null;
  }



  Future<void> setAutomationEnabled(bool enabled) async {
    await _invoke<void>(
      _Methods.setAutomationEnabled,
      args: {'enabled': enabled},
      timeout: _Timeouts.settings,
      onTimeoutValue: null,
    );
  }






  void setAutomationActiveState({
    String? node,
    String? group,
    List<String>? nodes,
    List<String>? groups,
  }) {
    unawaited(_invoke<void>(
      _Methods.setAutomationActiveState,
      args: <String, dynamic>{
        'node': node,
        'group': group,


        'nodes': ?nodes,
        'groups': ?groups,
      },
      timeout: _Timeouts.settings,
      onTimeoutValue: null,
    ).catchError((Object e) {
      AppLog.I.error('[automation] setAutomationActiveState failed: $e');
    }));
  }




  void sendAutomationBroadcast(String action, Map<String, Object?> extras) {


    unawaited(_invoke<void>(
      _Methods.sendAutomationBroadcast,
      args: {'action': action, 'extras': extras},
      timeout: _Timeouts.settings,
      onTimeoutValue: null,
    ).catchError((Object e) {
      AppLog.I.error('[automation] sendAutomationBroadcast($action) failed: $e');
    }));
  }









  Future<T?> _invoke<T>(
    String method, {
    Map<String, dynamic>? args,
    required Duration timeout,
    required T? onTimeoutValue,
  }) async {
    try {
      return await _methods
          .invokeMethod<T>(method, args)
          .timeout(timeout);
    } on TimeoutException {
      AppLog.I.error(
        'BoxVpnClient: $method timed out after ${timeout.inSeconds}s',
      );
      return onTimeoutValue;
    }
  }
}






class MemoryInfo {
  const MemoryInfo({
    this.totalPss = 0,
    this.totalSwap = 0,
    this.javaHeap = 0,
    this.nativeHeap = 0,
    this.code = 0,
    this.stack = 0,
    this.graphics = 0,
    this.privateOther = 0,
    this.system = 0,
    this.nativeHeapAllocated = 0,
    this.nativeHeapSize = 0,
  });


  final int totalPss;
  final int totalSwap;
  final int javaHeap;
  final int nativeHeap;
  final int code;
  final int stack;
  final int graphics;
  final int privateOther;
  final int system;


  final int nativeHeapAllocated;
  final int nativeHeapSize;

  static int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);

  factory MemoryInfo.fromMap(Map<dynamic, dynamic> m) => MemoryInfo(
        totalPss: _int(m['totalPss']),
        totalSwap: _int(m['totalSwap']),
        javaHeap: _int(m['javaHeap']),
        nativeHeap: _int(m['nativeHeap']),
        code: _int(m['code']),
        stack: _int(m['stack']),
        graphics: _int(m['graphics']),
        privateOther: _int(m['privateOther']),
        system: _int(m['system']),
        nativeHeapAllocated: _int(m['nativeHeapAllocated']),
        nativeHeapSize: _int(m['nativeHeapSize']),
      );
}




final class CoreCheck {
  const CoreCheck({required this.ok, this.error = ''});
  final bool ok;
  final String error;
}
