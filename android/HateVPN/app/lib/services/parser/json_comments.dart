









library;

import 'dart:convert';





String? uncommentedJson(String text) {
  final head = text.trimLeft();
  if (!head.startsWith('{') && !head.startsWith('[')) return null;
  if (_isJson(text)) return null;
  final stripped = stripJsonComments(text);
  if (stripped == null || !_isJson(stripped)) return null;
  return stripped;
}

bool _isJson(String text) {
  try {
    jsonDecode(text);
    return true;
  } on FormatException {
    return false;
  }
}


String? stripJsonComments(String text) {
  final out = StringBuffer();
  var found = false;
  var inString = false;
  var i = 0;
  while (i < text.length) {
    final c = text[i];
    if (inString) {
      out.write(c);
      if (c == r'\' && i + 1 < text.length) {
        out.write(text[i + 1]);
        i += 2;
        continue;
      }
      if (c == '"') inString = false;
      i++;
      continue;
    }
    if (c == '"') {
      inString = true;
      out.write(c);
      i++;
      continue;
    }
    final next = i + 1 < text.length ? text[i + 1] : '';
    if (c == '/' && next == '/') {
      found = true;
      _trimTrailingBlanks(out);
      i = text.indexOf('\n', i);
      if (i < 0) break;
      continue;
    }
    if (c == '/' && next == '*') {
      found = true;
      final end = text.indexOf('*/', i + 2);
      i = end < 0 ? text.length : end + 2;
      continue;
    }
    out.write(c);
    i++;
  }
  return found ? out.toString() : null;
}


void _trimTrailingBlanks(StringBuffer out) {
  final s = out.toString();
  var end = s.length;
  while (end > 0 && (s[end - 1] == ' ' || s[end - 1] == '\t')) {
    end--;
  }
  if (end == s.length) return;
  out
    ..clear()
    ..write(s.substring(0, end));
}
