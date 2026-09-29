



















library;

import 'dart:convert' show Utf8Decoder;


enum DecodeMode {

  query,


  path,
}







String percentDecodeOnce(String raw, {DecodeMode mode = DecodeMode.query}) {
  if (raw.isEmpty) return raw;
  final hasPlus = mode == DecodeMode.query && raw.contains('+');
  if (!raw.contains('%') && !hasPlus) return raw;

  final out = StringBuffer();
  final bytes = <int>[];

  void flush() {
    if (bytes.isEmpty) return;
    out.write(_utf8OrRaw(bytes));
    bytes.clear();
  }

  for (var i = 0; i < raw.length; i++) {
    final ch = raw.codeUnitAt(i);
    if (ch == 0x25   && i + 2 < raw.length) {
      final hi = _hex(raw.codeUnitAt(i + 1));
      final lo = _hex(raw.codeUnitAt(i + 2));
      if (hi >= 0 && lo >= 0) {
        bytes.add(hi * 16 + lo);
        i += 2;
        continue;
      }
    }
    flush();
    if (ch == 0x2B   && mode == DecodeMode.query) {
      out.write(' ');
    } else {
      out.writeCharCode(ch);
    }
  }
  flush();
  return out.toString();
}








String decodeExtra(
  String value, {
  DecodeMode mode = DecodeMode.query,
  int? passes,
  int max = 16,
}) {
  var v = value;
  final limit = passes ?? max;
  for (var i = 0; i < limit; i++) {
    if (!v.contains('%')) break;
    final next = percentDecodeOnce(v, mode: mode);

    if (next == v) break;
    v = next;
    if (passes == null) continue;
  }
  return v;
}





String _utf8OrRaw(List<int> bytes) => decodeUtf8Lenient(bytes);












String decodeUtf8Lenient(List<int> bytes) {
  try {
    return const Utf8Decoder().convert(bytes);
  } on FormatException {

  }
  final out = StringBuffer();
  var inBad = false;
  var i = 0;
  while (i < bytes.length) {
    final n = _utf8SeqLen(bytes, i);
    if (n == 0) {
      if (!inBad) out.writeCharCode(0xFFFD);
      inBad = true;
      i++;
      continue;
    }
    inBad = false;
    out.write(const Utf8Decoder().convert(bytes, i, i + n));
    i += n;
  }
  return out.toString();
}



int _utf8SeqLen(List<int> b, int i) {
  final c = b[i] & 0xFF;
  if (c < 0x80) return 1;
  int n;
  var lo = 0x80, hi = 0xBF;
  if (c >= 0xC2 && c <= 0xDF) {
    n = 2;
  } else if (c >= 0xE0 && c <= 0xEF) {
    n = 3;
    if (c == 0xE0) lo = 0xA0;
    if (c == 0xED) hi = 0x9F;
  } else if (c >= 0xF0 && c <= 0xF4) {
    n = 4;
    if (c == 0xF0) lo = 0x90;
    if (c == 0xF4) hi = 0x8F;
  } else {
    return 0;
  }
  if (i + n > b.length) return 0;
  final c1 = b[i + 1] & 0xFF;
  if (c1 < lo || c1 > hi) return 0;
  for (var k = 2; k < n; k++) {
    final ck = b[i + k] & 0xFF;
    if (ck < 0x80 || ck > 0xBF) return 0;
  }
  return n;
}

int _hex(int c) {
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
  if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
  return -1;
}
