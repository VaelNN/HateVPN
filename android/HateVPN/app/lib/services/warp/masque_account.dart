import '../parser/uri_utils.dart' show ensureCidr;













class MasqueAccount {
  const MasqueAccount({
    required this.privKeyDer,
    required this.serverPubDer,
    required this.clientV4,
    required this.clientV6,
    required this.server,
    required this.port,
    required this.deviceId,
    required this.token,
    required this.createdAt,
    this.sni = '',
    this.idleTimeout = '',
    this.keepAlive = '',
  });


  final String privKeyDer;


  final String serverPubDer;


  final String clientV4;


  final String clientV6;


  final String server;


  final int port;

  final String deviceId;


  final String token;


  final String createdAt;


  final String sni;


  final String idleTimeout;


  final String keepAlive;


  static const String defaultServer = '162.159.198.1';
  static const int defaultPort = 443;



  static String nodeTag() => '🔥🎭 WARP (MASQUE)';

  MasqueAccount copyWith({
    String? sni,
    String? idleTimeout,
    String? keepAlive,
  }) =>
      MasqueAccount(
        privKeyDer: privKeyDer,
        serverPubDer: serverPubDer,
        clientV4: clientV4,
        clientV6: clientV6,
        server: server,
        port: port,
        deviceId: deviceId,
        token: token,
        createdAt: createdAt,
        sni: sni ?? this.sni,
        idleTimeout: idleTimeout ?? this.idleTimeout,
        keepAlive: keepAlive ?? this.keepAlive,
      );






  String toMasqueUri({String vhttp = 'h3'}) {
    final addrs = [
      if (clientV4.isNotEmpty) ensureCidr(clientV4),
      if (clientV6.isNotEmpty) ensureCidr(clientV6),
    ].join(',');
    final q = <String, String>{
      'publickey': serverPubDer,
      'address': addrs,
      'profile': 'cloudflare',
      'vhttp': vhttp,
      'mtu': '1280',
      if (sni.isNotEmpty) 'sni': sni,
      if (idleTimeout.isNotEmpty) 'idle_timeout': idleTimeout,
      if (keepAlive.isNotEmpty) 'keep_alive': keepAlive,
    };
    final qs = q.entries
        .map((e) =>
            '${e.key}=${Uri.encodeQueryComponent(e.value).replaceAll('+', '%20')}')
        .join('&');
    return 'masque://${Uri.encodeQueryComponent(privKeyDer)}@$server:$port?$qs#${Uri.encodeComponent(nodeTag())}';
  }

  Map<String, Object?> toJson() => {
        'priv_key_der': privKeyDer,
        'server_pub_der': serverPubDer,
        'client_v4': clientV4,
        'client_v6': clientV6,
        'server': server,
        'port': port,
        'device_id': deviceId,
        'token': token,
        'created_at': createdAt,


        'sni': sni,
        'idle_timeout': idleTimeout,
        'keep_alive': keepAlive,
      };

  static MasqueAccount? fromJson(Map<String, dynamic> m) {
    final priv = m['priv_key_der'];
    final pub = m['server_pub_der'];
    if (priv is! String || priv.isEmpty || pub is! String || pub.isEmpty) {
      return null;
    }
    return MasqueAccount(
      privKeyDer: priv,
      serverPubDer: pub,
      clientV4: (m['client_v4'] as String?) ?? '',
      clientV6: (m['client_v6'] as String?) ?? '',
      server: (m['server'] as String?) ?? defaultServer,
      port: (m['port'] as num?)?.toInt() ?? defaultPort,
      deviceId: (m['device_id'] as String?) ?? '',
      token: (m['token'] as String?) ?? '',
      createdAt: (m['created_at'] as String?) ?? '',
      sni: (m['sni'] as String?) ?? '',
      idleTimeout: (m['idle_timeout'] as String?) ?? '',
      keepAlive: (m['keep_alive'] as String?) ?? '',
    );
  }


  Map<String, Object?> redacted() => {
        'server_pub_der': serverPubDer,
        'client_v4': clientV4,
        'client_v6': clientV6,
        'server': server,
        'port': port,
        'device_id': deviceId,
        'created_at': createdAt,
        'priv_key_der': '<redacted>',
        'token': '<redacted>',
      };
}
