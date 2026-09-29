import 'dart:convert';
import 'dart:io';

import '../../models/node_spec.dart';
import 'body_decoder.dart';
import 'drop_verdict.dart';
import 'ini_parser.dart';
import 'uri_utils.dart';











DecodedBody decodeAmneziaLink(String link) {
  final t = link.trim();
  if (!t.startsWith('vpn://')) {
    return const DecodeFailure('not a vpn:// link');
  }
  if (t.length > maxAmneziaLinkLength) {
    return const DecodeFailure('vpn://: link too long');
  }





  final bareIni = _decodeBareIni(t);
  if (bareIni != null) return AmneziaConfig([bareIni]);

  final root = _decodeAmneziaRoot(t);
  if (root == null) {
    return const DecodeFailure('vpn://: payload is neither qCompress nor JSON');
  }

  final containers = root['containers'];
  if (containers is! List || containers.isEmpty) {
    return const DecodeFailure('vpn://: no containers[]');
  }

  final inis = <String>[];
  for (final c in containers) {
    if (c is! Map) continue;
    for (final proto in const ['awg', 'wireguard']) {
      final ini = _extractIni(c[proto]);
      if (ini != null) inis.add(_substituteDns(ini, root));
    }
  }
  if (inis.isEmpty) {
    return const DecodeFailure('vpn://: no WireGuard/AmneziaWG containers');
  }
  return AmneziaConfig(inis);
}













WireguardSpec? parseAmneziaVpnUri(String link, {XrayDropVerdict? dropped}) {
  final t = link.trim();
  if (!t.startsWith('vpn://')) return null;





  final bareIni = _decodeBareIni(t);
  if (bareIni != null) return parseWireguardIni(bareIni, dropped: dropped);

  final root = _decodeAmneziaRoot(t);
  if (root == null) return null;

  final containers = root['containers'];
  if (containers is! List || containers.isEmpty) return null;

  final defaultContainer = root['defaultContainer'];
  final preferredName = defaultContainer is String ? defaultContainer : null;



  Map? chosen;
  String? chosenIni;
  Map? firstWithIni;
  String? firstWithIniText;
  for (final c in containers) {
    if (c is! Map) continue;
    String? ini;
    for (final proto in const ['awg', 'wireguard']) {
      ini = _extractIni(c[proto]);
      if (ini != null) break;
    }
    if (ini == null) continue;
    firstWithIni ??= c;
    firstWithIniText ??= ini;
    final name = c['container'];
    if (preferredName != null && name == preferredName) {
      chosen = c;
      chosenIni = ini;
      break;
    }
  }
  chosen ??= firstWithIni;
  chosenIni ??= firstWithIniText;
  if (chosen == null || chosenIni == null) return null;

  final ini = _substituteDns(chosenIni, root);


  final description = root['description'];
  final hostName = root['hostName'];
  final containerName = chosen['container'];
  final label = (description is String && description.isNotEmpty)
      ? description
      : (hostName is String && hostName.isNotEmpty)
          ? hostName
          : (containerName is String && containerName.isNotEmpty)
              ? containerName
              : null;

  return parseWireguardIni(ini, nameHint: label, dropped: dropped);
}













List<WireguardSpec>? parseAmneziaVpnUriAll(String link,
    {List<XrayDropVerdict>? verdicts}) {
  final t = link.trim();
  if (!t.startsWith('vpn://')) return null;
  final bareIni = _decodeBareIni(t);
  if (bareIni != null) {
    final v = XrayDropVerdict();
    verdicts?.add(v);
    final n = parseWireguardIni(bareIni, dropped: v);
    return n == null ? const [] : [n];
  }
  final root = _decodeAmneziaRoot(t);
  if (root == null) return null;
  final containers = root['containers'];
  if (containers is! List || containers.isEmpty) return null;

  final entries = <({Map c, String ini})>[];
  for (final c in containers) {
    if (c is! Map) continue;
    for (final proto in const ['awg', 'wireguard']) {
      final ini = _extractIni(c[proto]);
      if (ini != null) entries.add((c: c, ini: _substituteDns(ini, root)));
    }
  }
  if (entries.isEmpty) return null;

  final defaultContainer = root['defaultContainer'];
  var chosen = entries.indexWhere((e) =>
      defaultContainer is String && e.c['container'] == defaultContainer);
  if (chosen < 0) chosen = 0;

  final description = root['description'];
  final hostName = root['hostName'];
  final profile = (description is String && description.isNotEmpty)
      ? description
      : (hostName is String && hostName.isNotEmpty)
          ? hostName
          : null;

  final out = <WireguardSpec>[];
  for (var i = 0; i < entries.length; i++) {
    final name = entries[i].c['container'];
    final containerName = name is String && name.isNotEmpty ? name : null;
    final String? label;
    if (i == chosen) {
      label = profile ?? containerName;
    } else if (profile != null && containerName != null) {
      label = '$profile $containerName';
    } else {
      label = profile ?? containerName;
    }
    final v = XrayDropVerdict();
    verdicts?.add(v);
    final n = parseWireguardIni(entries[i].ini, nameHint: label, dropped: v);
    if (n != null) out.add(n);
  }
  return out;
}











String? _decodeBareIni(String linkTrimmed) {
  final bytes = decodeBase64Safe(linkTrimmed.substring('vpn://'.length));
  if (bytes == null) return null;
  String text;
  try {
    text = utf8.decode(bytes);
  } catch (_) {
    return null;
  }
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final l = raw.trim();
    if (l.isEmpty || l.startsWith('#') || l.startsWith(';')) continue;
    return l.startsWith('[') ? text : null;
  }
  return null;
}




Map<String, dynamic>? _decodeAmneziaRoot(String linkTrimmed) {
  final bytes = decodeBase64Safe(linkTrimmed.substring('vpn://'.length));
  if (bytes == null) return null;

  final json = _inflate(bytes);
  if (json == null) return null;

  Object root;
  try {
    root = jsonDecode(json);
  } catch (_) {
    return null;
  }
  if (root is! Map<String, dynamic>) return null;
  return root;
}


const int _maxInflated = 4 << 20;


String? _inflate(List<int> bytes) {
  if (bytes.length > 4) {
    final claimed = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    if (claimed <= _maxInflated) {
      try {
        return utf8.decode(zlib.decode(bytes.sublist(4)));
      } catch (_) {

      }
    }
  }
  try {
    final s = utf8.decode(bytes);
    return s.trimLeft().startsWith('{') ? s : null;
  } catch (_) {
    return null;
  }
}



String? _extractIni(Object? protoObj) {
  if (protoObj is! Map) return null;
  Object? lastConfig = protoObj['last_config'];
  if (lastConfig is String) {
    try {
      lastConfig = jsonDecode(lastConfig);
    } catch (_) {
      return null;
    }
  }
  if (lastConfig is! Map) return null;
  final ini = lastConfig['config'];
  if (ini is! String) return null;
  if (!ini.contains('[Interface]') || !ini.contains('[Peer]')) return null;
  return _withLastConfigMtu(ini, lastConfig['mtu']);
}







String _withLastConfigMtu(String ini, Object? mtuRaw) {
  int? mtu;
  if (mtuRaw is num) {
    mtu = mtuRaw.toInt();
  } else if (mtuRaw is String) {
    mtu = int.tryParse(mtuRaw.trim());
  }
  if (mtu == null || mtu <= 0) return ini;
  final lines = ini.split(RegExp(r'\r?\n'));
  var section = '';
  var ifaceIdx = -1;
  for (var i = 0; i < lines.length; i++) {
    final t = lines[i].trim();
    if (t.startsWith('[')) {
      section = t.toLowerCase();
      if (section == '[interface]' && ifaceIdx < 0) ifaceIdx = i;
      continue;
    }
    if (section != '[interface]') continue;
    final eq = t.indexOf('=');
    if (eq > 0 && t.substring(0, eq).trim().toLowerCase() == 'mtu') return ini;
  }
  if (ifaceIdx < 0) return ini;
  lines.insert(ifaceIdx + 1, 'MTU = $mtu');
  return lines.join('\n');
}




String _substituteDns(String ini, Map<String, dynamic> root) {
  final values = <String, String>{
    r'$PRIMARY_DNS': _profileString(root['dns1']),
    r'$SECONDARY_DNS': _profileString(root['dns2']),
  };
  final out = <String>[];
  for (final line in ini.split('\n')) {
    final m = RegExp(r'^(\s*DNS\s*=\s*)(.*)$').firstMatch(line);
    if (m == null) {
      out.add(line);
      continue;
    }
    final items = <String>[];
    for (final raw in m.group(2)!.split(',')) {
      var item = raw.trim();
      if (item.isEmpty) continue;
      if (item.startsWith(r'$')) {


        item = values[item] ?? '';
        if (item.isEmpty) continue;
      }
      items.add(item);
    }

    if (items.isNotEmpty) out.add('${m.group(1)}${items.join(', ')}');
  }
  return out.join('\n');
}

String _profileString(Object? v) => v is String ? v.trim() : '';
