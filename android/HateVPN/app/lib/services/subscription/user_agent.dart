import '../version_info.dart';



































const _kProductToken = 'LxBox-android';



final _uaSanitizeRe = RegExp(r'[()\s;]+');



String buildSubscriptionUserAgent({required String appVersion}) {
  final ver = _sanitizeToken(appVersion, fallback: 'unknown');
  return '$_kProductToken/$ver';
}




String _sanitizeToken(String raw, {required String fallback}) {
  var s = raw.trim();
  if (s.startsWith('v')) s = s.substring(1);
  s = s.replaceAll(_uaSanitizeRe, '');
  return s.isEmpty ? fallback : s;
}



String resolveSubscriptionUserAgent() =>
    buildSubscriptionUserAgent(appVersion: VersionInfo.I.version);
