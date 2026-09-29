import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';















class SupportState {
  SupportState._();
  static final SupportState I = SupportState._();

  Map<String, dynamic>? _cache;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/support_state.json');
  }

  Future<Map<String, dynamic>> _load() async {
    if (_cache != null) return _cache!;
    try {
      final f = await _file();
      if (!f.existsSync()) return _cache = <String, dynamic>{};
      final decoded = jsonDecode(await f.readAsString());
      return _cache =
          decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {


      return _cache = <String, dynamic>{};
    }
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(_cache), flush: true);
    } catch (_) {

    }
  }

  Future<int> getInt(String key) async =>
      ((await _load())[key] as num?)?.toInt() ?? 0;

  Future<String> getString(String key) async =>
      (await _load())[key] as String? ?? '';


  Future<Map<String, String>> getStringMap(String key) async {
    final v = (await _load())[key];
    if (v is! Map) return <String, String>{};
    return v.map((k, val) => MapEntry(k.toString(), val.toString()));
  }

  Future<void> set(String key, Object value) async {
    (await _load())[key] = value;
    await _save();
  }



  Future<void> setAll(Map<String, Object> values) async {
    (await _load()).addAll(values);
    await _save();
  }


  void resetCacheForTesting() => _cache = null;
}
