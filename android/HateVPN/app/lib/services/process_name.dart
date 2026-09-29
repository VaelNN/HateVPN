








String packageNameFromProcess(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return '';
  final pkg = s.split(' ').first.trim();

  if (pkg.contains('/') || !pkg.contains('.')) return '';
  return pkg;
}
