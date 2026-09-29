


library;

import 'dart:convert';

import '../vpn/cc_channel.dart';
import 'l10n/locale_controller.dart';



enum ExitNodeMismatch {

  none,


  chosenNotSaved,


  clearedNotSaved,


  otherNotSaved,
}


String? recordedExitNode(Map<String, dynamic> body) {
  final v = body['exit_node'];
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}




bool exitNodeRefersTo(
  String recorded,
  CcTailscalePeer peer, {
  String magicDnsSuffix = '',
}) {
  final r = recorded.trim().toLowerCase();
  if (r.isEmpty) return false;
  if (peer.ips.any((ip) => ip.toLowerCase() == r)) return true;
  final fqdn = peer.dnsNameClean.toLowerCase();
  if (fqdn.isNotEmpty) {
    if (r == fqdn || r == '$fqdn.') return true;
    final suffix = magicDnsSuffix.toLowerCase().replaceAll(RegExp(r'\.$'), '');
    final base = suffix.isNotEmpty && fqdn.endsWith('.$suffix')
        ? fqdn.substring(0, fqdn.length - suffix.length - 1)
        : fqdn.split('.').first;
    if (r == base) return true;
  }
  return peer.hostName.isNotEmpty && r == peer.hostName.toLowerCase();
}


ExitNodeMismatch exitNodeMismatch({
  required String? recorded,
  required CcTailscalePeer? active,
  String magicDnsSuffix = '',
}) {
  if (recorded == null && active == null) return ExitNodeMismatch.none;
  if (recorded == null) return ExitNodeMismatch.chosenNotSaved;
  if (active == null) return ExitNodeMismatch.clearedNotSaved;
  return exitNodeRefersTo(recorded, active, magicDnsSuffix: magicDnsSuffix)
      ? ExitNodeMismatch.none
      : ExitNodeMismatch.otherNotSaved;
}


String exitNodeWarningText(ExitNodeMismatch m) => switch (m) {
  ExitNodeMismatch.none => '',
  ExitNodeMismatch.chosenNotSaved => getLocalText.s(
    "Not saved. Traffic is not routed through this node until you save the choice.",
  ),
  ExitNodeMismatch.clearedNotSaved => getLocalText.s(
    "Not saved. The node stays in the lists, but has no exit until you save the choice.",
  ),
  ExitNodeMismatch.otherNotSaved => getLocalText.s(
    "Not saved. The choice is lost after restart.",
  ),
};





String exitNodeConfigValue(CcTailscalePeer peer) {
  final v4 = peer.ips.where((ip) => !ip.contains(':'));
  if (v4.isNotEmpty) return v4.first;
  if (peer.ips.isNotEmpty) return peer.ips.first;
  if (peer.dnsNameClean.isNotEmpty) return peer.dnsNameClean;
  return peer.hostName;
}





String withExitNode(String source, String? value) {
  final decoded = jsonDecode(source);
  if (decoded is! Map) {
    throw const FormatException('node source is not a JSON object');
  }
  final body = <String, dynamic>{
    for (final e in decoded.entries) '${e.key}': e.value,
  };
  if (value == null || value.isEmpty) {
    body.remove('exit_node');
  } else {
    body['exit_node'] = value;
  }
  return const JsonEncoder.withIndent('  ').convert(body);
}



List<CcTailscalePeer> sortDevices(Iterable<CcTailscalePeer> peers) {
  final list = peers.toList();
  list.sort((a, b) {
    if (a.online != b.online) return a.online ? -1 : 1;
    return a.hostName.toLowerCase().compareTo(b.hostName.toLowerCase());
  });
  return list;
}


List<CcTailscalePeer> exitNodeOptions(CcTailscaleStatus s) =>
    sortDevices(s.peers.where((p) => p.exitNodeOption));


bool showOwnerGroups(CcTailscaleStatus s) =>
    s.userGroups.where((g) => g.peers.isNotEmpty).length > 1;




bool tailscaleHasExit({
  required bool vpnUp,
  required CcTailscaleStatus? status,
  required Map<String, dynamic> body,
}) {
  if (vpnUp && status != null) return status.exitNode != null;
  return recordedExitNode(body) != null;
}



Map<String, Object> tailscaleDebugSummary(CcTailscaleStatus s) => {
  'backend_state': s.backendState,
  'devices': s.peers.length,
};
