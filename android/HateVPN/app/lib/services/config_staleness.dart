
























import 'dart:convert';

import 'platform_channels.dart';












class OverrideSnapshot {
  const OverrideSnapshot({
    this.includeSelfPackage = false,
    this.autoRedirect = false,
  });






  final bool includeSelfPackage;



  final bool autoRedirect;



  static const mirroredFields = <String>{
    'auto_redirect',
    'include_package',
  };
}




















String applyOverrides(String configJson, OverrideSnapshot override) {
  final Map<String, dynamic> config;
  try {
    final decoded = jsonDecode(configJson);
    if (decoded is! Map<String, dynamic>) return configJson;
    config = decoded;
  } catch (_) {
    return configJson;
  }

  final inbounds = config['inbounds'];
  if (inbounds is! List) return configJson;


  Map<String, dynamic>? tun;
  for (final i in inbounds) {
    if (i is Map<String, dynamic> && i['type'] == 'tun') {
      tun = i;
      break;
    }
  }
  if (tun == null) return configJson;







  tun['auto_redirect'] = override.autoRedirect;




  final isAllowMode = tun.containsKey('include_package');
  if (override.includeSelfPackage && isAllowMode) {

    final existing = tun['include_package'];
    final packages = <String>[
      if (existing is List) ...existing.map((e) => '$e')
      else if (existing is String) existing,
      PlatformChannels.packageName,
    ];
    tun['include_package'] = packages;
  }

  return jsonEncode(config);
}



enum StalenessVerdict {







  fresh,


  stale,




  unknown,
}










StalenessVerdict compareCanonical({
  required String? canonicalSaved,
  required String? runningSnapshot,
}) {
  if (canonicalSaved == null || canonicalSaved.isEmpty) {
    return StalenessVerdict.unknown;
  }
  if (runningSnapshot == null || runningSnapshot.isEmpty) {
    return StalenessVerdict.unknown;
  }
  return canonicalSaved == runningSnapshot
      ? StalenessVerdict.fresh
      : StalenessVerdict.stale;
}
