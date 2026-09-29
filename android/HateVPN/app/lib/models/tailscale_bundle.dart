



library;



const String kTailscaleHostnamePrefix = 'LxBox';


const int kTailscaleHostnameMaxLength = 63;











String defaultTailscaleHostname(String model) {
  final suffix = _dnsLabelSegment(model);
  if (suffix.isEmpty) return kTailscaleHostnamePrefix;
  final room = kTailscaleHostnameMaxLength - kTailscaleHostnamePrefix.length - 1;
  final trimmed = suffix.length > room

      ? _stripDashes(suffix.substring(0, room))
      : suffix;
  if (trimmed.isEmpty) return kTailscaleHostnamePrefix;
  return '$kTailscaleHostnamePrefix-$trimmed';
}








String _dnsLabelSegment(String model) {
  final buf = StringBuffer();
  for (final code in model.toLowerCase().codeUnits) {
    final isDigit = code >= 0x30 && code <= 0x39;
    final isLetter = code >= 0x61 && code <= 0x7A;
    buf.writeCharCode(isDigit || isLetter ? code : 0x2D);
  }
  return _stripDashes(buf.toString());
}


String _stripDashes(String s) {
  final collapsed = s.replaceAll(RegExp(r'-+'), '-');
  return collapsed.replaceAll(RegExp(r'^-|-$'), '');
}
