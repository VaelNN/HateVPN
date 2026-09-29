import 'package:collection/collection.dart';























const kTlsPassthroughKeys = <String>[
  'disable_sni',
  'engine',
  'min_version',
  'max_version',
  'cipher_suites',
  'curve_preferences',
  'certificate',
  'certificate_path',
  'client_certificate',
  'client_certificate_path',
  'client_key',
  'client_key_path',
  'fragment',
  'fragment_fallback_delay',
  'record_fragment',
  'spoof',
  'spoof_method',
  'kernel_tx',
  'kernel_rx',
  'handshake_timeout',
  'ech',
];






const kTlsObjectKeys = <String>{'ech'};


const kTlsListableKeys = <String>{
  'cipher_suites',
  'curve_preferences',
  'certificate',
  'client_certificate',
  'client_key',
};


const kTlsBoolKeys = <String>{
  'disable_sni',
  'fragment',
  'record_fragment',
  'kernel_tx',
  'kernel_rx',
};





const kNaiveTlsPassthroughKeys = <String>{
  'certificate',
  'certificate_path',
  'ech',
};






const _kTlsEmitOrder = <String>[
  'enabled',


  'engine',
  'server_name',
  'alpn',
  'insecure',
  'disable_sni',
  'min_version',
  'max_version',
  'cipher_suites',
  'curve_preferences',
  'certificate',
  'certificate_path',
  'certificate_public_key_sha256',
  'client_certificate',
  'client_certificate_path',
  'client_key',
  'client_key_path',
  'fragment',
  'fragment_fallback_delay',
  'record_fragment',


  'spoof',
  'spoof_method',
  'kernel_tx',
  'kernel_rx',



  'handshake_timeout',
  'ech',
  'utls',
  'reality',
];

const _deepEq = DeepCollectionEquality();





class TlsSpec {
  final bool enabled;
  final String? serverName;
  final List<String> alpn;
  final bool insecure;
  final String? fingerprint;
  final RealitySpec? reality;







  final List<String> certificatePublicKeySha256;







  final Map<String, Object> passthrough;

  const TlsSpec({
    required this.enabled,
    this.serverName,
    this.alpn = const [],
    this.insecure = false,
    this.fingerprint,
    this.reality,
    this.certificatePublicKeySha256 = const [],
    this.passthrough = const {},
  });

  static const disabled = TlsSpec(enabled: false);





  Map<String, dynamic> toSingbox() {



    if (!enabled) return <String, dynamic>{};
    final typed = <String, dynamic>{'enabled': true};
    if (serverName != null && serverName!.isNotEmpty) {
      typed['server_name'] = serverName;
    }
    if (alpn.isNotEmpty) typed['alpn'] = List<String>.from(alpn);
    if (insecure) typed['insecure'] = true;
    if (certificatePublicKeySha256.isNotEmpty) {
      typed['certificate_public_key_sha256'] =
          List<String>.from(certificatePublicKeySha256);
    }
    if (fingerprint != null && fingerprint!.isNotEmpty) {
      typed['utls'] = {'enabled': true, 'fingerprint': fingerprint};
    } else if (fingerprint == '') {

      typed['utls'] = {'enabled': true};
    }
    if (reality != null) {
      typed['reality'] = reality!.toSingbox();
    }


    final m = <String, dynamic>{};
    for (final k in _kTlsEmitOrder) {
      final v = typed[k] ?? passthrough[k];
      if (v == null) continue;
      m[k] = v is List ? List<Object>.from(v) : v;
    }
    return m;
  }

  TlsSpec copyWith({
    bool? enabled,
    String? serverName,
    List<String>? alpn,
    bool? insecure,
    String? fingerprint,
    RealitySpec? reality,
    List<String>? certificatePublicKeySha256,
    Map<String, Object>? passthrough,
  }) =>
      TlsSpec(
        enabled: enabled ?? this.enabled,
        serverName: serverName ?? this.serverName,
        alpn: alpn ?? this.alpn,
        insecure: insecure ?? this.insecure,
        fingerprint: fingerprint ?? this.fingerprint,
        reality: reality ?? this.reality,
        certificatePublicKeySha256:
            certificatePublicKeySha256 ?? this.certificatePublicKeySha256,
        passthrough: passthrough ?? this.passthrough,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TlsSpec &&
          enabled == other.enabled &&
          serverName == other.serverName &&
          _listEq(alpn, other.alpn) &&
          insecure == other.insecure &&
          fingerprint == other.fingerprint &&
          reality == other.reality &&


          _listEq(certificatePublicKeySha256,
              other.certificatePublicKeySha256) &&
          _deepEq.equals(passthrough, other.passthrough));

  @override
  int get hashCode => Object.hash(
      enabled,
      serverName,
      Object.hashAll(alpn),
      insecure,
      fingerprint,
      reality,
      Object.hashAll(certificatePublicKeySha256),
      _deepEq.hash(passthrough));
}

class RealitySpec {
  final String publicKey;
  final String shortId;



  final String? keyShare;

  const RealitySpec({
    required this.publicKey,
    required this.shortId,
    this.keyShare,
  });

  Map<String, dynamic> toSingbox() => {
        'enabled': true,
        'public_key': publicKey,




        if (shortId.isNotEmpty) 'short_id': shortId,

        if (keyShare != null && keyShare!.isNotEmpty) 'key_share': keyShare,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RealitySpec &&
          publicKey == other.publicKey &&
          shortId == other.shortId &&
          keyShare == other.keyShare);

  @override
  int get hashCode => Object.hash(publicKey, shortId, keyShare);
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
