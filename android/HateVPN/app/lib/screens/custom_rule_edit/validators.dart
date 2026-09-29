









library;




final RegExp _domainRegex = RegExp(
  r'^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$',
);

bool isValidDomain(String v) => _domainRegex.hasMatch(v);







final RegExp _domainSuffixRegex = RegExp(
  r'^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$',
);

bool isValidDomainSuffix(String v) => _domainSuffixRegex.hasMatch(v);



bool isValidKeyword(String v) => v.isNotEmpty && !v.contains(RegExp(r'\s'));



bool isValidCidr(String v) {
  final parts = v.split('/');
  if (parts.length != 2) return false;
  final mask = int.tryParse(parts[1]);
  if (mask == null) return false;
  if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(parts[0])) {
    if (mask < 0 || mask > 32) return false;
    return parts[0].split('.').every((o) {
      final n = int.tryParse(o);
      return n != null && n >= 0 && n <= 255;
    });
  }
  if (RegExp(r'^[0-9a-fA-F:]+$').hasMatch(parts[0]) &&
      parts[0].contains(':')) {
    return mask >= 0 && mask <= 128;
  }
  return false;
}


bool isValidPort(String v) {
  final n = int.tryParse(v);
  return n != null && n >= 0 && n <= 65535;
}



bool isValidPortRange(String v) {
  final m = RegExp(r'^(\d*):(\d*)$').firstMatch(v);
  if (m == null) return false;
  final lo = m.group(1)!;
  final hi = m.group(2)!;
  if (lo.isEmpty && hi.isEmpty) return false;
  int? loN, hiN;
  if (lo.isNotEmpty) {
    loN = int.tryParse(lo);
    if (loN == null || loN < 0 || loN > 65535) return false;
  }
  if (hi.isNotEmpty) {
    hiN = int.tryParse(hi);
    if (hiN == null || hiN < 0 || hiN > 65535) return false;
  }
  if (loN != null && hiN != null && loN > hiN) return false;
  return true;
}


bool isValidUrl(String s) {
  final u = Uri.tryParse(s);
  return u != null &&
      (u.scheme == 'http' || u.scheme == 'https') &&
      u.host.isNotEmpty;
}



final RegExp _bssidRegex =
    RegExp(r'^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$');

bool isValidBssid(String v) =>
    v.isEmpty || _bssidRegex.hasMatch(v.trim());
