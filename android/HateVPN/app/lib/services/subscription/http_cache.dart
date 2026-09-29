import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';








class HttpCache {
  HttpCache._();

  static String _hash(String url) => url.hashCode.toRadixString(16);

  static Future<Directory> _dir() async {
    final root = await getApplicationSupportDirectory();
    final d = Directory('${root.path}/sub_cache');
    if (!d.existsSync()) await d.create(recursive: true);
    return d;
  }

  static Future<void> save(
    String url,
    String body,
    Map<String, String> headers,
  ) async {
    final dir = await _dir();
    final key = _hash(url);



    await _writeAtomic('${dir.path}/$key', body);
    await _writeAtomic('${dir.path}/$key.headers', jsonEncode(headers));
  }



  static int _tmpSeq = 0;

  static Future<void> _writeAtomic(String path, String content) async {
    final tmp = File('$path.${_tmpSeq++}.tmp');
    try {



      await tmp.parent.create(recursive: true);
      await tmp.writeAsString(content, flush: true);
      await tmp.rename(path);
    } catch (_) {


      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (_) {}
    }
  }

  static Future<String?> loadBody(String url) async {
    try {
      final dir = await _dir();
      final f = File('${dir.path}/${_hash(url)}');
      if (!f.existsSync()) return null;



      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, String>?> loadHeaders(String url) async {
    try {
      final dir = await _dir();
      final f = File('${dir.path}/${_hash(url)}.headers');
      if (!f.existsSync()) return null;
      final raw = await f.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
      return null;
    } catch (_) {
      return null;
    }
  }




  static Future<void> remove(String url) async {
    try {
      final dir = await _dir();
      final key = _hash(url);
      final body = File('${dir.path}/$key');
      final headers = File('${dir.path}/$key.headers');
      if (body.existsSync()) await body.delete();
      if (headers.existsSync()) await headers.delete();
    } catch (_) {

    }
  }
}
