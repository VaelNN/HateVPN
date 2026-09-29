








String maskSubscriptionUrl(String raw) {
  if (raw.isEmpty) return '';


  if (raw.startsWith('file:')) return 'file:<local>';
  final u = Uri.tryParse(raw);
  if (u == null) return '***';
  if (u.host.isEmpty) return '***';
  return '${u.scheme}://${u.host}/***';
}
