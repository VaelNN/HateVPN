part of '../post_steps.dart';









void applyMixedCaseSni(Map<String, dynamic> config, Map<String, String> vars) {
  if (vars['tls_mixed_case_sni'] != 'true') return;
  final rng = Random.secure();
  final outbounds = config['outbounds'] as List<dynamic>? ?? const [];
  for (final ob in outbounds) {
    if (ob is! Map<String, dynamic>) continue;
    if (ob.containsKey('detour')) continue;
    final tls = ob['tls'];
    if (tls is! Map<String, dynamic>) continue;





    final reality = tls['reality'];
    if (reality is Map<String, dynamic> && reality['enabled'] == true) continue;
    final sn = tls['server_name'];
    if (sn is! String || sn.isEmpty) continue;
    tls['server_name'] = _randomizeHostCase(sn, rng);
  }
}

String _randomizeHostCase(String host, Random rng) {

  final labels = host.split('.');
  for (var i = 0; i < labels.length; i++) {
    final label = labels[i];
    if (label.startsWith('xn--')) continue;
    final buf = StringBuffer();
    for (final cu in label.codeUnits) {

      final isUpper = cu >= 0x41 && cu <= 0x5A;
      final isLower = cu >= 0x61 && cu <= 0x7A;
      if (isUpper || isLower) {
        buf.writeCharCode(rng.nextBool() ? (cu | 0x20) : (cu & ~0x20));
      } else {
        buf.writeCharCode(cu);
      }
    }
    labels[i] = buf.toString();
  }
  return labels.join('.');
}









void applyTlsFragment(Map<String, dynamic> config, Map<String, String> vars) {
  final fragment = vars['tls_fragment'] == 'true';
  final recordFragment = vars['tls_record_fragment'] == 'true';
  if (!fragment && !recordFragment) return;

  final fallbackDelay = vars['tls_fragment_fallback_delay'] ?? '500ms';
  final outbounds = config['outbounds'] as List<dynamic>? ?? const [];
  for (final ob in outbounds) {
    if (ob is! Map<String, dynamic>) continue;
    if (ob.containsKey('detour')) continue;
    final addFragment = fragment && fieldAllowedOn(ob, 'tls.fragment');
    final addRecord =
        recordFragment && fieldAllowedOn(ob, 'tls.record_fragment');
    if (!addFragment && !addRecord) continue;
    Map<String, dynamic> tls;


    if (ob['type'] == 'masque') {
      tls = (ob['tls'] ??= <String, dynamic>{}) as Map<String, dynamic>;
    } else {
      final t = ob['tls'];
      if (t is! Map<String, dynamic>) continue;
      if (t['enabled'] != true) continue;
      tls = t;
    }
    if (addFragment) tls['fragment'] = true;
    if (addRecord) tls['record_fragment'] = true;
    tls['fragment_fallback_delay'] = fallbackDelay;
  }
}














List<RegistryWarning> applyDetourYields(
  Map<String, dynamic> config, {
  Set<Map<String, dynamic>> authored = const {},
}) {
  final out = <RegistryWarning>[];
  for (final key in const ['outbounds', 'endpoints']) {
    final list = config[key];
    if (list is! List) continue;
    for (final e in list) {
      if (e is! Map<String, dynamic>) continue;
      if (!e.containsKey('detour')) continue;
      out.addAll(yieldToBuildDetour(e, authored: authored.contains(e)));
    }
  }
  return out;
}
