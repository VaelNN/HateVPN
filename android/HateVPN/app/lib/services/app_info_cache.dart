import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/app_info.dart';
import '../vpn/box_vpn_client.dart';


























class AppInfoCache {
  AppInfoCache._();

  static final _cache = <String, AppInfo?>{};
  static final _inFlight = <String>{};



  static final _attempts = <String, int>{};

  static const List<Duration> _defaultRetryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
  ];



  @visibleForTesting
  static List<Duration> retryDelays = _defaultRetryDelays;



  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static final BoxVpnClient _vpn = BoxVpnClient();



  static List<AppInfo>? _allApps;
  static bool _allLoading = false;


  static AppInfo? of(String pkg) => _cache[pkg];




  static bool isNotFound(String pkg) =>
      _cache.containsKey(pkg) && _cache[pkg] == null;











  static void ensure(String pkg) {
    if (pkg.isEmpty) return;
    if (_inFlight.contains(pkg)) return;
    if (_cache.containsKey(pkg)) {
      final existing = _cache[pkg];
      if (existing == null) return;
      if (existing.icon != null) return;
      _inFlight.add(pkg);
      unawaited(_fetchIcon(pkg, existing));
      return;
    }
    _inFlight.add(pkg);
    unawaited(_fetch(pkg));
  }






  static Future<List<AppInfo>> loadAllApps() async {
    if (_allApps != null) return _allApps!;
    if (_allLoading) {
      while (_allLoading) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return _allApps ?? const <AppInfo>[];
    }
    _allLoading = true;
    try {
      final apps = await _vpn.getInstalledApps()
        ..sort((a, b) =>
            a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));



      var changed = false;
      for (final a in apps) {
        if (a.packageName.isEmpty) continue;
        _cache[a.packageName] = a;
        _inFlight.remove(a.packageName);
        _attempts.remove(a.packageName);
        changed = true;
      }
      _allApps = apps;
      if (changed) revision.value = revision.value + 1;
      return apps;
    } finally {
      _allLoading = false;
    }
  }

  static Future<void> _fetch(String pkg) async {
    AppInfo? info;
    var verified = false;
    try {


      info = await _vpn.getAppInfo(pkg);
      verified = true;
    } catch (_) {



    }
    if (!verified) {
      _inFlight.remove(pkg);
      _scheduleRetry(pkg);
      return;
    }
    _attempts.remove(pkg);
    _cache[pkg] = info;
    if (info == null) {
      _inFlight.remove(pkg);
      revision.value = revision.value + 1;
      return;
    }


    revision.value = revision.value + 1;
    await _fetchIcon(pkg, info);
  }





  static void _scheduleRetry(String pkg) {
    final n = (_attempts[pkg] ?? 0) + 1;
    _attempts[pkg] = n;
    if (n > retryDelays.length) return;
    unawaited(Future.delayed(retryDelays[n - 1], () {


      if (_cache.containsKey(pkg) || _inFlight.contains(pkg)) return;
      _inFlight.add(pkg);
      unawaited(_fetch(pkg));
    }));
  }



  static Future<void> _fetchIcon(String pkg, AppInfo existing) async {
    try {
      final b64 = await _vpn.getAppIcon(pkg);
      Uint8List? bytes;
      if (b64.isNotEmpty) {
        try {
          bytes = base64Decode(b64);
        } catch (_) {}
      }
      _cache[pkg] = AppInfo(
        packageName: existing.packageName,
        appName: existing.appName,
        isSystem: existing.isSystem,
        icon: bytes,
      );
    } catch (_) {

    } finally {
      _inFlight.remove(pkg);
      revision.value = revision.value + 1;
    }
  }


  @visibleForTesting
  static void resetForTest() {
    _cache.clear();
    _inFlight.clear();
    _attempts.clear();
    _allApps = null;
    _allLoading = false;
    retryDelays = _defaultRetryDelays;
    revision.value = 0;
  }
}
