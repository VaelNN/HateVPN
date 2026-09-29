import 'package:flutter/foundation.dart';

import 'app_log.dart';
import 'settings_storage.dart';
import 'stderr_reader.dart';














class CrashBannerState extends ChangeNotifier {
  CrashBannerState._();

  static final CrashBannerState I = CrashBannerState._();

  CrashReportFile? _pending;


  CrashReportFile? get pending => _pending;



  Future<void> refresh() async {
    try {
      final reports = await CrashReports.list();
      if (reports.isEmpty) {
        _set(null);
        return;
      }
      final latest = reports.first;
      final shown = await SettingsStorage.getShownCrashStamp();
      _set(CrashReports.stamp(latest) == shown ? null : latest);
    } catch (e) {
      AppLog.I.warning('Crash banner check failed: $e');
      _set(null);
    }
  }




  Future<void> markShown() async {
    final p = _pending;
    if (p == null) return;
    try {
      await SettingsStorage.setShownCrashStamp(CrashReports.stamp(p));
    } catch (e) {
      AppLog.I.warning('Crash banner stamp save failed: $e');
    }
    _set(null);
  }

  void _set(CrashReportFile? v) {
    if (_pending?.path == v?.path && _pending?.mtime == v?.mtime) return;
    _pending = v;
    notifyListeners();
  }

  @visibleForTesting
  void resetForTest() {
    _pending = null;
  }
}
