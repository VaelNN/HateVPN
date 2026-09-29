import 'dart:convert';

import '../services/parser/engine/emitter.dart';
import '../services/parser/engine/section_loader.dart';
import '../services/parser/tcp_keep_alive.dart';
import 'node_spec.dart';
import 'singbox_entry.dart';
import 'template_vars.dart';
















String? uriViaEngine(NodeSpec s) {
  final section = MapperSections.I.sectionFor('uri', s.protocol);
  if (section == null || !sectionEmits(section)) return null;
  final body = s.emitRaw(TemplateVars.empty).map;
  return emitViaSection(section, body, s.label)?.uri;
}








String uriViaEngineRequired(NodeSpec s) {
  final uri = uriViaEngine(s);
  if (uri != null) return uri;
  throw StateError(
    'нет секции эмита для типа тела «${s.protocol}»: реестр контракта не '
    'загружен либо секция не объявила emit. Рукописного эмита у этой схемы '
    'не осталось (§480 W7).',
  );
}











Map<String, dynamic> _baseOutbound(String type, NodeSpec s) => <String, dynamic>{
      'type': type,
      'tag': s.tag,
      'server': s.server,
      'server_port': s.port,
    };







void _addDialFields(Map<String, dynamic> out, NodeSpec s) {
  if (s.chained != null) out['detour'] = s.chained!.tag;
  tcpKeepAliveToSingbox(out, s.tcpKeepAlive);
}








Endpoint emitTailscale(TailscaleSpec s, TemplateVars vars) {
  final map = <String, dynamic>{
    'type': 'tailscale',
    'tag': s.tag,
    ...deepCopyJson(s.body) as Map<String, dynamic>,
  };
  _addDialFields(map, s);
  return Endpoint(map);
}



String toUriTailscale(TailscaleSpec s) => jsonEncode(<String, dynamic>{
      'type': 'tailscale',
      'tag': s.tag,
      ...s.body,
    });





Outbound emitVless(VlessSpec s, TemplateVars vars) {
  final out = _baseOutbound('vless', s)..['uuid'] = s.uuid;

  if (s.transport != null) {
    final (tmap, warnings) = s.transport!.toSingbox(vars);
    out['transport'] = tmap;
    for (final w in warnings) {
      if (!s.warnings.contains(w)) s.warnings.add(w);
    }
  }







  if (s.flow.isNotEmpty) out['flow'] = s.flow;
  if (s.packetEncoding.isNotEmpty) out['packet_encoding'] = s.packetEncoding;







  if (s.encryption.isNotEmpty) out['encryption'] = s.encryption;

  final tlsMap = s.tls.toSingbox();
  if (tlsMap.isNotEmpty) out['tls'] = tlsMap;

  _addDialFields(out, s);

  return Outbound(out);
}





Outbound emitVmess(VmessSpec s, TemplateVars vars) {
  final out = _baseOutbound('vmess', s)
    ..['uuid'] = s.uuid
    ..['security'] = s.security;
  if (s.alterId != 0) out['alter_id'] = s.alterId;

  if (s.transport != null) {
    final (tmap, warnings) = s.transport!.toSingbox(vars);
    out['transport'] = tmap;
    for (final w in warnings) {
      if (!s.warnings.contains(w)) s.warnings.add(w);
    }
  }

  final tlsMap = s.tls.toSingbox();
  if (tlsMap.isNotEmpty) out['tls'] = tlsMap;

  _addDialFields(out, s);
  return Outbound(out);
}





Outbound emitTrojan(TrojanSpec s, TemplateVars vars) {
  final out = _baseOutbound('trojan', s)..['password'] = s.password;
  if (s.transport != null) {
    final (tmap, warnings) = s.transport!.toSingbox(vars);
    out['transport'] = tmap;
    for (final w in warnings) {
      if (!s.warnings.contains(w)) s.warnings.add(w);
    }
  }


  final tlsMap = s.tls.toSingbox();
  if (tlsMap.isNotEmpty) out['tls'] = tlsMap;
  _addDialFields(out, s);
  return Outbound(out);
}





Outbound emitAnyTls(AnyTlsSpec s, TemplateVars vars) {
  final out = _baseOutbound('anytls', s)..['password'] = s.password;


  out['tls'] = s.tls.toSingbox();
  if (s.idleSessionCheckInterval.isNotEmpty) {
    out['idle_session_check_interval'] = s.idleSessionCheckInterval;
  }
  if (s.idleSessionTimeout.isNotEmpty) {
    out['idle_session_timeout'] = s.idleSessionTimeout;
  }
  if (s.minIdleSession != null) {
    out['min_idle_session'] = s.minIdleSession;
  }
  _addDialFields(out, s);
  return Outbound(out);
}





Outbound emitShadowsocks(ShadowsocksSpec s, TemplateVars vars) {
  final out = _baseOutbound('shadowsocks', s)
    ..['method'] = s.method
    ..['password'] = s.password;
  if (s.plugin.isNotEmpty) out['plugin'] = s.plugin;



  if (s.pluginOpts.isNotEmpty) out['plugin_opts'] = s.pluginOpts;
  _addDialFields(out, s);
  return Outbound(out);
}





Outbound emitHysteria2(Hysteria2Spec s, TemplateVars vars) {
  final out = _baseOutbound('hysteria2', s);
  if (s.password.isNotEmpty) out['password'] = s.password;



  if (s.serverPorts != null && s.serverPorts!.isNotEmpty) {
    out['server_ports'] = List<String>.from(s.serverPorts!);
  }





  if (s.obfs.isNotEmpty) {
    out['obfs'] = {
      'type': s.obfs,
      if (s.obfsPassword.isNotEmpty) 'password': s.obfsPassword,
      'min_packet_size': ?s.obfsMinPacketSize,
      'max_packet_size': ?s.obfsMaxPacketSize,
    };
  }
  if (s.upMbps != null) out['up_mbps'] = s.upMbps;
  if (s.downMbps != null) out['down_mbps'] = s.downMbps;


  out['tls'] = s.tls.toSingbox();
  _addDialFields(out, s);
  return Outbound(out);
}







Outbound emitNaive(NaiveSpec s, TemplateVars vars) {
  final out = _baseOutbound('naive', s);
  if (s.username.isNotEmpty) out['username'] = s.username;
  if (s.password.isNotEmpty) out['password'] = s.password;


  if (s.quic) {
    out['quic'] = true;
    out['quic_congestion_control'] = 'bbr';
  }
  if (s.extraHeaders.isNotEmpty) {
    final keys = s.extraHeaders.keys.toList()..sort();
    final sorted = <String, String>{};
    for (final k in keys) {
      sorted[k] = s.extraHeaders[k]!;
    }
    out['extra_headers'] = sorted;
  }
  out['tls'] = s.tls.toSingbox();
  _addDialFields(out, s);
  return Outbound(out);
}













Outbound emitTuic(TuicSpec s, TemplateVars vars) {
  final out = _baseOutbound('tuic', s)..['uuid'] = s.uuid;


  if (s.password.isNotEmpty) out['password'] = s.password;


  if (s.congestionControl != null) {
    out['congestion_control'] = s.congestionControl;
  }
  if (s.udpRelayMode != null) out['udp_relay_mode'] = s.udpRelayMode;
  if (s.zeroRtt) out['zero_rtt_handshake'] = true;
  if (s.heartbeat != null) out['heartbeat'] = s.heartbeat;


  out['tls'] = s.tls.toSingbox();
  _addDialFields(out, s);
  return Outbound(out);
}





Outbound emitSsh(SshSpec s, TemplateVars vars) {
  final out = _baseOutbound('ssh', s)..['user'] = s.user;
  if (s.password.isNotEmpty) out['password'] = s.password;
  if (s.privateKey.isNotEmpty) out['private_key'] = s.privateKey;
  if (s.privateKeyPassphrase.isNotEmpty) {
    out['private_key_passphrase'] = s.privateKeyPassphrase;
  }
  if (s.hostKey.isNotEmpty) out['host_key'] = s.hostKey;
  if (s.hostKeyAlgorithms.isNotEmpty) {
    out['host_key_algorithms'] = s.hostKeyAlgorithms;
  }
  _addDialFields(out, s);
  return Outbound(out);
}





Outbound emitSocks(SocksSpec s, TemplateVars vars) {
  final out = _baseOutbound('socks', s)..['version'] = s.version;
  if (s.username.isNotEmpty) out['username'] = s.username;
  if (s.password.isNotEmpty) out['password'] = s.password;
  _addDialFields(out, s);
  return Outbound(out);
}





Outbound emitHttp(HttpSpec s, TemplateVars vars) {
  final out = _baseOutbound('http', s);
  if (s.username.isNotEmpty) out['username'] = s.username;
  if (s.password.isNotEmpty) out['password'] = s.password;
  if (s.path.isNotEmpty) out['path'] = s.path;
  if (s.headers.isNotEmpty) {
    final keys = s.headers.keys.toList()..sort();
    final sorted = <String, String>{};
    for (final k in keys) {
      sorted[k] = s.headers[k]!;
    }
    out['headers'] = sorted;
  }
  final tlsMap = s.tls.toSingbox();
  if (tlsMap.isNotEmpty) out['tls'] = tlsMap;
  _addDialFields(out, s);
  return Outbound(out);
}





Endpoint emitWireguard(WireguardSpec s, TemplateVars vars) {
  final peers = s.peers
      .map((p) => <String, dynamic>{
            'address': p.endpointHost,
            'port': p.endpointPort,
            'public_key': p.publicKey,


            if (p.reserved != null && p.reserved!.isNotEmpty)
              'reserved': List<int>.from(p.reserved!),
            'allowed_ips': List<String>.from(p.allowedIps),
            if (p.preSharedKey.isNotEmpty) 'pre_shared_key': p.preSharedKey,
            if (p.persistentKeepalive != null)
              'persistent_keepalive_interval': p.persistentKeepalive,
          })
      .toList();

  final map = <String, dynamic>{
    'type': 'wireguard',
    'tag': s.tag,
    if (s.mtu != null) 'mtu': s.mtu,
    'address': List<String>.from(s.localAddresses),
    'private_key': s.privateKey,
    'peers': peers,
  };

  s.awg?.writeInto(map);
  return Endpoint(map);
}






Outbound emitMasque(MasqueSpec s, TemplateVars vars) {
  String? ip, ipv6;
  for (final a in s.localAddresses) {
    if (a.contains(':')) {
      ipv6 ??= a;
    } else {
      ip ??= a;
    }
  }




  final tls = <String, dynamic>{
    if (s.sni.isNotEmpty) 'server_name': s.sni,
    if (s.disableSni) 'disable_sni': true,
    for (final e in s.tlsExtra.entries)
      e.key: e.value is List ? List<Object>.from(e.value as List) : e.value,
  };
  final map = <String, dynamic>{
    'type': 'masque',
    'tag': s.tag,
    'server': s.server,
    'server_port': s.port,
    'profile': s.profile,

    if (s.vhttp.isNotEmpty) 'vhttp': s.vhttp,

    if (s.privateKeyDer.isNotEmpty) 'private_key': s.privateKeyDer,
    if (s.publicKeyDer.isNotEmpty) 'public_key': s.publicKeyDer,
    'ip': ?ip,
    'ipv6': ?ipv6,
    if (tls.isNotEmpty) 'tls': tls,
    if (s.mtu != null) 'mtu': s.mtu,
    if (s.idleTimeout.isNotEmpty) 'idle_timeout': s.idleTimeout,
    if (s.keepAlive.isNotEmpty) 'keep_alive_period': s.keepAlive,
  };
  return Outbound(map);
}
