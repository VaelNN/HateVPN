import 'dart:convert';
import 'dart:typed_data';







class AppInfo {
  const AppInfo({
    required this.packageName,
    required this.appName,
    required this.isSystem,
    this.icon,
  });



  final String packageName;



  final String appName;


  final bool isSystem;



  final Uint8List? icon;




  factory AppInfo.fromMap(Map<String, dynamic> raw) {
    final iconStr = raw['icon'] as String? ?? '';
    Uint8List? bytes;
    if (iconStr.isNotEmpty) {
      try {
        bytes = base64Decode(iconStr);
      } catch (_) {

      }
    }
    final pkg = (raw['packageName'] as String?) ?? '';
    return AppInfo(
      packageName: pkg,
      appName: (raw['appName'] as String?) ?? pkg,
      isSystem: (raw['isSystemApp'] as bool?) ?? false,
      icon: bytes,
    );
  }
}
