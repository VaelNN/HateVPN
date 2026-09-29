import '../../models/node_warning.dart';
import '../../models/tls_spec.dart';


















const Set<String> kUtlsFingerprints = {
  'chrome',
  'chrome_psk',
  'chrome_psk_shuffle',
  'chrome_padding_psk_shuffle',
  'chrome_pq',
  'chrome_pq_psk',
  'firefox',
  'edge',
  'safari',
  '360',
  'qq',
  'ios',
  'android',
  'random',
  'randomized',
};
























const Set<String> kRealityHybridFingerprints = {
  'chrome',
  'chrome_psk',
  'chrome_psk_shuffle',
  'chrome_padding_psk_shuffle',
  'chrome_pq',
  'chrome_pq_psk',

  'firefox',

  'safari',
};




bool isRealityHybridFingerprint(String fp) =>
    fp.isEmpty || kRealityHybridFingerprints.contains(fp);



const Map<String, String> _xrayAliasPrefixes = {
  'hellochrome': 'chrome',
  'hellofirefox': 'firefox',
  'helloedge': 'edge',
  'hellosafari': 'safari',
  'hello360': '360',
  'helloqq': 'qq',
  'helloios': 'ios',
  'helloandroid': 'android',









  'hellorandom': 'random',
};




({String value, bool junk}) normalizeUtlsFingerprintValue(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) return (value: '', junk: false);
  if (kUtlsFingerprints.contains(s)) return (value: s, junk: false);
  for (final e in _xrayAliasPrefixes.entries) {
    if (s.startsWith(e.key)) return (value: e.value, junk: false);
  }
  return (value: 'chrome', junk: true);
}




TlsSpec normalizeTlsFingerprint(TlsSpec tls, List<NodeWarning>? warnings) {
  if (!tls.enabled) return tls;
  final fp = tls.fingerprint ?? '';
  final n = normalizeUtlsFingerprintValue(fp);
  final value = n.value;



  if (n.junk) warnings?.add(UnknownFingerprintWarning(fp));







  if (tls.reality != null &&
      value.isNotEmpty &&
      value != 'random' &&
      !isRealityHybridFingerprint(value)) {
    warnings?.add(RealityFingerprintWarning(value));
  }
  if (value == fp) return tls;
  return tls.copyWith(fingerprint: value);
}
