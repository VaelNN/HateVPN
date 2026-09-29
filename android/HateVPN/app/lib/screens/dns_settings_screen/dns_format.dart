

String formatRulePreview(Map<String, dynamic>? body, {required String kind}) {
  if (body == null) {

    return kind == 'preset' ? '(preset disabled — orphan)'
        : kind == 'template' ? '(missing in template)'
        : '';
  }
  final parts = <String>[];
  final clean = Map<String, dynamic>.from(body)
    ..remove('name')
    ..remove('enabled_default');
  for (final entry in clean.entries) {
    final v = entry.value;
    if (v is List && v.length > 3) {
      parts.add('${entry.key}: [${v.take(2).join(', ')}, …]');
    } else if (v is List) {
      parts.add('${entry.key}: ${v.join(', ')}');
    } else {
      parts.add('${entry.key}: $v');
    }
  }
  return parts.join(' · ');
}





String formatRulesPreview(List<Map<String, dynamic>> bodies,
    {required String kind}) {
  if (bodies.isEmpty) return '(no DNS rules emitted)';
  return bodies.map((b) => formatRulePreview(b, kind: kind)).join('\n');
}
