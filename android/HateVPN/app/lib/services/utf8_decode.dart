import 'dart:convert';


String? utf8DecodeOrNull(List<int> bytes) {
  try {
    return const Utf8Decoder(allowMalformed: false).convert(bytes);
  } catch (_) {
    return null;
  }
}
