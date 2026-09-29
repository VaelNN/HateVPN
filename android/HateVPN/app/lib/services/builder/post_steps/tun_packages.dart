part of '../post_steps.dart';
















void applyTunPackages(Map<String, dynamic> config, TunAppsConfig tunApps) {
  if (tunApps.isOff || tunApps.packages.isEmpty) return;

  final inbounds = config['inbounds'];
  if (inbounds is! List) return;

  Map<String, dynamic>? tun;
  for (final i in inbounds) {
    if (i is Map<String, dynamic> && i['type'] == 'tun') {
      tun = i;
      break;
    }
  }
  if (tun == null) return;

  final field = tunApps.isAllow ? 'include_package' : 'exclude_package';
  tun[field] = List<String>.from(tunApps.packages);
}
