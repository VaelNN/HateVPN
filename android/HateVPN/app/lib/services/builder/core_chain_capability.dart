






























import 'package:flutter/foundation.dart' show visibleForTesting;



const String kChainMinCoreVersion = '1.14.0-lx.27-rc.5';






class CoreVersion implements Comparable<CoreVersion> {
  const CoreVersion({
    required this.major,
    required this.minor,
    required this.patch,
    required this.lx,
    required this.rc,
  });

  final int major;
  final int minor;
  final int patch;


  final int lx;



  final int? rc;











  static CoreVersion? parse(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final m = _re.firstMatch(s.startsWith('v') ? s.substring(1) : s);
    if (m == null) return null;
    return CoreVersion(
      major: int.parse(m.group(1)!),
      minor: int.parse(m.group(2)!),
      patch: int.parse(m.group(3)!),
      lx: int.parse(m.group(4)!),
      rc: m.group(5) == null ? null : int.parse(m.group(5)!),
    );
  }


  static final RegExp _re =
      RegExp(r'^(\d+)\.(\d+)\.(\d+)-lx\.(\d+)(?:-rc\.(\d+))?');

  @override
  int compareTo(CoreVersion other) {
    for (final pair in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
      (lx, other.lx),
    ]) {
      final c = pair.$1.compareTo(pair.$2);
      if (c != 0) return c;
    }

    final a = rc, b = other.rc;
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  @override
  String toString() =>
      '$major.$minor.$patch-lx.$lx${rc == null ? '' : '-rc.$rc'}';
}





bool coreSupportsChain(String coreVersion) {
  final v = CoreVersion.parse(coreVersion);
  if (v == null) return true;
  final min = CoreVersion.parse(kChainMinCoreVersion)!;
  return v.compareTo(min) >= 0;
}











const String kCoreBuildTagsPin = 'v1.14.2-lx.8';

const Set<String> kCoreBuildTags = {
  'with_gvisor',
  'with_quic',
  'with_wireguard',
  'with_utls',
  'with_naive_outbound',
  'badlinkname',
  'tfogo_checklinkname0',
  'with_xhttp',
  'with_awg',
  'with_lx_command',
  'with_lx_idle_suspend',
  'with_lx_chain',
  'with_openvpn',
  'with_openconnect',
  'with_tailscale',
  'ts_omit_logtail',
  'ts_omit_ssh',
  'ts_omit_drive',
  'ts_omit_taildrop',
  'ts_omit_webclient',
  'ts_omit_doctor',
  'ts_omit_capture',
  'ts_omit_kube',
  'ts_omit_aws',
  'ts_omit_synology',
  'ts_omit_bird',
};







String chainUnsupportedByCoreLine(String tag, String coreVersion) {
  final shown = coreVersion.trim().isEmpty ? 'of unknown version' : coreVersion.trim();
  return 'Hop chain "$tag" was skipped: the VPN core ($shown) is older than '
      '$kChainMinCoreVersion and does not know the "chain" outbound type — '
      'it would reject the whole config. Update the app to get a newer core.';
}












class CoreVersionCache {
  CoreVersionCache._();

  static String _cached = '';


  static String get value => _cached;



  static Future<String> ensure(Future<String> Function() read) async {
    if (_cached.isNotEmpty) return _cached;
    try {
      final v = (await read()).trim();
      if (v.isNotEmpty) _cached = v;
      return v;
    } catch (_) {

      return '';
    }
  }

  @visibleForTesting
  static void resetForTest([String value = '']) => _cached = value;
}
