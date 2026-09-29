





String? diagnoseEmptyParse(String rawBody) {
  if (rawBody.isEmpty) {
    return 'Empty response from server';
  }
  final sample = rawBody.length > 512 ? rawBody.substring(0, 512) : rawBody;
  final lowered = sample.toLowerCase().trimLeft();


  if (lowered.startsWith('<!doctype html') ||
      lowered.startsWith('<html') ||
      lowered.contains('<body')) {
    return 'Server returned a web page, not subscription data — '
        'URL may be wrong or requires login';
  }


  if (sample.contains('proxies:') ||
      sample.contains('proxy-groups:') ||
      sample.contains('port: 7890')) {
    return 'This looks like Clash YAML — not supported yet. '
        'Ask provider for URI-list subscription URL';
  }


  final t = sample.trimLeft();
  if ((t.startsWith('{') || t.startsWith('[')) &&
      (sample.contains('"inbounds"') || sample.contains('"routing"'))) {
    return 'Input looks like a full sing-box config — not a subscription. '
        'Use only the outbounds array';
  }




  if (sample.length < 200 && _looksLikePlainMessage(sample)) {
    return 'Server returned a plain message (not a subscription): '
        '"${sample.replaceAll("\n", " ").trim()}"';
  }

  return null;
}






bool _looksLikePlainMessage(String sample) {
  final head = sample.length > 100 ? sample.substring(0, 100) : sample;
  for (final ch in const ['{', '[', ':', '=', '<']) {
    if (head.contains(ch)) return false;
  }

  final trimmed = sample.trim();
  if (trimmed.isEmpty) return false;

  final allowed = RegExp(r'''[A-Za-zА-Яа-яЁё.,!?'"()\-]''');
  var messageLike = 0;
  var nonSpace = 0;
  for (final ch in trimmed.split('')) {
    if (ch.trim().isEmpty) continue;
    nonSpace++;
    if (allowed.hasMatch(ch)) messageLike++;
  }
  if (nonSpace == 0) return false;
  return messageLike * 10 >= nonSpace * 6;
}
