import 'dart:convert';

import '../../models/auto_select.dart';
import '../../models/direction.dart' show UrltestMode;
import '../../models/node_spec.dart';
import '../../models/node_warning.dart';
import '../../models/tls_spec.dart';
import '../../models/template_vars.dart';
import '../../models/transport_spec.dart';
import '../contract/group_genus.dart';
import '../contract/registry.dart' show awgMtuCeilingByRegistry;
import '../node_hash.dart';
import '../safe_regex.dart';
import 'engine/engine_mapper.dart' show mapJsonViaEngine;
import 'mappers/uri_pipeline.dart'
    show parseXrayViaPipeline;
import '../contract/body_sanitizer.dart' show BodySource;
import 'body_delta_builder.dart';
import 'drop_verdict.dart';
import 'tcp_keep_alive.dart';
import 'transport.dart';
import 'uri_utils.dart';
import 'utls_fingerprint.dart';







const kXrayServiceProtocols = {'freedom', 'blackhole', 'dns', 'loopback'};



































List<NodeSpec> parseXrayElement(
  Map<String, dynamic> element, {
  Set<String>? seen,
  Map<String, String>? synonyms,
  bool Function(String signature)? ownedBy,
  List<NodeWarning>? dropped,
}) {
  final outbounds = element['outbounds'];
  if (outbounds is! List) return const [];




  final payloadAll = outbounds
      .whereType<Map<String, dynamic>>()
      .where(
        (o) =>
            !kXrayServiceProtocols.contains(o['protocol']?.toString() ?? ''),
      )
      .toList();
  if (payloadAll.isEmpty) return const [];





  final byTag = <String, Map<String, dynamic>>{};
  for (final o in outbounds.whereType<Map<String, dynamic>>()) {
    final t = o['tag']?.toString() ?? '';


    if (t.isNotEmpty) byTag.putIfAbsent(t, () => o);
  }


  final dialerRefOf = <Map<String, dynamic>, String>{};
  final dialerTargets = <String>{};
  for (final ob in payloadAll) {


    final stream = ob['streamSettings'];
    final sockopt = stream is Map ? stream['sockopt'] : null;
    final ref = sockopt is Map ? sockopt['dialerProxy']?.toString() : null;
    if (ref != null && ref.isNotEmpty) {
      dialerRefOf[ob] = ref;
      dialerTargets.add(ref);
    }
  }


















  bool inDialerCycle(Map<String, dynamic> ob) {
    final start = ob['tag']?.toString() ?? '';
    if (start.isEmpty) return false;
    final seenTags = <String>{start};
    var ref = dialerRefOf[ob];
    while (ref != null && ref.isNotEmpty) {
      if (ref == start) return true;
      if (!seenTags.add(ref)) return false;
      final next = byTag[ref];
      if (next == null) return false;
      ref = dialerRefOf[next];
    }
    return false;
  }

  final candidates = payloadAll
      .where((o) =>
          !dialerTargets.contains(o['tag']?.toString()) || inDialerCycle(o))
      .toList();
  if (candidates.isEmpty) return const [];
  final mainIdx = candidates.indexWhere((o) => dialerRefOf.containsKey(o)) >= 0
      ? candidates.indexWhere((o) => dialerRefOf.containsKey(o))
      : (candidates.indexWhere((o) => o['tag'] == 'proxy') >= 0
            ? candidates.indexWhere((o) => o['tag'] == 'proxy')
            : 0);
  final ordered = [
    candidates[mainIdx],
    for (var i = 0; i < candidates.length; i++)
      if (i != mainIdx) candidates[i],
  ];

  final remarks = element['remarks']?.toString() ?? '';
  final extended = _prettyJson(element);







  final elRouting = element['routing'];
  final elBalancers = elRouting is Map ? elRouting['balancers'] : null;
  final hasBalancer = elBalancers is List && elBalancers.isNotEmpty;




  final soloNode = !hasBalancer && ordered.length == 1;


  final tagUses = <String, int>{};
  for (final ob in ordered) {
    final t = ob['tag']?.toString().trim() ?? '';
    if (t.isNotEmpty) tagUses[t] = (tagUses[t] ?? 0) + 1;
  }

  final result = <NodeSpec>[];


  final memberTagByObTag = <String, String>{};




  for (var i = 0; i < ordered.length; i++) {
    final ob = ordered[i];

    final obTag = ob['tag']?.toString() ?? '';
    try {





      final identity = _xrayIdentity(ob);
      if (identity != null && obTag.isNotEmpty) synonyms?[obTag] = identity;






      final label = _elementLabel(
        remarks: remarks,
        ob: ob,
        index: i,
        solo: soloNode,
        tagUses: tagUses,
      );









      final compact = _prettyJson(ob);
      final verdict = XrayDropVerdict();
      var spec = _xrayToSpec(ob, label,
          dropped: verdict, rawSource: compact, document: outbounds);
      if (spec == null && verdict.explicit) {


        final r = verdict.reason;
        final w = RegistryWarning(
          code: r?.code ?? 'type_invalid',
          path: r?.path,
          value: r?.value,
          params: r?.params ?? const {},
          ownerTag: obTag,
        );
        dropped?.add(w);
        continue;
      }



      if (spec == null) {
        dropped?.add(_unreadEntry(verdict.reason, ob, obTag));
        continue;
      }






      final ref = dialerRefOf[ob];
      NodeSpec? chained;
      if (ref != null) {




        if (_isXrayFreedom(byTag[ref])) {

        } else {
          chained = _xrayBuildChain(ob, byTag, ref, outbounds);



          if (chained == null) {




            dropped?.add(
                DialerProxyUnusableWarning(label, ref, ownerTag: obTag));
            continue;
          }
        }
      }

      final node = chained == null ? spec : withChained(spec, chained);



      final signature = nodeDedupSignature(node);



      if (ownedBy != null && !ownedBy(signature)) continue;
      if (seen != null) {
        if (seen.contains(signature)) continue;
        seen.add(signature);
      }

      if (obTag.isNotEmpty) memberTagByObTag.putIfAbsent(obTag, () => node.tag);
      result.add(node..sourceExtended = extended == compact ? null : extended);
    } catch (_) {





      dropped?.add(RegistryWarning(code: 'form_unrecognized', ownerTag: obTag));
    }
  }






  final localSyn = <String, String>{};
  for (final o in payloadAll) {
    final t = o['tag']?.toString() ?? '';
    final k = _xrayIdentity(o);
    if (t.isNotEmpty && k != null) localSyn[t] = k;
  }
  final auto = _xrayAutoSelect(element, remarks, localSyn, memberTagByObTag);
  if (auto != null) result.add(auto..sourceExtended = extended);

  return result;
}







RegistryWarning _unreadEntry(
    RegistryWarning? reason, Map<String, dynamic> ob, String obTag) {
  final code = reason?.code ?? 'form_unrecognized';
  final params = <String, String>{...?reason?.params};
  final proto = ob['protocol']?.toString() ?? '';
  if (code == 'protocol_unsupported' &&
      proto.isNotEmpty &&
      !params.containsKey('scheme')) {
    params['scheme'] = proto;
  }
  return RegistryWarning(code: code, params: params, ownerTag: obTag);
}






AutoSelectSpec? _xrayAutoSelect(
  Map<String, dynamic> element,
  String remarks,
  Map<String, String>? synonyms, [
  Map<String, String> memberTags = const {},
]) {
  final routing = element['routing'];
  final balancers = routing is Map ? routing['balancers'] : null;
  if (balancers is! List || balancers.isEmpty) return null;
  final b = balancers.first;
  if (b is! Map) return null;




  final rawSel = b['selector'];
  final selector = rawSel is List
      ? rawSel.map((e) => '$e').toList()
      : const <String>[];
  final strategy = b['strategy'];
  final strategyMap = strategy is Map ? strategy : const {};
  final rawSettings = strategyMap['settings'];
  final settings = rawSettings is Map ? rawSettings : const {};
  final rawPing = element['burstObservatory'] is Map
      ? (element['burstObservatory'] as Map)['pingConfig']
      : null;
  final ping = rawPing is Map ? rawPing : const {};

























  final type = strategyMap['type']?.toString();
  final expected = _asInt(settings['expected']);
  final spreadAll = type == null || type == 'random' || type == 'roundRobin';
  final mode = switch (type) {
    'leastPing' => UrltestMode.leastTest,
    'leastLoad' when expected != null && expected <= 1 => UrltestMode.leastTest,
    _ => UrltestMode.roundRobin,
  };

  final d = const AutoSelectParams();
  final params = AutoSelectParams(
    url: ping['destination']?.toString() ?? d.url,
    interval: ping['interval']?.toString() ?? d.interval,
    idleTimeout: d.idleTimeout,
    mode: mode,



    pool: spreadAll ? _payloadCount(element) : (expected ?? d.pool),



    poolTolerance: clampPoolTolerance(
      _goDurationMs(settings['maxRTT']) ?? d.poolTolerance,
    ),
  );

  final label = remarks.isNotEmpty ? remarks : (b['tag']?.toString() ?? 'auto');
  final membership = RuleMembers.fromXraySelector(selector);



  final inc = tryCompileRegex(membership.include);
  final sourceMembers = <String>[
    for (final e in memberTags.entries)
      if (inc == null || inc.hasMatch(e.key)) e.value,
  ];
  return AutoSelectSpec(
    id: newUuidV4(),
    tag: tagFromLabel(label, 'urltest', 'auto', 0),
    label: label,
    membership: membership,
    params: params,
    tagSynonyms: synonyms == null ? const {} : Map.of(synonyms),

    genus: GroupGenus.forSource(kGenusSourceXray),
    sourceMemberTags: sourceMembers.toSet().toList(),


    sourceParamKeys: {
      if (ping['destination'] != null) 'url',
      if (ping['interval'] != null) 'interval',
      if (mode == UrltestMode.roundRobin) ...{'mode', 'balancer'},
    },
  );
}




int _payloadCount(Map<String, dynamic> element) {
  final obs = element['outbounds'];
  if (obs is! List) return 0;
  return obs
      .whereType<Map<String, dynamic>>()
      .where(
        (o) =>
            !kXrayServiceProtocols.contains(o['protocol']?.toString() ?? ''),
      )
      .length;
}



int? _asInt(Object? v) => switch (v) {
  final num n => n.toInt(),
  final String str => int.tryParse(str.trim()),
  _ => null,
};


int? _goDurationMs(Object? raw) {
  final s = raw?.toString().trim() ?? '';
  final m = RegExp(r'^(\d+(?:\.\d+)?)(ms|s|m|h)$').firstMatch(s);
  if (m == null) return null;
  final v = double.parse(m.group(1)!);
  return switch (m.group(2)) {
    'ms' => v.round(),
    's' => (v * 1000).round(),
    'm' => (v * 60000).round(),
    _ => (v * 3600000).round(),
  };
}



NodeSpec? parseXrayOutbound(Map<String, dynamic> element) {
  final nodes = parseXrayElement(element);
  return nodes.isEmpty ? null : nodes.first;
}





















String _elementLabel({
  required String remarks,
  required Map<String, dynamic> ob,
  required int index,
  required bool solo,
  required Map<String, int> tagUses,
}) {
  if (solo) return remarks;
  final tag = ob['tag']?.toString().trim() ?? '';
  if (remarks.isEmpty) return tag.isNotEmpty ? tag : '${index + 1}';

  if (tag.isEmpty || (tagUses[tag] ?? 0) > 1) return '$remarks ${index + 1}';
  return '$remarks $tag';
}


String _prettyJson(Object? value) {
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    return value.toString();
  }
}







List<String>? _stringListOrNull(Object? raw) {
  if (raw is! List) return null;
  final out = <String>[];
  for (final v in raw) {
    if (v == null) continue;
    final s = v.toString().trim();
    if (s.isNotEmpty) out.add(s);
  }
  return out.isEmpty ? null : out;
}









String? _xrayIdentity(Map<String, dynamic> o) {
  final protocol = o['protocol']?.toString() ?? '';
  final s = o['settings'] as Map? ?? const {};
  String server;
  int port;
  String cred;

  switch (protocol) {
    case 'vless':
    case 'vmess':
      final vnext = (s['vnext'] as List?)?.cast<Map>();
      if (vnext == null || vnext.isEmpty) return null;
      final v = vnext.first;
      server = v['address']?.toString() ?? '';







      final rawPort = (v['port'] as num?)?.toInt();
      if (rawPort == null || rawPort <= 0) return null;
      port = rawPort;
      final users = (v['users'] as List?)?.cast<Map>() ?? const [];
      cred = users.isEmpty ? '' : (users.first['id']?.toString() ?? '');



    case 'trojan':
    case 'shadowsocks':
      final servers = (s['servers'] as List?)?.cast<Map>();
      if (servers == null || servers.isEmpty) return null;
      final v = servers.first;
      server = v['address']?.toString() ?? '';






      final rawPort = (v['port'] as num?)?.toInt();
      if (rawPort == null || rawPort <= 0) return null;
      port = rawPort;
      cred = v['password']?.toString() ?? '';
    case 'hysteria':

      final hy = (o['streamSettings'] as Map?)?['hysteriaSettings'];
      server = s['address']?.toString() ?? '';



      final rawPort = (s['port'] as num?)?.toInt();
      if (rawPort == null || rawPort <= 0) return null;
      port = rawPort;
      cred = hy is Map ? (hy['auth']?.toString() ?? '') : '';
      if (server.isEmpty) return null;
      return 'hysteria2|$server|$port|$cred';
    default:
      return null;
  }
  if (server.isEmpty) return null;
  return '$protocol|$server|$port|$cred';
}


bool _isXrayFreedom(Map<String, dynamic>? o) =>
    o != null && (o['protocol']?.toString() ?? '') == 'freedom';
















NodeSpec? _xrayToSpec(
  Map<String, dynamic> o,
  String remarks, {
  XrayDropVerdict? dropped,
  String? rawSource,
  List<dynamic>? document,
}) {









  final mapping =
      mapJsonViaEngine('xray', o, dropped: dropped, document: document);
  if (mapping == null) return null;
  final label = remarks.isNotEmpty ? remarks : (o['tag']?.toString() ?? '');
  return parseXrayViaPipeline(
    mapping.body,
    rawSource: rawSource ?? _prettyJson(o),
    label: label,
    warnings: mapping.warnings,
    wsEarlyDataHeaderImplicit: mapping.wsEarlyDataHeaderImplicit,
    tagScheme: mapping.tagScheme,
    dropped: dropped,
  );
}























NodeSpec? _xrayBuildChain(
  Map<String, dynamic> owner,
  Map<String, Map<String, dynamic>> byTag,
  String firstRef,
  List<dynamic> document,
) {


  final visited = <String>{};
  final ownerTag = owner['tag']?.toString() ?? '';
  if (ownerTag.isNotEmpty) visited.add(ownerTag);

  NodeSpec? build(String ref, int depth) {
    if (ref.isEmpty) return null;


    if (depth >= kMaxDetourDepth) return null;
    if (visited.contains(ref)) return null;

    final target = byTag[ref];
    if (target == null) return null;
    final protocol = target['protocol']?.toString() ?? '';





    if (kXrayServiceProtocols.contains(protocol)) return null;

    visited.add(ref);









    final spec = _xrayToSpec(target, ref, document: document);
    if (spec == null) return null;


    if (spec.isGroup) return null;


    final stream = target['streamSettings'];
    final sockopt = stream is Map ? stream['sockopt'] : null;
    final nextRef = sockopt is Map ? sockopt['dialerProxy']?.toString() : null;
    if (nextRef == null || nextRef.isEmpty) return spec;

    if (_isXrayFreedom(byTag[nextRef])) return spec;

    final next = build(nextRef, depth + 1);



    if (next == null) return null;
    return withChained(spec, next);
  }

  return build(firstRef, 0);
}













const Set<String> kAppSingboxNodeTypes = {
  'vless',
  'vmess',
  'trojan',
  'anytls',
  'shadowsocks',
  'hysteria2',
  'naive',
  'tuic',
  'ssh',
  'socks',
  'http',
  'wireguard',
  'masque',
  'tailscale',
};

bool isAppKnownSingboxType(String type) => kAppSingboxNodeTypes.contains(type);

NodeSpec? parseSingboxEntry(
  Map<String, dynamic> entry, {
  String? rawSource,
  String? label,
  bool wsEarlyDataHeaderImplicit = false,
  BodySource? sanitizedFrom,
}) {
  final node = _parseSingboxEntryTyped(entry,
      rawSource: rawSource,
      label: label,
      wsEarlyDataHeaderImplicit: wsEarlyDataHeaderImplicit);






  if (node != null && sanitizedFrom != null) {
    node.bodyDelta = bodyDeltaFor(
      entry,
      node.emitRaw(TemplateVars.empty).map,
      dropDefaults: sanitizedFrom == BodySource.singbox,
    );
  }
  return node;
}

NodeSpec? _parseSingboxEntryTyped(
  Map<String, dynamic> entry, {
  String? rawSource,
  String? label,
  bool wsEarlyDataHeaderImplicit = false,
}) {



  final src = rawSource ?? _prettyJson(entry);
  final type = entry['type']?.toString() ?? '';
  final tag = entry['tag']?.toString() ?? '';
  final server = entry['server']?.toString() ?? '';
  final port = (entry['server_port'] as num?)?.toInt() ?? 0;
  final label0 = label ?? tag;


  final ka = tcpKeepAliveFromSingbox(entry);






  TransportSpec? transportOf(Object? raw) {
    final t = _transportFromSingbox(raw);
    if (!wsEarlyDataHeaderImplicit) return t;
    if (t is! WsTransport || t.earlyDataHeaderName == null) return t;
    return WsTransport(
      path: t.path,
      host: t.host,
      headers: t.headers,
      maxEarlyData: t.maxEarlyData,
      earlyDataHeaderName: t.earlyDataHeaderName,
      earlyDataHeaderImplicit: true,
    );
  }

  switch (type) {
    case 'vless':
      if (server.isEmpty || port == 0) return null;
      final tls = _tlsFromSingbox(entry['tls'], server);
      return VlessSpec(
        id: newUuidV4(),
        tag: tag.isEmpty ? 'vless-$server-$port' : tag,
        label: label0,
        server: server,
        port: port,
        rawSource: src,
        uuid: entry['uuid']?.toString() ?? '',
        flow: entry['flow']?.toString() ?? '',
        tls: tls,
        transport: transportOf(entry['transport']),
        packetEncoding: normalizePacketEncoding(
          entry['packet_encoding']?.toString() ?? '',
          tag: tag,
        ),






        encryption: entry['encryption']?.toString().trim() ?? '',
        tcpKeepAlive: ka,
      );
    case 'vmess':
      if (server.isEmpty || port == 0) return null;
      return VmessSpec(
        id: newUuidV4(),
        tag: tag.isEmpty ? 'vmess-$server-$port' : tag,
        label: label0,
        server: server,
        port: port,
        rawSource: src,
        uuid: entry['uuid']?.toString() ?? '',
        alterId: (entry['alter_id'] as num?)?.toInt() ?? 0,


        security: normalizeVmessSecurity(entry['security']?.toString() ?? ''),
        tls: _tlsFromSingbox(entry['tls'], server),
        transport: transportOf(entry['transport']),
        tcpKeepAlive: ka,
      );
    case 'trojan':
      if (server.isEmpty || port == 0) return null;
      return TrojanSpec(
        id: newUuidV4(),
        tag: tag.isEmpty ? 'trojan-$server-$port' : tag,
        label: label0,
        server: server,
        port: port,
        rawSource: src,
        password: entry['password']?.toString() ?? '',
        tls: _tlsFromSingbox(entry['tls'], server),
        transport: transportOf(entry['transport']),
        tcpKeepAlive: ka,
      );
    case 'anytls':
      if (server.isEmpty || port == 0) return null;


      var anyTls = _tlsFromSingbox(entry['tls'], server);
      if (!anyTls.enabled) {
        anyTls = TlsSpec(enabled: true, serverName: server);
      }
      return AnyTlsSpec(
        id: newUuidV4(),
        tag: tag.isEmpty ? 'anytls-$server-$port' : tag,
        label: label0,
        server: server,
        port: port,
        rawSource: src,
        password: entry['password']?.toString() ?? '',
        tls: anyTls,



        idleSessionCheckInterval: normalizeSingboxDuration(
            entry['idle_session_check_interval']?.toString() ?? ''),
        idleSessionTimeout: normalizeSingboxDuration(
            entry['idle_session_timeout']?.toString() ?? ''),







        minIdleSession: _asInt(entry['min_idle_session']),
        tcpKeepAlive: ka,
      );
    case 'shadowsocks':
      if (server.isEmpty || port == 0) return null;
      return ShadowsocksSpec(
        id: newUuidV4(),
        tag: tag.isEmpty ? 'ss-$server-$port' : tag,
        label: label0,
        server: server,
        port: port,
        rawSource: src,
        method: entry['method']?.toString() ?? '',
        password: entry['password']?.toString() ?? '',






        plugin: entry['plugin']?.toString() ?? '',
        pluginOpts: entry['plugin_opts']?.toString() ?? '',
        tcpKeepAlive: ka,
      );
    case 'hysteria2':
      if (server.isEmpty || port == 0) return null;

      final obfs = entry['obfs'] as Map?;








      final obfsType = obfs?['type']?.toString() ?? '';













      return Hysteria2Spec(
        id: newUuidV4(),
        tag: tag.isEmpty ? 'hy2-$server-$port' : tag,
        label: label0,
        server: server,
        port: port,
        rawSource: src,
        password: entry['password']?.toString() ?? '',
        obfs: obfsType,
        obfsPassword:
            obfsType.isEmpty ? '' : obfs?['password']?.toString() ?? '',
        obfsMinPacketSize: (obfs?['min_packet_size'] as num?)?.toInt(),
        obfsMaxPacketSize: (obfs?['max_packet_size'] as num?)?.toInt(),




        upMbps: (entry['up_mbps'] as num?)?.toInt(),
        downMbps: (entry['down_mbps'] as num?)?.toInt(),
        serverPorts: _stringListOrNull(entry['server_ports']),
        tls: _tlsFromSingbox(entry['tls'], server),
      );
    case 'naive':
      if (server.isEmpty || port == 0) return null;
      final eh = entry['extra_headers'];
      final extraHeaders = <String, String>{};
      if (eh is Map) {
        for (final k in eh.keys) {
          final v = eh[k];
          if (v is String) {
            extraHeaders[k.toString()] = v;
          } else if (v is List && v.isNotEmpty) {
            extraHeaders[k.toString()] = v.first.toString();
          }
        }
      }
      return NaiveSpec(
        id: newUuidV4(),
        tag: tag.isEmpty ? 'naive-$server-$port' : tag,
        label: label0,
        server: server,
        port: port,
        rawSource: src,
        username: entry['username']?.toString() ?? '',
        password: entry['password']?.toString() ?? '',



        tls: _naiveTlsFromSingbox(entry['tls'], server),
        extraHeaders: extraHeaders,










        quic: entry['quic'] == true,
        tcpKeepAlive: ka,
      );
    case 'tuic':
      if (server.isEmpty || port == 0) return null;
      return TuicSpec(




        id: newUuidV4(),
        tag: tag.isEmpty ? 'tuic-$server-$port' : tag,
        label: label0,
        server: server,
        port: port,
        rawSource: src,
        uuid: entry['uuid']?.toString() ?? '',
        password: entry['password']?.toString() ?? '',


        congestionControl: entry['congestion_control']?.toString(),
        udpRelayMode: entry['udp_relay_mode']?.toString(),
        zeroRtt: entry['zero_rtt_handshake'] == true,
        tls: _tlsFromSingbox(entry['tls'], server),

        heartbeat: entry['heartbeat'] == null
            ? null
            : normalizeSingboxDuration(entry['heartbeat'].toString()),
      );
    case 'ssh':
      if (server.isEmpty || port == 0) return null;
      final hk = entry['host_key'];
      return SshSpec(
        id: newUuidV4(),
        tag: tag.isEmpty ? 'ssh-$server-$port' : tag,
        label: label0,
        server: server,
        port: port,
        rawSource: src,
        user: entry['user']?.toString() ?? 'root',
        password: entry['password']?.toString() ?? '',
        privateKey: entry['private_key']?.toString() ?? '',
        privateKeyPassphrase: entry['private_key_passphrase']?.toString() ?? '',
        hostKey: hk is List ? hk.map((e) => e.toString()).toList() : const [],





        hostKeyAlgorithms: switch (entry['host_key_algorithms']) {
          final List l => l.map((e) => e.toString()).toList(),

          final String s when s.isNotEmpty => [s],
          _ => const <String>[],
        },
        tcpKeepAlive: ka,
      );
    case 'socks':
      if (server.isEmpty || port == 0) return null;
      return SocksSpec(
        id: newUuidV4(),
        tag: tag.isEmpty ? 'socks-$server-$port' : tag,
        label: label0,
        server: server,
        port: port,
        rawSource: src,






        version: (entry['version']?.toString().trim().toLowerCase() ?? '')
                .isEmpty
            ? '5'
            : entry['version'].toString().trim().toLowerCase(),
        username: entry['username']?.toString() ?? '',
        password: entry['password']?.toString() ?? '',
        tcpKeepAlive: ka,
      );
    case 'http':
      if (server.isEmpty || port == 0) return null;


      final hh = entry['headers'];
      final headers = <String, String>{};
      if (hh is Map) {
        for (final k in hh.keys) {
          final v = hh[k];
          if (v is String) {
            headers[k.toString()] = v;
          } else if (v is List && v.isNotEmpty) {
            headers[k.toString()] = v.first.toString();
          }
        }
      }
      return HttpSpec(
        id: newUuidV4(),
        tag: tag.isEmpty ? 'http-$server-$port' : tag,
        label: label0,
        server: server,
        port: port,
        rawSource: src,
        username: entry['username']?.toString() ?? '',
        password: entry['password']?.toString() ?? '',
        path: entry['path']?.toString() ?? '',
        headers: headers,
        tls: _tlsFromSingbox(entry['tls'], server),
        tcpKeepAlive: ka,
      );
    case 'wireguard':

      final addr =
          (entry['address'] as List?)
              ?.map((e) => ensureCidr(e.toString()))
              .toList() ??
          const <String>[];
      final peers = (entry['peers'] as List?)?.cast<Map>() ?? const [];
      if (peers.isEmpty) return null;
      final p = peers.first;
      final peerServer = p['address']?.toString() ?? server;
      final peerPort = (p['port'] as num?)?.toInt() ?? port;
      if (peerServer.isEmpty) return null;
      final allowedIps =
          (p['allowed_ips'] as List?)
              ?.map((e) => ensureCidr(e.toString()))
              .toList() ??
          const ['0.0.0.0/0', '::/0'];
      final awg = Awg.fromJson(entry);
      final wgTag = tag.isEmpty ? 'wg-$peerServer-$peerPort' : tag;




      final rawMtu = (entry['mtu'] as num?)?.toInt();





      final reserved =
          _reservedFromJson(p['reserved'] ?? entry['reserved']) ??
          (p['client_id'] is String
              ? parseReserved(p['client_id'] as String)
              : null);





      final wgPrivRaw = entry['private_key']?.toString() ?? '';
      final wgPubRaw = p['public_key']?.toString() ?? '';
      final wgPriv = normalizeWGKey(wgPrivRaw) ?? wgPrivRaw;
      final wgPub = normalizeWGKey(wgPubRaw) ?? wgPubRaw;
      if (awg != null) normalizeAwgHeaderKey(awg);
      final wgPskRaw = p['pre_shared_key']?.toString() ?? '';
      final wgPsk =
          wgPskRaw.isEmpty ? '' : (normalizeWGKey(wgPskRaw) ?? wgPskRaw);
      return WireguardSpec(
        id: newUuidV4(),
        tag: wgTag,
        label: label0,
        server: peerServer,
        port: peerPort,
        rawSource: src,
        privateKey: wgPriv,
        localAddresses: addr,
        peers: [
          WireguardPeer(
            publicKey: wgPub,
            preSharedKey: wgPsk,
            endpointHost: peerServer,
            endpointPort: peerPort,
            allowedIps: allowedIps,

            persistentKeepalive: _wgKeepaliveFromJson(
                p['persistent_keepalive_interval']),
            reserved: reserved,
          ),
        ],












        mtu: awg != null || Awg.hasAwg3Json(entry)
            ? (rawMtu ?? awgMtuCeilingByRegistry(type))
            : rawMtu,
        awg: awg,
      );
    case 'masque':


      if (server.isEmpty || port == 0) return null;
      final priv = entry['private_key']?.toString() ?? '';
      final pub = entry['public_key']?.toString() ?? '';




      final ip = entry['ip']?.toString() ?? '';
      final ipv6 = entry['ipv6']?.toString() ?? '';
      final addrs = <String>[
        if (ip.isNotEmpty) ensureCidr(ip),
        if (ipv6.isNotEmpty) ensureCidr(ipv6),
      ];






      final masqueTls = entry['tls'];
      final tlsMap = masqueTls is Map ? masqueTls : const {};
      final vhttpRaw = entry['vhttp']?.toString() ?? '';




      final vhttpJson = (vhttpRaw.isEmpty || vhttpRaw == 'h3' ||
              vhttpRaw == 'h2' || vhttpRaw == 'auto')
          ? vhttpRaw
          : 'h3';
      final sniRaw = tlsMap['server_name']?.toString() ?? '';
      return MasqueSpec(









        id: newUuidV4(),
        tag: tag.isEmpty ? 'masque-$server-$port' : tag,
        label: label0,
        server: server,
        port: port,
        rawSource: src,
        privateKeyDer: priv,
        publicKeyDer: pub,
        localAddresses: addrs,
        profile: entry['profile']?.toString() ?? 'cloudflare',
        vhttp: vhttpJson,
        sni: sniRaw,
        disableSni: tlsMap['disable_sni'] == true,
        mtu: (entry['mtu'] as num?)?.toInt(),
        idleTimeout: entry['idle_timeout']?.toString() ?? '',
        keepAlive: entry['keep_alive_period']?.toString() ?? '',
        tlsExtra: {
          for (final e in tlsMap.entries)
            if (e.key != 'server_name' &&
                e.key != 'disable_sni' &&
                e.key != 'enabled' &&
                e.value != null)
              '${e.key}': e.value as Object,
        },
      );
    case 'tailscale':





      return TailscaleSpec(
        id: newUuidV4(),
        tag: tag.isEmpty ? 'tailscale' : tag,
        label: label0,
        body: entry,
        rawSource: src,
      );
    default:
      return null;
  }
}




List<int>? _reservedFromJson(dynamic raw) {
  if (raw is! List || raw.length != 3) return null;
  final out = <int>[];
  for (final e in raw) {
    final n = e is num ? e.toInt() : null;
    if (n == null || n < 0 || n > 255) return null;
    out.add(n);
  }
  return out;
}








TlsSpec _naiveTlsFromSingbox(dynamic raw, String server) {
  final full = _tlsFromSingbox(raw, server);
  if (!full.enabled) return full;
  return TlsSpec(
    enabled: true,
    serverName: full.serverName,
    passthrough: {
      for (final e in full.passthrough.entries)
        if (kNaiveTlsPassthroughKeys.contains(e.key)) e.key: e.value,
    },
  );
}






Map<String, Object> tlsPassthroughFromSingbox(Map raw) {
  final out = <String, Object>{};
  for (final k in kTlsPassthroughKeys) {
    if (!raw.containsKey(k)) continue;
    final v = raw[k];
    if (kTlsBoolKeys.contains(k)) {
      if (v == true) out[k] = true;
    } else if (kTlsObjectKeys.contains(k)) {



      if (v is Map) {
        final obj = Map<String, dynamic>.from(v.cast<String, dynamic>());
        if (obj.isNotEmpty) out[k] = obj;
      }
    } else if (kTlsListableKeys.contains(k)) {
      if (v is String) {
        if (v.isNotEmpty) out[k] = v;
      } else if (v is List) {
        final list = [
          for (final e in v)
            if (e is String && e.isNotEmpty) e,
        ];
        if (list.isNotEmpty) out[k] = list;
      }
    } else if (v is String && v.isNotEmpty) {
      out[k] = v;
    }
  }
  return out;
}

TlsSpec _tlsFromSingbox(dynamic raw, String server) {
  if (raw is! Map) return TlsSpec.disabled;
  if (raw['enabled'] != true) return TlsSpec.disabled;
  final utls = raw['utls'] as Map?;
  final reality = raw['reality'] as Map?;



  return normalizeTlsFingerprint(
    TlsSpec(
      enabled: true,















      serverName: raw['server_name']?.toString(),



      alpn: switch (raw['alpn']) {
        final List l => [for (final e in l) e.toString()],
        _ => const [],
      },
      insecure: raw['insecure'] == true,


      fingerprint: utls?['fingerprint']?.toString() ??
          (utls?['enabled'] == true ? '' : null),


      certificatePublicKeySha256: switch (raw['certificate_public_key_sha256']) {
        final String v when v.isNotEmpty => [v],
        final List v => [
            for (final e in v)
              if (e is String && e.isNotEmpty) e,
          ],
        _ => const [],
      },
      passthrough: {
        ...tlsPassthroughFromSingbox(raw),
        if (raw['alpn'] case final String a when a.isNotEmpty) 'alpn': a,
      },


      reality:
          reality == null ||
              reality['enabled'] != true ||
              !isValidRealityPublicKey(reality['public_key']?.toString() ?? '')
          ? null
          : RealitySpec(









              publicKey: reality['public_key']!.toString().trim(),
              shortId: normalizeRealityShortId(
                reality['short_id']?.toString() ?? '',
              ),
              keyShare: _realityKeyShare(reality['key_share']),
            ),
    ),
    null,
  );
}











String? _realityKeyShare(dynamic raw) =>
    raw is String && raw.isNotEmpty ? raw : null;

TransportSpec? _transportFromSingbox(dynamic raw) {
  if (raw is! Map) return null;
  final type = raw['type']?.toString() ?? '';
  switch (type) {
    case 'ws':
      final headers = (raw['headers'] as Map?)?.cast<String, dynamic>();





      final wsHasPath = raw.containsKey('path');
      final (splitPath, edFromPath) = splitEarlyDataPath(
        raw['path']?.toString() ?? '',
      );
      final path = wsHasPath ? splitPath : '';
      final edField = raw['max_early_data'];
      return WsTransport(
        path: path,
        host: headers?['Host']?.toString() ?? '',





        headers: _headersExceptHost(headers),
        maxEarlyData: edField is int ? edField : edFromPath,
        earlyDataHeaderName:
            (raw['early_data_header_name']?.toString().isNotEmpty ?? false)
            ? raw['early_data_header_name'].toString()
            : null,
      );
    case 'grpc':
      return GrpcTransport(serviceName: raw['service_name']?.toString() ?? '');
    case 'http':
      return HttpTransport(
        path: raw['path']?.toString() ?? '/',
        hosts:
            (raw['host'] as List?)?.map((e) => e.toString()).toList() ??
            const [],



        headers: (raw['headers'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), _headerValue(v)),
            ) ??
            const {},
      );
    case 'httpupgrade':


      final huHasPath = raw.containsKey('path');
      final (splitPath, _) = splitEarlyDataPath(
        raw['path']?.toString() ?? '',
      );
      final path = huHasPath ? splitPath : '';
      return HttpUpgradeTransport(
        path: path,
        host: raw['host']?.toString() ?? '',

        headers: _headersExceptHost(
            (raw['headers'] as Map?)?.cast<String, dynamic>()),
      );

    case 'splithttp':
    case 'xhttp':


      return xhttpFromMap(
        xhttpScalarsFromJson(raw),
        headers:
            (raw['headers'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            ) ??
            const {},
      );
    default:
      return null;
  }
}




Map<String, String> _headersExceptHost(Map<String, dynamic>? raw) {
  if (raw == null) return const {};
  final out = <String, String>{};
  for (final e in raw.entries) {
    if (e.key == 'Host') continue;
    out[e.key] = _headerValue(e.value);
  }
  return out;
}




String _headerValue(Object? v) {
  if (v is List) return v.isEmpty ? '' : v.first.toString();
  return v?.toString() ?? '';
}



Object? _wgKeepaliveFromJson(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return parseWgKeepalive(v);
  return null;
}
