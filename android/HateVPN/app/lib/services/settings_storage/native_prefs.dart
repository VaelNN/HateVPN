part of '../settings_storage.dart';


















class NativePrefsKeys {
  static const autoStart = 'auto_start';
  static const keepOnExit = 'keep_on_exit';
  static const backgroundMode = 'background_mode';
  static const coreLogsEnabled = 'core_logs_enabled';
  static const coreLogsVerbose = 'core_logs_verbose';
  static const allowBypass = 'allow_bypass';
  static const autoRedirect = 'auto_redirect';
  static const memoryLimit = 'memory_limit';

  static const bools = <String>{
    autoStart,
    keepOnExit,
    coreLogsEnabled,
    coreLogsVerbose,
    allowBypass,
    autoRedirect,
  };
  static const all = <String>{
    autoStart,
    keepOnExit,
    backgroundMode,
    coreLogsEnabled,
    coreLogsVerbose,
    allowBypass,
    autoRedirect,
    memoryLimit,
  };
}




const Map<String, Object> _nativePrefsDefaults = {
  NativePrefsKeys.autoStart: false,
  NativePrefsKeys.keepOnExit: true,
  NativePrefsKeys.backgroundMode: 'never',
  NativePrefsKeys.coreLogsEnabled: false,
  NativePrefsKeys.coreLogsVerbose: false,
  NativePrefsKeys.allowBypass: false,
  NativePrefsKeys.autoRedirect: false,
  NativePrefsKeys.memoryLimit: MemoryLimitSetting.auto,
};


Future<Map<String, dynamic>> _getNativePrefs() async {
  final data = await _load();
  final raw = data['native_prefs'];
  if (raw is Map<String, dynamic>) return Map<String, dynamic>.from(raw);
  return Map<String, dynamic>.from(_nativePrefsDefaults);
}


Future<bool> _getNativeBool(String key) async {
  assert(NativePrefsKeys.bools.contains(key), 'not a bool native pref: $key');
  final p = await _getNativePrefs();
  final v = p[key];
  return v is bool ? v : (_nativePrefsDefaults[key] as bool);
}


Future<String> _getNativeBackgroundMode() async {
  final p = await _getNativePrefs();
  final v = p[NativePrefsKeys.backgroundMode];
  return v is String
      ? v
      : (_nativePrefsDefaults[NativePrefsKeys.backgroundMode] as String);
}



Future<void> _setNativeBool(String key, bool value) async {
  assert(NativePrefsKeys.bools.contains(key), 'not a bool native pref: $key');
  await _writeNativeJson(key, value);
  await _mirrorBoolToNative(key, value);
}


Future<void> _setNativeBackgroundMode(String wireValue) async {
  await _writeNativeJson(NativePrefsKeys.backgroundMode, wireValue);
  await BoxVpnClient().setBackgroundMode(BackgroundMode.fromNative(wireValue));
}


Future<String> _getNativeMemoryLimit() async {
  final p = await _getNativePrefs();
  final v = p[NativePrefsKeys.memoryLimit];
  return MemoryLimitSetting.normalize(v is String ? v : null);
}



Future<void> _setNativeMemoryLimit(String wireValue) async {
  final v = MemoryLimitSetting.normalize(wireValue);
  await _writeNativeJson(NativePrefsKeys.memoryLimit, v);
  await BoxVpnClient().setMemoryLimit(v);
}







Future<Map<String, dynamic>> _exportToBackupMap() async {
  final p = await _getNativePrefs();
  return {
    for (final key in NativePrefsKeys.all) key: p[key] ?? _nativePrefsDefaults[key],
  };
}





Future<int> _applyFromBackupMap(
  Map<String, dynamic> data, {
  void Function(String key, Object error)? onError,
}) async {
  var n = 0;
  for (final key in NativePrefsKeys.all) {
    if (!data.containsKey(key)) continue;
    try {
      if (key == NativePrefsKeys.backgroundMode) {

        await _setNativeBackgroundMode(
            BackgroundMode.fromNative(data[key]?.toString()).wireValue);
      } else if (key == NativePrefsKeys.memoryLimit) {

        await _setNativeMemoryLimit(
            MemoryLimitSetting.normalize(data[key]?.toString()));
      } else {
        await _setNativeBool(key, data[key] == true);
      }
      n++;
    } catch (e) {
      onError?.call(key, e);
    }
  }
  return n;
}



Future<void> _bootstrapAndSyncNativePrefs() async {
  final data = await _load();
  if (data['native_prefs'] is! Map<String, dynamic>) {
    await _bootstrapFromNative();
  } else {
    await _syncJsonToNative();
  }


  await _syncHasTunToNative();




  await _reconcileAppLanguageWithSystem();


  await _mirrorAppLanguageToNative(await SettingsStorage.getAppLanguage());
}



Future<void> _reconcileAppLanguageWithSystem() async {
  try {
    final state = await BoxVpnClient().getAppLanguageState();
    if (state == null) return;
    final stored = await SettingsStorage.getAppLanguage();
    switch (reconcileAppLanguage(stored: stored, state: state)) {
      case ReconcileSystemWins(:final newSetting):


        await SettingsStorage.setAppLanguage(newSetting);
      case ReconcileStorageWins():

        await _mirrorAppLanguageToNative(stored);
      case ReconcileNoop():
        break;
    }
  } catch (_) {

  }
}









Future<void> _mirrorAppLanguageToNative(String value) async {
  try {
    await BoxVpnClient().setAppLanguage(value);
  } catch (_) {

  }
}


Future<void> _setNativeHasTun(bool hasTun) =>
    BoxVpnClient().setHasTun(hasTun);

Future<void> _syncHasTunToNative() async {
  final cfg = await _getVpnMode();
  await BoxVpnClient().setHasTun(cfg.hasTun);
}


Future<void> _writeNativeJson(String key, Object value) async {
  final data = await _load();
  final section = (data['native_prefs'] is Map<String, dynamic>)
      ? Map<String, dynamic>.from(data['native_prefs'] as Map)
      : <String, dynamic>{};
  section[key] = value;
  data['native_prefs'] = section;
  SettingsStorage._cache = data;
  await _save();
}


Future<void> _mirrorBoolToNative(String key, bool value) async {
  final vpn = BoxVpnClient();
  switch (key) {
    case NativePrefsKeys.autoStart:
      await vpn.setAutoStart(value);
      break;
    case NativePrefsKeys.keepOnExit:
      await vpn.setKeepOnExit(value);
      break;
    case NativePrefsKeys.coreLogsEnabled:
      await vpn.setCoreLogsEnabled(value);
      break;
    case NativePrefsKeys.coreLogsVerbose:
      await vpn.setCoreLogsVerbose(value);
      break;
    case NativePrefsKeys.allowBypass:
      await vpn.setAllowBypass(value);
      break;
    case NativePrefsKeys.autoRedirect:
      await vpn.setAutoRedirect(value);
      break;
  }
}


Future<void> _bootstrapFromNative() async {
  final vpn = BoxVpnClient();
  final section = <String, dynamic>{
    NativePrefsKeys.autoStart: await vpn.getAutoStart(),
    NativePrefsKeys.keepOnExit: await vpn.getKeepOnExit(),
    NativePrefsKeys.backgroundMode: (await vpn.getBackgroundMode()).wireValue,
    NativePrefsKeys.coreLogsEnabled: await vpn.getCoreLogsEnabled(),
    NativePrefsKeys.coreLogsVerbose: await vpn.getCoreLogsVerbose(),
    NativePrefsKeys.allowBypass: await vpn.getAllowBypass(),
    NativePrefsKeys.autoRedirect: await vpn.getAutoRedirect(),
    NativePrefsKeys.memoryLimit: await vpn.getMemoryLimit(),
  };
  final data = await _load();
  data['native_prefs'] = section;
  SettingsStorage._cache = data;
  await _save();
}


Future<void> _syncJsonToNative() async {
  final vpn = BoxVpnClient();
  final json = await _getNativePrefs();
  for (final key in NativePrefsKeys.bools) {
    final want = json[key];
    if (want is! bool) continue;
    final have = await _nativeGetBool(vpn, key);
    if (have != want) await _mirrorBoolToNative(key, want);
  }
  final wantBg = json[NativePrefsKeys.backgroundMode];
  if (wantBg is String) {
    final haveBg = (await vpn.getBackgroundMode()).wireValue;
    if (haveBg != wantBg) {
      await vpn.setBackgroundMode(BackgroundMode.fromNative(wantBg));
    }
  }

  final wantMl = json[NativePrefsKeys.memoryLimit];
  if (wantMl is String) {
    final normMl = MemoryLimitSetting.normalize(wantMl);
    final haveMl = await vpn.getMemoryLimit();
    if (haveMl != normMl) await vpn.setMemoryLimit(normMl);
  }
}

Future<bool> _nativeGetBool(BoxVpnClient vpn, String key) async {
  switch (key) {
    case NativePrefsKeys.autoStart:
      return vpn.getAutoStart();
    case NativePrefsKeys.keepOnExit:
      return vpn.getKeepOnExit();
    case NativePrefsKeys.coreLogsEnabled:
      return vpn.getCoreLogsEnabled();
    case NativePrefsKeys.coreLogsVerbose:
      return vpn.getCoreLogsVerbose();
    case NativePrefsKeys.allowBypass:
      return vpn.getAllowBypass();
    case NativePrefsKeys.autoRedirect:
      return vpn.getAutoRedirect();
    default:
      return false;
  }
}
