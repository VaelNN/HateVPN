





















library;

import 'masque_account.dart';
import 'warp_account.dart';


Map<String, dynamic> warpAccountToBackup(WarpAccount acc) {
  return <String, dynamic>{
    'type': 'wg',
    'private_key': acc.privKey,
    'peer_public': acc.peerPub,
    'client_v4': acc.clientV4,
    'client_v6': acc.clientV6,
    if (acc.clientId.isNotEmpty) 'client_id': acc.clientId,
    if (acc.deviceId.isNotEmpty) 'device_id': acc.deviceId,
    if (acc.token.isNotEmpty) 'token': acc.token,
    if (acc.accountId.isNotEmpty) 'account_id': acc.accountId,
    if (acc.license != null && acc.license!.isNotEmpty) 'license': acc.license,
    if (acc.warpPlus) 'warp_plus': true,
    if (acc.createdAt.isNotEmpty) 'created_at': acc.createdAt,


    if (acc.awg != null) 'awg': Map<String, Object>.from(acc.awg!.fields),

    if (acc.endpoint.isNotEmpty && acc.endpoint != WarpAccount.defaultEndpoint)
      'endpoint': acc.endpoint,
  };
}


Map<String, dynamic> masqueAccountToBackup(MasqueAccount acc) {
  return <String, dynamic>{
    'type': 'masque',
    'private_key_der': acc.privKeyDer,
    'server_pub_der': acc.serverPubDer,
    'client_v4': acc.clientV4,
    'client_v6': acc.clientV6,
    'server': acc.server,
    if (acc.port != 0) 'port': acc.port,
    if (acc.deviceId.isNotEmpty) 'device_id': acc.deviceId,
    if (acc.token.isNotEmpty) 'token': acc.token,
    if (acc.createdAt.isNotEmpty) 'created_at': acc.createdAt,



    if (acc.sni.isNotEmpty) 'sni': acc.sni,
    if (acc.idleTimeout.isNotEmpty) 'idle_timeout': acc.idleTimeout,
    if (acc.keepAlive.isNotEmpty) 'keep_alive': acc.keepAlive,
  };
}






WarpAccount? warpAccountFromBackup(Map<String, dynamic> j) {
  if (j['type'] != 'wg') return null;
  return WarpAccount.fromJson({
    'priv_key': j['private_key'],
    'peer_pub': j['peer_public'],
    'client_v4': j['client_v4'],
    'client_v6': j['client_v6'],
    'client_id': j['client_id'],
    'account_id': j['account_id'],
    'device_id': j['device_id'],
    'token': j['token'],


    'endpoint': j['endpoint'] ?? WarpAccount.defaultEndpoint,
    'created_at': j['created_at'],
    'license': j['license'],
    'warp_plus': j['warp_plus'],
    'awg': ?_awgFrom(j['awg']),
  });
}


MasqueAccount? masqueAccountFromBackup(Map<String, dynamic> j) {
  if (j['type'] != 'masque') return null;
  return MasqueAccount.fromJson({
    'priv_key_der': j['private_key_der'],
    'server_pub_der': j['server_pub_der'],
    'client_v4': j['client_v4'],
    'client_v6': j['client_v6'],
    'server': j['server'],
    'port': j['port'],
    'device_id': j['device_id'],
    'token': j['token'],
    'created_at': j['created_at'],
    'sni': j['sni'],
    'idle_timeout': j['idle_timeout'],
    'keep_alive': j['keep_alive'],
  });
}




Map<String, dynamic>? _awgFrom(Object? raw) =>
    raw is Map && raw.isNotEmpty ? raw.cast<String, dynamic>() : null;
