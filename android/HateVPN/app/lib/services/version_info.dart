import 'package:package_info_plus/package_info_plus.dart';













class VersionInfo {
  VersionInfo._();
  static final VersionInfo I = VersionInfo._();

  String _version = '0.0.0';
  String _buildNumber = '0';
  bool _initialized = false;



  Future<void> init() async {
    if (_initialized) return;
    try {
      final info = await PackageInfo.fromPlatform();
      _version = info.version;
      _buildNumber = info.buildNumber;
    } catch (_) {

    }
    _initialized = true;
  }



  String get version => _version;



  String get buildNumber => _buildNumber;


  String get versionAndBuild => '$_version+$_buildNumber';
}
