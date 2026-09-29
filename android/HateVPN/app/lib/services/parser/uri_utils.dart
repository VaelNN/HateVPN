import 'dart:convert';
import 'dart:math';

import '../../models/node_spec.dart' show Awg;
import '../../models/node_warning.dart';
import '../app_log.dart';
import 'engine/decoders.dart' show decodeUtf8Lenient;


const int maxURILength = 65536;







const int kMaxDetourDepth = 8;







const int maxAmneziaLinkLength = 524288;



List<int>? decodeBase64Safe(String s) {
  final input = s.replaceAll(RegExp(r'\s+'), '');
  for (final codec in [base64Url, base64]) {
    for (final pad in [true, false]) {
      try {
        var attempt = input;
        if (pad) {
          final rem = attempt.length % 4;
          if (rem == 2) attempt += '==';
          if (rem == 3) attempt += '=';
        }
        return codec.decode(attempt);
      } catch (_) {}
    }
  }
  return null;
}



final Map<int, int> _b64CharValue = {
  for (var i = 0; i < 26; i++) 'A'.codeUnitAt(0) + i: i,
  for (var i = 0; i < 26; i++) 'a'.codeUnitAt(0) + i: 26 + i,
  for (var i = 0; i < 10; i++) '0'.codeUnitAt(0) + i: 52 + i,
  '+'.codeUnitAt(0): 62,
  '-'.codeUnitAt(0): 62,
  '/'.codeUnitAt(0): 63,
  '_'.codeUnitAt(0): 63,
};

















List<int>? decodeBase64Lenient(String s) => _decodeBase64Lenient(s);


final RegExp _reB64Padding = RegExp(r'=+$');

List<int>? _decodeBase64Lenient(String s) {
  final trimmed = s.replaceAll(_reB64Padding, '');
  if (trimmed.isEmpty) return null;
  final values = <int>[];
  for (final unit in trimmed.codeUnits) {
    final v = _b64CharValue[unit];
    if (v == null) return null;
    values.add(v);
  }


  final rem = values.length % 4;
  if (rem == 1) return null;

  final out = <int>[];
  var i = 0;
  while (i + 4 <= values.length) {
    final n = (values[i] << 18) |
        (values[i + 1] << 12) |
        (values[i + 2] << 6) |
        values[i + 3];
    out.add((n >> 16) & 0xFF);
    out.add((n >> 8) & 0xFF);
    out.add(n & 0xFF);
    i += 4;
  }
  if (rem == 2) {
    final n = (values[i] << 18) | (values[i + 1] << 12);
    out.add((n >> 16) & 0xFF);
  } else if (rem == 3) {
    final n = (values[i] << 18) | (values[i + 1] << 12) | (values[i + 2] << 6);
    out.add((n >> 16) & 0xFF);
    out.add((n >> 8) & 0xFF);
  }
  return out;
}












String? normalizeWGKey(String value) {
  final raw = _decodeBase64Lenient(value);
  if (raw == null || raw.length != 32) return null;
  return base64.encode(raw);
}






List<int>? parseReserved(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  if (s.contains(',')) {
    final parts = s.split(',').map((e) => e.trim()).toList();
    if (parts.length != 3) return null;
    final out = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return null;
      out.add(n);
    }
    return out;
  }
  final bytes = decodeBase64Safe(s);
  if (bytes == null || bytes.length != 3) return null;
  if (bytes.any((b) => b < 0 || b > 255)) return null;
  return List<int>.from(bytes);
}



String utf8Lossy(List<int> bytes) => decodeUtf8Lenient(bytes);


String sanitizeForDisplay(String s) {
  if (s.isEmpty) return s;
  final buf = StringBuffer();
  for (final r in s.runes) {
    if (r == 9 || r == 10 || r == 13) {
      buf.writeCharCode(r);
      continue;
    }
    if (r <= 0x1F || r == 0x7F) continue;
    buf.writeCharCode(r);
  }
  return buf.toString();
}



String tagFromLabel(String label, String scheme, String server, int port) {
  if (label.trim().isNotEmpty) {
    return label.trim().replaceAll('🇪🇳', '🇬🇧');
  }
  return '$scheme-$server-$port';
}








String decodeFragment(String fragment) {
  if (fragment.isEmpty) return '';
  try {
    return sanitizeForDisplay(Uri.decodeComponent(fragment)).trim();
  } catch (_) {
    return sanitizeForDisplay(fragment).trim();
  }
}












final _rng = Random();
String newUuidV4() {
  final b = List<int>.generate(16, (_) => _rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  return '${h(0)}${h(1)}${h(2)}${h(3)}-'
      '${h(4)}${h(5)}-'
      '${h(6)}${h(7)}-'
      '${h(8)}${h(9)}-'
      '${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
}





















String normalizePacketEncoding(
  String raw, {
  String? tag,
  List<NodeWarning>? warnings,
}) {
  final v = raw.trim().toLowerCase();
  if (v.isEmpty || v == 'none') return '';
  if (v == 'xudp' || v == 'packetaddr') return v;
  AppLog.I.warning(
    "unknown packetEncoding='$raw'${tag != null ? ' in $tag' : ''} — dropping",
  );
  warnings?.add(PacketEncodingUnknownWarning(raw.trim()));
  return '';
}





















void normalizeAwgHeaderKey(Awg awg) {
  final raw = awg.fields[Awg.headerKey];
  if (raw is! String || raw.trim().isEmpty) return;
  final bytes = _decodeBase64Lenient(raw.trim());
  if (bytes == null || bytes.length != 32) return;
  awg.fields[Awg.headerKey] = base64.encode(bytes);
}




Object? parseWgKeepalive(String? raw) {
  final v = (raw ?? '').trim();
  if (v.isEmpty) return null;
  final n = int.tryParse(v);
  if (n != null) return n;
  final r = Awg.parseAwg3Range(v);
  return r is String ? r : null;
}





String ensureCidr(String addr) {
  final s = addr.trim();
  if (s.isEmpty || s.contains('/')) return s;
  return s.contains(':') ? '$s/128' : '$s/32';
}





String encodeUserInfoSlashes(String uri) {
  final schemeEnd = uri.indexOf('://');
  if (schemeEnd < 0) return uri;
  final start = schemeEnd + 3;
  final at = uri.indexOf('@', start);
  if (at < 0) return uri;
  final userInfo = uri.substring(start, at);
  if (!userInfo.contains('/')) return uri;
  return uri.substring(0, start) +
      userInfo.replaceAll('/', '%2F') +
      uri.substring(at);
}







String? queryParamPreservePlus(Uri u, String key) {
  final raw = u.query;
  if (raw.isEmpty) return null;
  for (final part in raw.split('&')) {
    final eq = part.indexOf('=');
    final k = eq < 0 ? part : part.substring(0, eq);
    if (k != key) continue;
    final v = eq < 0 ? '' : part.substring(eq + 1);
    try {
      return Uri.decodeComponent(v);
    } catch (_) {
      return v;
    }
  }
  return null;
}






String? queryParamCI(Map<String, String> q, String key) {
  final lk = key.toLowerCase();
  for (final e in q.entries) {
    if (e.key.toLowerCase() == lk) return e.value;
  }
  return null;
}












bool isValidRealityPublicKey(String pbk) {
  final s = pbk.trim();
  if (s.isEmpty) return false;
  final bytes = decodeBase64Safe(s);
  return bytes != null && bytes.length == 32;
}

















bool urlPathOk(String path) {
  for (var i = 0; i < path.length; i++) {
    if (path.codeUnitAt(i) != 0x25) continue;
    if (i + 2 >= path.length) return false;
    if (!_isHexDigit(path.codeUnitAt(i + 1)) ||
        !_isHexDigit(path.codeUnitAt(i + 2))) {
      return false;
    }
    i += 2;
  }
  return true;
}

bool _isHexDigit(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x46) ||
    (c >= 0x61 && c <= 0x66);











String normalizeRealityShortId(String s) {
  final buf = StringBuffer();
  for (final r in s.trim().runes) {
    if (r >= 0x30 && r <= 0x39) {
      buf.writeCharCode(r);
    } else if (r >= 0x61 && r <= 0x66) {
      buf.writeCharCode(r);
    } else if (r >= 0x41 && r <= 0x46) {
      buf.writeCharCode(r + 32);
    }
  }
  final out = buf.toString();
  return (out.length > 16 || out.length.isOdd) ? '' : out;
}









String normalizeSingboxDuration(String v) {
  if (v.isEmpty) return v;
  final isAllDigits = RegExp(r'^[0-9]+$').hasMatch(v);
  return isAllDigits ? '${v}s' : v;
}





const kVmessSecurityMethods = <String>{
  'auto',
  'none',
  'zero',
  'aes-128-cfb',
  'aes-128-gcm',
  'chacha20-poly1305',
};























String normalizeVmessSecurity(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty || s == 'null' || s == 'undefined') return 'auto';
  if (kVmessSecurityMethods.contains(s)) return s;
  if (s == 'chacha20-ietf-poly1305') return 'chacha20-poly1305';
  AppLog.I.warning(
      "vmess: security '$raw' is not accepted by the core, using 'auto'");
  return 'auto';
}










const shadowsocksLegacyMethods = <String>{
  'aes-128-ctr',
  'aes-192-ctr',
  'aes-256-ctr',
  'aes-128-cfb',
  'aes-192-cfb',
  'aes-256-cfb',
  'rc4-md5',
  'chacha20-ietf',
  'xchacha20',
};





const shadowsocksMethods = {
  '2022-blake3-aes-128-gcm',
  '2022-blake3-aes-256-gcm',
  '2022-blake3-chacha20-poly1305',
  'none',
  'aes-128-gcm',
  'aes-192-gcm',
  'aes-256-gcm',
  'chacha20-ietf-poly1305',
  'xchacha20-ietf-poly1305',
  ...shadowsocksLegacyMethods,
};

bool isValidShadowsocksMethod(String method) =>
    shadowsocksMethods.contains(method);



bool isLegacyShadowsocksMethod(String method) =>
    shadowsocksLegacyMethods.contains(method);


const plaintextVlessPorts = {80, 8080, 8880, 2052, 2082, 2086, 2095};


String encodeParam(String s) => Uri.encodeQueryComponent(s).replaceAll('+', '%20');


String encodeFragment(String s) =>
    Uri.encodeComponent(s).replaceAll('+', '%20');


String buildQuery(Map<String, String> params) {
  if (params.isEmpty) return '';
  final keys = params.keys.toList()..sort();
  return keys
      .map((k) => '${encodeParam(k)}=${encodeParam(params[k]!)}')
      .join('&');
}
