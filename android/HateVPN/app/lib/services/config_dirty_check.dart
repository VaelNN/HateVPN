import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../vpn/box_vpn_client.dart';



















class ConfigDirtyCheck {
  static const _settingsFileName = 'lxbox_settings.json';
  static const _singboxConfigFileName = 'singbox_config.json';




  static String? _filesDirCache;




  static Future<Directory> _configDir() async {
    final cached = _filesDirCache;
    if (cached != null) return Directory(cached);
    final native = await BoxVpnClient().getFilesDir();
    if (native != null && native.isNotEmpty) {
      _filesDirCache = native;
      return Directory(native);
    }
    return getApplicationDocumentsDirectory();
  }



  static void resetForTesting() {
    _filesDirCache = null;
  }



  static Future<DateTime?> settingsModifiedTime() async {
    return _mtimeOf(getApplicationDocumentsDirectory(), _settingsFileName);
  }



  static Future<DateTime?> configModifiedTime() async {
    return _mtimeOf(_configDir(), _singboxConfigFileName);
  }













  static Future<bool> isDirty() async {
    final s = await settingsModifiedTime();
    final c = await configModifiedTime();
    if (s == null) return false;
    if (c == null) return true;






    return _floorToSecond(s).isAfter(_floorToSecond(c));
  }

  static DateTime _floorToSecond(DateTime t) =>
      DateTime.fromMillisecondsSinceEpoch(
          (t.millisecondsSinceEpoch ~/ 1000) * 1000,
          isUtc: t.isUtc);

  static Future<DateTime?> _mtimeOf(
      Future<Directory> dir, String fileName) async {
    try {
      final f = File('${(await dir).path}/$fileName');
      if (!await f.exists()) return null;
      final stat = await f.stat();
      return stat.modified;
    } catch (_) {

      return null;
    }
  }















  static Future<void> touchConfig() async {
    try {
      final settingsMtime = await settingsModifiedTime();
      if (settingsMtime == null) return;
      final dir = await _configDir();
      final f = File('${dir.path}/$_singboxConfigFileName');
      if (await f.exists()) {
        await f.setLastModified(settingsMtime);
      }
    } catch (_) {

    }
  }
}
