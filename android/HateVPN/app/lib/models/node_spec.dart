import '../services/contract/group_genus.dart';
import '../services/contract/registry.dart';
import 'auto_select.dart';
import 'body_delta.dart';
import 'emit_context.dart';
import 'node_entries.dart';
import 'node_spec_emit.dart' as e;
import 'node_warning.dart';
import 'singbox_entry.dart';
import 'tcp_keep_alive_spec.dart';
import 'template_vars.dart';
import 'tls_spec.dart';
import 'transport_spec.dart';

















Object? deepCopyJson(Object? value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final e in value.entries) e.key as String: deepCopyJson(e.value),
    };
  }
  if (value is List) return [for (final v in value) deepCopyJson(v)];
  return value;
}

sealed class NodeSpec {
  final String id;
  final String tag;
  final String label;
  final String server;
  final int port;








  final String rawSource;
  final NodeSpec? chained;
  final List<NodeWarning> warnings;






  final TcpKeepAliveSpec? tcpKeepAlive;





  String? sourceExtended;














  Map<String, dynamic>? patchedJson;





  BodyDelta? bodyDelta;




  List<String> ruleTrail = const [];




  bool get isAddressless => false;

  NodeSpec({
    required this.id,
    required this.tag,
    required this.label,
    required this.server,
    required this.port,
    required this.rawSource,
    this.chained,
    this.tcpKeepAlive,
    List<NodeWarning>? warnings,
  }) : warnings = warnings ?? <NodeWarning>[];














  SingboxEntry emit(TemplateVars vars) {
    final raw = emitRaw(vars);
    final delta = bodyDelta;
    if (delta != null) delta.applyTo(raw.map, deepCopyJson);
    final patch = patchedJson;
    if (patch == null) return raw;
    final copy = deepCopyJson(patch) as Map<String, dynamic>;
    return switch (raw) {
      Outbound() => Outbound(copy),
      Endpoint() => Endpoint(copy),
    };
  }



  SingboxEntry emitRaw(TemplateVars vars);


  String toUri();


  String get protocol;








  bool get isGroup => false;














  NodeEntries getEntries(EmitContext? ctx, {bool skipDetour = false}) {
    final vars = ctx?.vars ?? TemplateVars.empty;
    final self = emit(vars);
    if (skipDetour || chained == null) {
      return NodeEntries(main: self);
    }
    final childEntries = chained!.getEntries(ctx, skipDetour: skipDetour);
    final detours = <SingboxEntry>[childEntries.main, ...childEntries.detours];
    return NodeEntries(main: self, detours: detours);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NodeSpec &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          tag == other.tag);

  @override
  int get hashCode => Object.hash(runtimeType, id, tag);

  @override
  String toString() => '$runtimeType($tag @ $server:$port)';
}





final class VlessSpec extends NodeSpec {
  final String uuid;
  final String flow;
  final TlsSpec tls;
  final TransportSpec? transport;
  final String packetEncoding;





  final String encryption;

  VlessSpec({
    required super.id,
    required super.tag,
    required super.label,
    required super.server,
    required super.port,
    required super.rawSource,
    required this.uuid,
    this.flow = '',
    this.tls = TlsSpec.disabled,
    this.transport,
    this.packetEncoding = '',
    this.encryption = '',
    super.chained,
    super.tcpKeepAlive,
    super.warnings,
  });

  @override
  String get protocol => 'vless';

  @override
  SingboxEntry emitRaw(TemplateVars vars) => e.emitVless(this, vars);

  @override
  String toUri() => e.uriViaEngineRequired(this);
}





final class VmessSpec extends NodeSpec {
  final String uuid;
  final int alterId;
  final String security;
  final TlsSpec tls;
  final TransportSpec? transport;



  VmessSpec({
    required super.id,
    required super.tag,
    required super.label,
    required super.server,
    required super.port,
    required super.rawSource,
    required this.uuid,
    this.alterId = 0,
    this.security = 'auto',
    this.tls = TlsSpec.disabled,
    this.transport,
    super.chained,
    super.tcpKeepAlive,
    super.warnings,
  });

  @override
  String get protocol => 'vmess';

  @override
  SingboxEntry emitRaw(TemplateVars vars) => e.emitVmess(this, vars);

  @override
  String toUri() => e.uriViaEngineRequired(this);
}





final class TrojanSpec extends NodeSpec {
  final String password;
  final TlsSpec tls;
  final TransportSpec? transport;

  TrojanSpec({
    required super.id,
    required super.tag,
    required super.label,
    required super.server,
    required super.port,
    required super.rawSource,
    required this.password,
    this.tls = TlsSpec.disabled,
    this.transport,
    super.chained,
    super.tcpKeepAlive,
    super.warnings,
  });

  @override
  String get protocol => 'trojan';

  @override
  SingboxEntry emitRaw(TemplateVars vars) => e.emitTrojan(this, vars);

  @override
  String toUri() => e.uriViaEngineRequired(this);
}








final class AnyTlsSpec extends NodeSpec {
  final String password;
  final TlsSpec tls;
  final String idleSessionCheckInterval;
  final String idleSessionTimeout;
  final int? minIdleSession;

  AnyTlsSpec({
    required super.id,
    required super.tag,
    required super.label,
    required super.server,
    required super.port,
    required super.rawSource,
    required this.password,
    this.tls = TlsSpec.disabled,
    this.idleSessionCheckInterval = '',
    this.idleSessionTimeout = '',
    this.minIdleSession,
    super.chained,
    super.tcpKeepAlive,
    super.warnings,
  });

  @override
  String get protocol => 'anytls';

  @override
  SingboxEntry emitRaw(TemplateVars vars) => e.emitAnyTls(this, vars);

  @override
  String toUri() => e.uriViaEngineRequired(this);
}





final class ShadowsocksSpec extends NodeSpec {
  final String method;
  final String password;
  final String plugin;
  final String pluginOpts;

  ShadowsocksSpec({
    required super.id,
    required super.tag,
    required super.label,
    required super.server,
    required super.port,
    required super.rawSource,
    required this.method,
    required this.password,
    this.plugin = '',
    this.pluginOpts = '',
    super.chained,
    super.tcpKeepAlive,
    super.warnings,
  });

  @override
  String get protocol => 'shadowsocks';

  @override
  SingboxEntry emitRaw(TemplateVars vars) => e.emitShadowsocks(this, vars);

  @override
  String toUri() => e.uriViaEngineRequired(this);
}





final class Hysteria2Spec extends NodeSpec {
  final String password;





  final String obfs;
  final String obfsPassword;



  final int? obfsMinPacketSize;
  final int? obfsMaxPacketSize;
  final TlsSpec tls;
  final int? upMbps;
  final int? downMbps;






  final List<String>? serverPorts;

  Hysteria2Spec({
    required super.id,
    required super.tag,
    required super.label,
    required super.server,
    required super.port,
    required super.rawSource,
    required this.password,
    this.obfs = '',
    this.obfsPassword = '',
    this.obfsMinPacketSize,
    this.obfsMaxPacketSize,
    this.tls = TlsSpec.disabled,
    this.upMbps,
    this.downMbps,
    this.serverPorts,
    super.chained,
    super.warnings,
  });

  @override
  String get protocol => 'hysteria2';

  @override
  SingboxEntry emitRaw(TemplateVars vars) => e.emitHysteria2(this, vars);

  @override
  String toUri() => e.uriViaEngineRequired(this);
}












final class NaiveSpec extends NodeSpec {
  final String username;
  final String password;
  final TlsSpec tls;
  final Map<String, String> extraHeaders;





  final bool quic;

  NaiveSpec({
    required super.id,
    required super.tag,
    required super.label,
    required super.server,
    required super.port,
    required super.rawSource,
    this.username = '',
    this.password = '',
    this.tls = TlsSpec.disabled,
    this.extraHeaders = const {},
    this.quic = false,
    super.chained,
    super.tcpKeepAlive,
    super.warnings,
  });

  @override
  String get protocol => 'naive';

  @override
  SingboxEntry emitRaw(TemplateVars vars) => e.emitNaive(this, vars);

  @override
  String toUri() => e.uriViaEngineRequired(this);
}





final class TuicSpec extends NodeSpec {
  final String uuid;
  final String password;





  final String? congestionControl;
  final String? udpRelayMode;
  final bool zeroRtt;
  final TlsSpec tls;





  final String? heartbeat;

  TuicSpec({
    required super.id,
    required super.tag,
    required super.label,
    required super.server,
    required super.port,
    required super.rawSource,
    required this.uuid,
    required this.password,
    this.congestionControl,
    this.udpRelayMode,
    this.zeroRtt = false,
    this.tls = TlsSpec.disabled,
    this.heartbeat,
    super.chained,
    super.warnings,
  });

  @override
  String get protocol => 'tuic';

  @override
  SingboxEntry emitRaw(TemplateVars vars) => e.emitTuic(this, vars);

  @override
  String toUri() => e.uriViaEngineRequired(this);
}





final class SshSpec extends NodeSpec {
  final String user;
  final String password;
  final String privateKey;
  final String privateKeyPassphrase;
  final List<String> hostKey;
  final List<String> hostKeyAlgorithms;

  SshSpec({
    required super.id,
    required super.tag,
    required super.label,
    required super.server,
    required super.port,
    required super.rawSource,
    required this.user,
    this.password = '',
    this.privateKey = '',
    this.privateKeyPassphrase = '',
    this.hostKey = const [],
    this.hostKeyAlgorithms = const [],
    super.chained,
    super.tcpKeepAlive,
    super.warnings,
  });

  @override
  String get protocol => 'ssh';

  @override
  SingboxEntry emitRaw(TemplateVars vars) => e.emitSsh(this, vars);

  @override
  String toUri() => e.uriViaEngineRequired(this);
}





final class SocksSpec extends NodeSpec {
  final String version;
  final String username;
  final String password;

  SocksSpec({
    required super.id,
    required super.tag,
    required super.label,
    required super.server,
    required super.port,
    required super.rawSource,
    this.version = '5',
    this.username = '',
    this.password = '',
    super.chained,
    super.tcpKeepAlive,
    super.warnings,
  });

  @override
  String get protocol => 'socks';

  @override
  SingboxEntry emitRaw(TemplateVars vars) => e.emitSocks(this, vars);

  @override
  String toUri() => e.uriViaEngineRequired(this);
}





final class HttpSpec extends NodeSpec {
  final String username;
  final String password;
  final String path;
  final Map<String, String> headers;
  final TlsSpec tls;

  HttpSpec({
    required super.id,
    required super.tag,
    required super.label,
    required super.server,
    required super.port,
    required super.rawSource,
    this.username = '',
    this.password = '',
    this.path = '',
    this.headers = const {},
    this.tls = TlsSpec.disabled,
    super.chained,
    super.tcpKeepAlive,
    super.warnings,
  });

  @override
  String get protocol => 'http';

  @override
  SingboxEntry emitRaw(TemplateVars vars) => e.emitHttp(this, vars);

  @override
  String toUri() => e.uriViaEngineRequired(this);
}













class Awg {
  const Awg(this.fields);







  final Map<String, Object> fields;

  static const numKeys = <String>{
    'jc', 'jmin', 'jmax', 's1', 's2', 's3', 's4', 'h1', 'h2', 'h3', 'h4',
  };


  static const strKeys = <String>{
    'i1', 'i2', 'i3', 'i4', 'i5', 'id', 'ip', 'ib',
  };









  static const awg3RangeKeys = <String>{
    'content_padding_addition',
    'rekey_after_time',
    'rekey_timeout',
    'reject_after_time',
    'keepalive_timeout',
    'max_handshake_attempts',
  };



  static const awg3BoolKeys = <String>{'random_trailers', 'disable_cookies'};





  static const headerKey = 'header_protection_key';



  static const awg3MinPadding = 12;



  static const awg3WideHeaderRange = 65536;


  static const awg3JsonKeys = <String>{
    headerKey, ...awg3RangeKeys, ...awg3BoolKeys,
  };


  static String awg3Param(String jsonKey) => jsonKey.replaceAll('_', '');


  static final Map<String, String> awg3ParamToJson = {
    for (final k in awg3JsonKeys) awg3Param(k): k,
  };

  static final _uintRe = RegExp(r'^\d+$');
  static const _uint32Max = 0xFFFFFFFF;


  static int? _parseUint32(String s) {
    if (!_uintRe.hasMatch(s)) return null;
    final n = int.tryParse(s);
    return (n == null || n > _uint32Max) ? null : n;
  }






  static Object? parseAwg3Range(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    final n = _parseUint32(v);
    if (n != null) return n;
    final dash = v.indexOf('-');
    if (dash < 0) return null;
    final lo = _parseUint32(v.substring(0, dash).trim());
    final hi = _parseUint32(v.substring(dash + 1).trim());
    if (lo == null || hi == null || hi < lo) return null;
    return '$lo-$hi';
  }




  static bool? parseAwg3Bool(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'on':
      case 'true':
      case '1':
        return true;
      case '':
      case 'off':
      case 'false':
      case '0':
        return false;
      default:
        return null;
    }
  }




  static bool hasAwg3Params(Map<String, String> q) {
    for (final p in awg3ParamToJson.keys) {
      if ((q[p] ?? '').trim().isNotEmpty) return true;
    }
    return (q['keepalive'] ?? '').contains('-');
  }




  static bool hasAwg3Json(Map<String, dynamic> m) {
    if (awg3JsonKeys.any((k) => m[k] != null)) return true;
    final peers = m['peers'];
    if (peers is List) {
      for (final p in peers) {
        if (p is Map) {
          final ka = p['persistent_keepalive_interval'];
          if (ka is String && ka.contains('-')) return true;
        }
      }
    }
    return false;
  }


  bool get hasAwg3 => awg3JsonKeys.any(fields.containsKey);


  bool get hasHeaderKey =>
      (fields[headerKey] is String) && (fields[headerKey] as String).isNotEmpty;




  bool get randomTrailersWithWideHeaders {
    if (fields['random_trailers'] != true) return false;
    for (final k in headerKeys) {
      final v = fields[k];
      if (v is! String) continue;
      final dash = v.indexOf('-');
      if (dash < 0) continue;
      final lo = int.tryParse(v.substring(0, dash));
      final hi = int.tryParse(v.substring(dash + 1));
      if (lo == null || hi == null) continue;
      if (hi >= lo && hi - lo >= awg3WideHeaderRange) return true;
    }
    return false;
  }



  String? get paddingTooShortField {
    if (!hasHeaderKey) return null;
    for (final k in const ['s1', 's2', 's3', 's4']) {
      final v = fields[k];
      final n = v is int ? v : 0;
      if (n < awg3MinPadding) return k;
    }
    return null;
  }




  static const headerKeys = <String>{'h1', 'h2', 'h3', 'h4'};




  static final _headerRe = RegExp(r'^\d+(-\d+)?$');






  static Object? _parseHeader(String v) {
    if (!_headerRe.hasMatch(v)) return null;
    final n = int.tryParse(v);
    if (n != null) return n;
    final parts = v.split('-');
    final lo = int.parse(parts[0]);
    final hi = int.parse(parts[1]);
    return lo <= hi ? v : '$hi-$lo';
  }

  bool get isEmpty => fields.isEmpty;















  static void applyJunkSizeRequires(Map<String, Object> f,
      {List<String>? dropped}) {
    if (f.containsKey('jmin') && !f.containsKey('jmax')) {
      f.remove('jmin');
      dropped?.add('jmin');
    }
  }



  static Awg? fromJson(Map<String, dynamic> m) {
    final f = <String, Object>{};











    final hk = m[headerKey];
    if (hk is String && hk.trim().isNotEmpty) f[headerKey] = hk.trim();
    for (final k in awg3RangeKeys) {
      final v = m[k];
      if (v is num) {
        final n = v.toInt();
        if (n >= 0 && n <= _uint32Max) f[k] = n;
      } else if (v is String) {
        final r = parseAwg3Range(v);
        if (r != null) f[k] = r;
      }
    }
    for (final k in awg3BoolKeys) {
      if (m[k] == true) f[k] = true;
    }
    for (final k in numKeys) {
      final v = m[k];
      if (v is num) {
        f[k] = v.toInt();
      } else if (v is String && headerKeys.contains(k)) {
        final h = _parseHeader(v.trim());
        if (h != null) f[k] = h;
      }
    }
    for (final k in strKeys) {
      final v = m[k];
      if (v is String && v.isNotEmpty) f[k] = v;
    }


    applyJunkSizeRequires(f);
    return f.isEmpty ? null : Awg(f);
  }




  void writeInto(Map<String, dynamic> m) => m.addAll(fields);

}

class WireguardPeer {
  final String publicKey;
  final String preSharedKey;
  final String endpointHost;
  final int endpointPort;
  final List<String> allowedIps;



  final Object? persistentKeepalive;




  final List<int>? reserved;

  const WireguardPeer({
    required this.publicKey,
    this.preSharedKey = '',
    required this.endpointHost,
    required this.endpointPort,
    this.allowedIps = const ['0.0.0.0/0', '::/0'],
    this.persistentKeepalive,
    this.reserved,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WireguardPeer &&
          publicKey == other.publicKey &&
          preSharedKey == other.preSharedKey &&
          endpointHost == other.endpointHost &&
          endpointPort == other.endpointPort);

  @override
  int get hashCode =>
      Object.hash(publicKey, preSharedKey, endpointHost, endpointPort);
}

final class WireguardSpec extends NodeSpec {
  final String privateKey;
  final List<String> localAddresses;
  final List<WireguardPeer> peers;
  final int? mtu;


  final Awg? awg;

  WireguardSpec({
    required super.id,
    required super.tag,
    required super.label,
    required super.server,
    required super.port,
    required super.rawSource,
    required this.privateKey,
    required this.localAddresses,
    required this.peers,
    this.mtu,
    this.awg,
    super.chained,
    super.warnings,
  });

  @override
  String get protocol => 'wireguard';

  @override
  SingboxEntry emitRaw(TemplateVars vars) => e.emitWireguard(this, vars);

  @override
  String toUri() => e.uriViaEngineRequired(this);
}









final class MasqueSpec extends NodeSpec {

  final String privateKeyDer;


  final String publicKeyDer;


  final List<String> localAddresses;


  final String profile;







  final String vhttp;





  final String sni;



  final bool disableSni;

  final int? mtu;



  final String idleTimeout;



  final String keepAlive;




  final Map<String, Object> tlsExtra;

  MasqueSpec({
    required super.id,
    required super.tag,
    required super.label,
    required super.server,
    required super.port,
    required super.rawSource,
    required this.privateKeyDer,
    required this.publicKeyDer,
    required this.localAddresses,
    this.profile = 'cloudflare',
    this.vhttp = 'h3',
    this.sni = '',
    this.disableSni = false,
    this.mtu,
    this.idleTimeout = '',
    this.keepAlive = '',
    this.tlsExtra = const {},
    super.chained,
    super.warnings,
  });

  @override
  String get protocol => 'masque';

  @override
  SingboxEntry emitRaw(TemplateVars vars) => e.emitMasque(this, vars);

  @override
  String toUri() => e.uriViaEngineRequired(this);
}
















final class AutoSelectSpec extends NodeSpec {

  final AutoSelectMembership membership;


  final AutoSelectParams params;





  final String poolBadge;




  final Map<String, String> tagSynonyms;

  AutoSelectSpec({
    required super.id,
    required super.tag,
    required super.label,
    this.membership = const RuleMembers(),
    this.params = const AutoSelectParams(),
    this.tagSynonyms = const {},
    this.poolBadge = kDefaultPoolBadge,
    this.manualDefault = '',
    String? genus,
    this.sourceParamKeys,
    this.sourceMemberTags = const [],
    super.warnings,


    super.rawSource = '',
  })  : genus = genus ?? GroupGenus.auto,
        super(server: '', port: 0);




  final String genus;



  bool get isManual => genus == GroupGenus.manual;






  final Set<String>? sourceParamKeys;





  final List<String> sourceMemberTags;











  final String manualDefault;

  @override
  String get protocol => genus;

  @override
  bool get isGroup => true;

  @override
  bool get isAddressless => true;










  @override
  SingboxEntry emitRaw(TemplateVars vars) {
    final m = membership;
    final members = m is ExplicitMembers
        ? [for (final l in m.members) l.tag]
        : sourceMemberTags.toList();
    final all = params.toJson();
    final keys = sourceParamKeys;
    return Outbound({
      'tag': tag,
      'type': genus,
      'outbounds': members,
      if (isManual) ...{
        if (keys != null
            ? keys.contains(kInterruptKey)
            : params.interruptExistConnections)
          kInterruptKey: params.interruptExistConnections,
        if (manualDefault.isNotEmpty) 'default': manualDefault,
      } else
        for (final e in all.entries)
          if (keys == null || keys.contains(e.key)) e.key: e.value,
    });
  }


  static const String kInterruptKey = 'interrupt_exist_connections';





  SingboxEntry coreEntry(SingboxEntry emitted) {
    if (isManual || sourceParamKeys == null) return emitted;
    final map = emitted.map;
    final full = <String, dynamic>{
      'tag': map['tag'],
      'type': map['type'],
      'outbounds': map['outbounds'],
      ...params.toJson(),
      ...map,
    };
    return switch (emitted) {
      Outbound() => Outbound(full),
      Endpoint() => Endpoint(full),
    };
  }




  @override
  String toUri() => '';




  bool sameGroupAs(AutoSelectSpec other) =>
      tag == other.tag &&
      label == other.label &&
      membership == other.membership &&
      params == other.params &&
      poolBadge == other.poolBadge &&
      manualDefault == other.manualDefault &&
      genus == other.genus;

  AutoSelectSpec copyWith({
    String? tag,
    String? label,
    AutoSelectMembership? membership,
    AutoSelectParams? params,
    Map<String, String>? tagSynonyms,
    String? poolBadge,
    String? manualDefault,
    String? genus,
  }) =>
      AutoSelectSpec(
        id: id,
        tag: tag ?? this.tag,
        label: label ?? this.label,
        membership: membership ?? this.membership,
        params: params ?? this.params,
        tagSynonyms: tagSynonyms ?? this.tagSynonyms,
        poolBadge: poolBadge ?? this.poolBadge,
        manualDefault: manualDefault ?? this.manualDefault,
        genus: genus ?? this.genus,
        sourceParamKeys: sourceParamKeys,
        sourceMemberTags: sourceMemberTags,
        warnings: warnings,
        rawSource: rawSource,
      );
}
















final class TailscaleSpec extends NodeSpec {
  final Map<String, dynamic> body;

  TailscaleSpec({
    required super.id,
    required super.tag,
    required super.label,
    Map<String, dynamic> body = const {},
    super.rawSource = '',
    super.chained,
    super.warnings,
  })  : body = _stripMeta(body),
        super(server: '', port: 0);

  static Map<String, dynamic> _stripMeta(Map<String, dynamic> raw) {
    final copy = deepCopyJson(raw) as Map<String, dynamic>;
    copy
      ..remove('type')
      ..remove('tag')
      ..remove('detour');
    return copy;
  }

  @override
  String get protocol => 'tailscale';

  @override
  bool get isAddressless => true;

  @override
  SingboxEntry emitRaw(TemplateVars vars) => e.emitTailscale(this, vars);





  @override
  String toUri() => e.toUriTailscale(this);

  TailscaleSpec copyWith({
    String? tag,
    String? label,
    Map<String, dynamic>? body,
    NodeSpec? chained,
  }) =>
      TailscaleSpec(
        id: id,
        tag: tag ?? this.tag,
        label: label ?? this.label,
        body: body ?? this.body,
        rawSource: rawSource,
        chained: chained ?? this.chained,
        warnings: warnings,
      );
}






















final class UnknownTypeSpec extends NodeSpec {

  final String type;


  final Map<String, dynamic> body;

  UnknownTypeSpec({
    required super.id,
    required super.tag,
    required super.label,
    required this.type,
    required this.body,
    super.server = '',
    super.port = 0,
    super.rawSource = '',
    super.chained,
    super.warnings,
  });

  @override
  String get protocol => type;

  @override
  bool get isAddressless => server.isEmpty;

  @override
  SingboxEntry emitRaw(TemplateVars vars) {
    final map = <String, dynamic>{
      ...deepCopyJson(body) as Map<String, dynamic>,
      'type': type,
      'tag': tag,
    }..remove('detour');


    return ContractRegistry.I.isEndpointType(type)
        ? Endpoint(map)
        : Outbound(map);
  }

  @override
  String toUri() => rawSource;

  UnknownTypeSpec copyWith({String? tag, String? label, NodeSpec? chained}) =>
      UnknownTypeSpec(
        id: id,
        tag: tag ?? this.tag,
        label: label ?? this.label,
        type: type,
        body: body,
        server: server,
        port: port,
        rawSource: rawSource,
        chained: chained ?? this.chained,
        warnings: warnings,
      );
}

NodeSpec withChained(NodeSpec spec, NodeSpec chained) =>
    _withChainedTyped(spec, chained)..bodyDelta = spec.bodyDelta;

NodeSpec _withChainedTyped(NodeSpec spec, NodeSpec chained) => switch (spec) {
      TailscaleSpec s => s.copyWith(chained: chained),
      UnknownTypeSpec s => s.copyWith(chained: chained),
      VlessSpec s => VlessSpec(
          id: s.id,
          tag: s.tag,
          label: s.label,
          server: s.server,
          port: s.port,
          rawSource: s.rawSource,
          uuid: s.uuid,
          flow: s.flow,
          tls: s.tls,
          transport: s.transport,
          packetEncoding: s.packetEncoding,
          encryption: s.encryption,
          chained: chained,
          tcpKeepAlive: s.tcpKeepAlive,
          warnings: s.warnings,
        ),
      VmessSpec s => VmessSpec(
          id: s.id,
          tag: s.tag,
          label: s.label,
          server: s.server,
          port: s.port,
          rawSource: s.rawSource,
          uuid: s.uuid,
          alterId: s.alterId,
          security: s.security,
          tls: s.tls,
          transport: s.transport,
          chained: chained,
          tcpKeepAlive: s.tcpKeepAlive,
          warnings: s.warnings,
        ),
      TrojanSpec s => TrojanSpec(
          id: s.id,
          tag: s.tag,
          label: s.label,
          server: s.server,
          port: s.port,
          rawSource: s.rawSource,
          password: s.password,
          tls: s.tls,
          transport: s.transport,
          chained: chained,
          tcpKeepAlive: s.tcpKeepAlive,
          warnings: s.warnings,
        ),
      AnyTlsSpec s => AnyTlsSpec(
          id: s.id,
          tag: s.tag,
          label: s.label,
          server: s.server,
          port: s.port,
          rawSource: s.rawSource,
          password: s.password,
          tls: s.tls,
          idleSessionCheckInterval: s.idleSessionCheckInterval,
          idleSessionTimeout: s.idleSessionTimeout,
          minIdleSession: s.minIdleSession,
          chained: chained,
          tcpKeepAlive: s.tcpKeepAlive,
          warnings: s.warnings,
        ),
      ShadowsocksSpec s => ShadowsocksSpec(
          id: s.id,
          tag: s.tag,
          label: s.label,
          server: s.server,
          port: s.port,
          rawSource: s.rawSource,
          method: s.method,
          password: s.password,
          plugin: s.plugin,
          pluginOpts: s.pluginOpts,
          chained: chained,
          tcpKeepAlive: s.tcpKeepAlive,
          warnings: s.warnings,
        ),
      Hysteria2Spec s => Hysteria2Spec(
          id: s.id,
          tag: s.tag,
          label: s.label,
          server: s.server,
          port: s.port,
          rawSource: s.rawSource,
          password: s.password,
          obfs: s.obfs,
          obfsPassword: s.obfsPassword,
          obfsMinPacketSize: s.obfsMinPacketSize,
          obfsMaxPacketSize: s.obfsMaxPacketSize,
          tls: s.tls,
          upMbps: s.upMbps,
          downMbps: s.downMbps,
          chained: chained,
          warnings: s.warnings,
        ),
      NaiveSpec s => NaiveSpec(
          id: s.id,
          tag: s.tag,
          label: s.label,
          server: s.server,
          port: s.port,
          rawSource: s.rawSource,
          username: s.username,
          password: s.password,
          tls: s.tls,
          extraHeaders: s.extraHeaders,
          chained: chained,
          tcpKeepAlive: s.tcpKeepAlive,
          warnings: s.warnings,
        ),
      TuicSpec s => TuicSpec(
          id: s.id,
          tag: s.tag,
          label: s.label,
          server: s.server,
          port: s.port,
          rawSource: s.rawSource,
          uuid: s.uuid,
          password: s.password,
          congestionControl: s.congestionControl,
          udpRelayMode: s.udpRelayMode,
          zeroRtt: s.zeroRtt,
          tls: s.tls,
          heartbeat: s.heartbeat,
          chained: chained,
          warnings: s.warnings,
        ),
      SshSpec s => SshSpec(
          id: s.id,
          tag: s.tag,
          label: s.label,
          server: s.server,
          port: s.port,
          rawSource: s.rawSource,
          user: s.user,
          password: s.password,
          privateKey: s.privateKey,
          privateKeyPassphrase: s.privateKeyPassphrase,
          hostKey: s.hostKey,
          hostKeyAlgorithms: s.hostKeyAlgorithms,
          chained: chained,
          tcpKeepAlive: s.tcpKeepAlive,
          warnings: s.warnings,
        ),
      SocksSpec s => SocksSpec(
          id: s.id,
          tag: s.tag,
          label: s.label,
          server: s.server,
          port: s.port,
          rawSource: s.rawSource,
          version: s.version,
          username: s.username,
          password: s.password,
          chained: chained,
          tcpKeepAlive: s.tcpKeepAlive,
          warnings: s.warnings,
        ),
      HttpSpec s => HttpSpec(
          id: s.id,
          tag: s.tag,
          label: s.label,
          server: s.server,
          port: s.port,
          rawSource: s.rawSource,
          username: s.username,
          password: s.password,
          path: s.path,
          headers: s.headers,
          tls: s.tls,
          chained: chained,
          tcpKeepAlive: s.tcpKeepAlive,
          warnings: s.warnings,
        ),
      WireguardSpec s => WireguardSpec(
          id: s.id,
          tag: s.tag,
          label: s.label,
          server: s.server,
          port: s.port,
          rawSource: s.rawSource,
          privateKey: s.privateKey,
          localAddresses: s.localAddresses,
          peers: s.peers,
          mtu: s.mtu,
          awg: s.awg,
          chained: chained,
          warnings: s.warnings,
        ),
      MasqueSpec s => MasqueSpec(
          id: s.id,
          tag: s.tag,
          label: s.label,
          server: s.server,
          port: s.port,
          rawSource: s.rawSource,
          privateKeyDer: s.privateKeyDer,
          publicKeyDer: s.publicKeyDer,
          localAddresses: s.localAddresses,
          profile: s.profile,
          vhttp: s.vhttp,
          sni: s.sni,
          disableSni: s.disableSni,
          mtu: s.mtu,
          idleTimeout: s.idleTimeout,
          keepAlive: s.keepAlive,
          tlsExtra: s.tlsExtra,
          chained: chained,
          warnings: s.warnings,
        ),
      AutoSelectSpec s => s,
    };
