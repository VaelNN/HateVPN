import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../vpn/pprof_profile.dart';







class ProfileDumpWriter {
  ProfileDumpWriter._();


  static Future<String> writeProfile(PprofProfile p, Uint8List bytes) async {
    final file = File('${await _dir()}/${p.fileBase}-${_stamp()}.${p.fileExt}');
    await file.writeAsBytes(bytes);
    return file.path;
  }



  static Future<String> writeGoroutines(String text) async {
    final file = File('${await _dir()}/goroutines-${_stamp()}.txt');
    await file.writeAsString(text);
    return file.path;
  }


  static Future<String> writeCpuProfile(Uint8List bytes) async {
    final file = File('${await _dir()}/cpu-${_stamp()}.pb');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  static Future<String> _dir() async =>
      (await getTemporaryDirectory()).path;


  static String _stamp() =>
      DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
}
