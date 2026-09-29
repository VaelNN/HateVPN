import '../../models/node_spec.dart' show Awg;
import '../parser/uri_utils.dart' show parseReserved;







class WarpAccount {
  const WarpAccount({
    required this.privKey,
    required this.peerPub,
    required this.clientV4,
    required this.clientV6,
    required this.clientId,
    required this.accountId,
    required this.deviceId,
    required this.token,
    required this.endpoint,
    required this.createdAt,
    this.license,
    this.warpPlus = false,
    this.awg,
  });



  final String privKey;


  final String peerPub;


  final String clientV4;


  final String clientV6;



  final String clientId;

  final String accountId;
  final String deviceId;


  final String token;


  final String endpoint;


  final String createdAt;


  final String? license;


  final bool warpPlus;




  final Awg? awg;

  static const String defaultEndpoint = 'engage.cloudflareclient.com:2408';




  static String nodeTag({required bool warpPlus, required bool hasAwg}) {
    final plus = warpPlus ? '+' : '';
    return hasAwg ? '🔥⛈️ WARP$plus (AWG 1.5)' : '🔥☁️ WARP$plus';
  }


  List<int>? get reserved => parseReserved(clientId);


  WarpAccount copyWith({
    String? license,
    bool? warpPlus,
    String? endpoint,
    Awg? awg,
    bool clearAwg = false,
  }) =>
      WarpAccount(
        privKey: privKey,
        peerPub: peerPub,
        clientV4: clientV4,
        clientV6: clientV6,
        clientId: clientId,
        accountId: accountId,
        deviceId: deviceId,
        token: token,
        endpoint: endpoint ?? this.endpoint,
        createdAt: createdAt,
        license: license ?? this.license,
        warpPlus: warpPlus ?? this.warpPlus,
        awg: clearAwg ? null : (awg ?? this.awg),
      );















  String toWireguardUri({bool includeReserved = true, int? persistentKeepalive}) {
    final res = includeReserved ? reserved : null;
    final addrs = [clientV4, if (clientV6.isNotEmpty) clientV6].join(',');

    final tag = nodeTag(warpPlus: warpPlus, hasAwg: false);
    final q = <String, String>{
      'publickey': peerPub,
      'address': addrs,
      'allowedips': '0.0.0.0/0,::/0',
      'mtu': '1280',
      if (res != null) 'reserved': res.join(','),
      if (persistentKeepalive != null && persistentKeepalive > 0)
        'keepalive': '$persistentKeepalive',
    };
    final qs = q.entries
        .map((e) =>
            '${e.key}=${Uri.encodeQueryComponent(e.value).replaceAll('+', '%20')}')
        .join('&');
    return 'wireguard://${Uri.encodeQueryComponent(privKey)}@$endpoint?$qs#${Uri.encodeComponent(tag)}';
  }
















  String toWireguardConf({bool includeReserved = true, int? persistentKeepalive}) {
    final res = includeReserved ? reserved : null;
    final tag = warpPlus ? 'WARP+' : 'WARP';
    final addrs = [clientV4, if (clientV6.isNotEmpty) clientV6].join(', ');
    final b = StringBuffer()
      ..writeln('# $tag (Amnezia 1.5 obfuscation)')
      ..writeln('[Interface]')
      ..writeln('PrivateKey = $privKey')
      ..writeln('Address = $addrs')
      ..writeln('MTU = 1280');


    final awgFields = awg?.fields;
    if (awgFields != null) {

      final keys = awgFields.keys.toList()..sort();
      for (final k in keys) {
        final v = awgFields[k];

        final name = Awg.awg3JsonKeys.contains(k)
            ? Awg.awg3Param(k).toUpperCase()
            : k.toUpperCase();
        b.writeln('$name = ${v is bool ? 'on' : v}');
      }
    }
    b
      ..writeln()
      ..writeln('[Peer]')
      ..writeln('PublicKey = $peerPub')
      ..writeln('AllowedIPs = 0.0.0.0/0, ::/0')
      ..writeln('Endpoint = $endpoint');
    if (persistentKeepalive != null && persistentKeepalive > 0) {
      b.writeln('PersistentKeepalive = $persistentKeepalive');
    }
    if (res != null) {
      b.writeln('Reserved = ${res.join(',')}');
    }
    return b.toString();
  }



  Map<String, Object?> toJson() => {
        'priv_key': privKey,
        'peer_pub': peerPub,
        'client_v4': clientV4,
        'client_v6': clientV6,
        'client_id': clientId,
        'account_id': accountId,
        'device_id': deviceId,
        'token': token,
        'endpoint': endpoint,
        'created_at': createdAt,
        'license': license,
        'warp_plus': warpPlus,
        if (awg != null) 'awg': Map<String, Object>.from(awg!.fields),
      };

  static WarpAccount? fromJson(Map<String, dynamic> m) {
    final priv = m['priv_key'];
    final pub = m['peer_pub'];
    if (priv is! String || priv.isEmpty || pub is! String || pub.isEmpty) {
      return null;
    }
    return WarpAccount(
      privKey: priv,
      peerPub: pub,
      clientV4: (m['client_v4'] as String?) ?? '',
      clientV6: (m['client_v6'] as String?) ?? '',
      clientId: (m['client_id'] as String?) ?? '',
      accountId: (m['account_id'] as String?) ?? '',
      deviceId: (m['device_id'] as String?) ?? '',
      token: (m['token'] as String?) ?? '',
      endpoint: (m['endpoint'] as String?) ?? defaultEndpoint,
      createdAt: (m['created_at'] as String?) ?? '',
      license: m['license'] as String?,
      warpPlus: m['warp_plus'] == true,
      awg: m['awg'] is Map
          ? Awg.fromJson(Map<String, dynamic>.from(m['awg'] as Map))
          : null,
    );
  }


  Map<String, Object?> redacted() => {
        'peer_pub': peerPub,
        'client_v4': clientV4,
        'client_v6': clientV6,
        'client_id': clientId,
        'account_id': accountId,
        'device_id': deviceId,
        'endpoint': endpoint,
        'created_at': createdAt,
        'warp_plus': warpPlus,
        'obfuscated': awg != null,
        'priv_key': '<redacted>',
        'token': '<redacted>',
        'license': license == null ? null : '<redacted>',
      };
}
