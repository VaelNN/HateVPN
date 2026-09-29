







library;

import 'punycode.dart';



List<String> splitRaw(String text) => text
    .split(RegExp(r'[\n,]'))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();









List<String> normalizedDomains(
  String raw, {
  bool stripLeadingDot = false,
}) =>
    splitRaw(raw).map((s) {
      var v = s.toLowerCase();
      if (v.startsWith('http://')) v = v.substring(7);
      if (v.startsWith('https://')) v = v.substring(8);
      if (v.endsWith('/')) v = v.substring(0, v.length - 1);
      if (stripLeadingDot && v.startsWith('.')) v = v.substring(1);
      return domainToAscii(v);
    }).where((s) => s.isNotEmpty).toList();



List<String> normalizedKeywords(String raw) =>
    splitRaw(raw).map((s) => s.toLowerCase()).toList();



List<String> normalizedCidrs(String raw) => splitRaw(raw).map((s) {
      if (!s.contains('/')) return s.contains(':') ? '$s/128' : '$s/32';
      return s;
    }).toList();



List<String> normalizedPorts(String raw) => splitRaw(raw);
List<String> normalizedPortRanges(String raw) => splitRaw(raw);
