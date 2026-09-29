import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_log.dart';
import 'platform_channels.dart';
import 'project_links.dart';










enum InstallSource { github, play, fdroid }



class InstallSourceResolver {
  InstallSourceResolver._();

  static const _channel = MethodChannel(PlatformChannels.utils);







  static const _define = String.fromEnvironment('LXBOX_DISTRIBUTION');

  static InstallSource _current = InstallSource.github;
  static bool _initialized = false;



  static InstallSource get current => _current;


  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    if (_define.isNotEmpty) {
      final parsed = installSourceFromDefine(_define);
      if (parsed != null) {
        _current = parsed;
        return;
      }
      AppLog.I.warning(
          'InstallSource: unknown LXBOX_DISTRIBUTION="$_define" — using github');
      return;
    }
    String? installer;
    try {
      installer = await _channel.invokeMethod<String>('installSource');
    } catch (e) {

      AppLog.I.warning('InstallSource: native lookup failed ($e) — using github');
      return;
    }
    _current = installSourceFromInstaller(installer);
    AppLog.I.info(
        'InstallSource: installer=${installer ?? '<null>'} → ${_current.name}');
  }


  @visibleForTesting
  static void setForTest(InstallSource source) {
    _current = source;
    _initialized = true;
  }

  @visibleForTesting
  static void resetForTest() {
    _current = InstallSource.github;
    _initialized = false;
  }
}



InstallSource? installSourceFromDefine(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'github':
      return InstallSource.github;
    case 'play':
      return InstallSource.play;
    case 'fdroid':
      return InstallSource.fdroid;
    default:
      return null;
  }
}







InstallSource installSourceFromInstaller(String? pkg) {
  switch (pkg) {
    case 'com.android.vending':
      return InstallSource.play;



    case 'org.fdroid.fdroid':
    case 'org.fdroid.basic':
    case 'com.looker.droidify':
      return InstallSource.fdroid;
    default:
      return InstallSource.github;
  }
}

extension InstallSourceX on InstallSource {


  String get label => switch (this) {
        InstallSource.github => 'GitHub',
        InstallSource.play => 'Google Play',
        InstallSource.fdroid => 'F-Droid',
      };










  String updateUrl(String tag) => switch (this) {
        InstallSource.github => ProjectLinks.releaseTag(tag),
        InstallSource.play => ProjectLinks.playPage,
        InstallSource.fdroid => ProjectLinks.fdroidPage,
      };



  String? get updateUrlFallback => switch (this) {
        InstallSource.play => ProjectLinks.playPageWeb,
        InstallSource.github || InstallSource.fdroid => null,
      };





  String get pageUrl => switch (this) {
        InstallSource.github => ProjectLinks.latestRelease,
        InstallSource.play => ProjectLinks.playPage,
        InstallSource.fdroid => ProjectLinks.fdroidPage,
      };
}
