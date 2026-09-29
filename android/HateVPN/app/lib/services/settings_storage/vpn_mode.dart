part of '../settings_storage.dart';













Future<VpnModeConfig> _getVpnMode() async {
  final data = await _load();
  final raw = data['vpn_mode'];
  if (raw is Map<String, dynamic>) {
    final mode = raw['mode'];
    if (mode == SettingsStorage._vpnModeVpn ||
        mode == SettingsStorage._vpnModeProxy ||
        mode == SettingsStorage._vpnModeVpnProxy) {
      final port = raw['proxy_port'];
      final listen = raw['proxy_listen'];
      final proto = raw['proxy_protocol'];
      return VpnModeConfig(
        mode: mode as String,
        proxyProtocol: const {
          VpnModeConfig.protoMixed,
          VpnModeConfig.protoHttp,
          VpnModeConfig.protoSocks,
        }.contains(proto)
            ? proto as String
            : VpnModeConfig.protoMixed,
        proxyPort: (port is int) ? port : VpnModeConfig.defaultPort,

        proxyListen: (listen is String && VpnModeConfig.isValidListenAddr(listen))
            ? listen
            : VpnModeConfig.listenLocal,
        proxyAuthEnabled: raw['proxy_auth_enabled'] != false,
        proxyUsername:
            (raw['proxy_username'] as String?) ?? VpnModeConfig.defaultUsername,
        proxyPassword: (raw['proxy_password'] as String?) ?? '',
      );
    }
  }

  return const VpnModeConfig.defaults();
}

Future<void> _setVpnMode(VpnModeConfig cfg, {bool flush = true}) async {
  if (![
    SettingsStorage._vpnModeVpn,
    SettingsStorage._vpnModeProxy,
    SettingsStorage._vpnModeVpnProxy,
  ].contains(cfg.mode)) {
    throw ArgumentError('vpn_mode.mode must be vpn|proxy|vpn_proxy: ${cfg.mode}');
  }
  final data = await _load();
  data['vpn_mode'] = cfg.toJson();
  SettingsStorage._cache = data;
  SettingsStorage.markConfigDirty();
  if (flush) await _save();
}


class VpnModeConfig {
  const VpnModeConfig({
    required this.mode,
    required this.proxyProtocol,
    required this.proxyPort,
    required this.proxyListen,
    required this.proxyAuthEnabled,
    required this.proxyUsername,
    required this.proxyPassword,
  });


  const VpnModeConfig.defaults()
      : mode = 'vpn',
        proxyProtocol = protoMixed,
        proxyPort = defaultPort,
        proxyListen = listenLocal,
        proxyAuthEnabled = true,
        proxyUsername = defaultUsername,
        proxyPassword = '';

  static const int defaultPort = 2080;
  static const String listenLocal = '127.0.0.1';
  static const String listenPublic = '0.0.0.0';
  static const String defaultUsername = 'user';



  static bool isValidListenAddr(String addr) {
    final parts = addr.split('.');
    if (parts.length != 4) return false;
    for (final p in parts) {
      if (p.isEmpty || p.length > 3) return false;
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }


  static bool isLoopback(String addr) => addr.startsWith('127.');





  static bool isValidPort(int port) => port >= 1024 && port <= 65535;


  static bool isValidProtocol(String proto) =>
      proto == protoMixed || proto == protoHttp || proto == protoSocks;



  static const String protoMixed = 'mixed';
  static const String protoHttp = 'http';
  static const String protoSocks = 'socks';


  final String mode;


  final String proxyProtocol;
  final int proxyPort;



  final String proxyListen;
  final bool proxyAuthEnabled;
  final String proxyUsername;
  final String proxyPassword;

  bool get isVpn => mode == 'vpn';
  bool get isProxy => mode == 'proxy';
  bool get isVpnProxy => mode == 'vpn_proxy';


  bool get hasTun => mode != 'proxy';


  bool get hasMixed => mode != 'vpn';



  bool get isPublicListen => !isLoopback(proxyListen);


  bool get effectiveAuth => isPublicListen ? true : proxyAuthEnabled;

  VpnModeConfig copyWith({
    String? mode,
    String? proxyProtocol,
    int? proxyPort,
    String? proxyListen,
    bool? proxyAuthEnabled,
    String? proxyUsername,
    String? proxyPassword,
  }) =>
      VpnModeConfig(
        mode: mode ?? this.mode,
        proxyProtocol: proxyProtocol ?? this.proxyProtocol,
        proxyPort: proxyPort ?? this.proxyPort,
        proxyListen: proxyListen ?? this.proxyListen,
        proxyAuthEnabled: proxyAuthEnabled ?? this.proxyAuthEnabled,
        proxyUsername: proxyUsername ?? this.proxyUsername,
        proxyPassword: proxyPassword ?? this.proxyPassword,
      );

  Map<String, Object?> toJson() => {
        'mode': mode,
        'proxy_protocol': proxyProtocol,
        'proxy_port': proxyPort,
        'proxy_listen': proxyListen,
        'proxy_auth_enabled': proxyAuthEnabled,
        'proxy_username': proxyUsername,
        'proxy_password': proxyPassword,
      };
}
