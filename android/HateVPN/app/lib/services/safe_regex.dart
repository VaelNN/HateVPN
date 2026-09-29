








library;






RegExp? tryCompileRegex(
  String pattern, {
  bool caseSensitive = true,
  bool unicode = false,
}) {
  if (pattern.isEmpty) return null;
  try {
    return RegExp(pattern, caseSensitive: caseSensitive, unicode: unicode);
  } on FormatException {
    return null;
  }
}
