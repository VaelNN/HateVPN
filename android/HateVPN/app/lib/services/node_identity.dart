import '../models/node_spec.dart';














String? nodeIdentityKey(NodeSpec node) {



  final patch = node.patchedJson;
  if (patch != null && !node.isGroup) {
    final server = _patchServer(patch);
    if (server.isEmpty) return null;
    final type = patch['type']?.toString() ?? node.protocol;
    return '$type|$server|${patch['server_port'] ?? node.port}|'
        '${_patchCred(patch)}';
  }
  return nodeIdentityKeyRaw(node);
}



String? nodeIdentityKeyRaw(NodeSpec node) {
  if (node.isGroup || node.server.isEmpty) return null;
  final cred = switch (node) {
    VlessSpec s => s.uuid,
    VmessSpec s => s.uuid,
    TrojanSpec s => s.password,
    ShadowsocksSpec s => s.password,
    Hysteria2Spec s => s.password,
    AnyTlsSpec s => s.password,
    TuicSpec s => s.uuid,
    NaiveSpec s => s.password,
    SocksSpec s => s.username,
    HttpSpec s => s.username,
    SshSpec s => s.user,
    WireguardSpec s => s.privateKey,
    MasqueSpec s => s.privateKeyDer,
    AutoSelectSpec() => '',

    TailscaleSpec() => '',

    UnknownTypeSpec s => s.body['username']?.toString() ?? '',
  };
  return '${node.protocol}|${node.server}|${node.port}|$cred';
}


String _patchServer(Map<String, dynamic> patch) {
  final direct = patch['server']?.toString() ?? '';
  if (direct.isNotEmpty) return direct;
  final peers = patch['peers'];
  if (peers is List && peers.isNotEmpty && peers.first is Map) {
    return (peers.first as Map)['address']?.toString() ?? '';
  }
  return '';
}




String _patchCred(Map<String, dynamic> patch) {
  for (final k in const ['uuid', 'password', 'private_key', 'username', 'user']) {
    final v = patch[k]?.toString() ?? '';
    if (v.isNotEmpty) return v;
  }
  return '';
}
