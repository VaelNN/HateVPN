
































library;


final class CoreRejection {
  const CoreRejection({
    required this.kind,
    required this.index,
    required this.type,
    required this.tag,
    required this.reason,
  });


  final String kind;


  final int index;


  final String type;


  final String tag;



  final String reason;

  @override
  String toString() => 'CoreRejection($kind[$index] $type[$tag]: $reason)';
}

const _prefix = 'initialize ';
const _sep = ']: ';















CoreRejection? parseCoreRejection(String line, Set<String> configTags) {
  final raw = line.trim();
  var at = raw.indexOf(_prefix);
  while (at >= 0) {
    final hit = _parseAt(raw.substring(at + _prefix.length), configTags);
    if (hit != null) return hit;
    at = raw.indexOf(_prefix, at + 1);
  }
  return null;
}


CoreRejection? _parseAt(String after, Set<String> configTags) {
  var rest = after;


  final String kind;
  if (rest.startsWith('outbound[')) {
    kind = 'outbound';
  } else if (rest.startsWith('endpoint[')) {
    kind = 'endpoint';
  } else {

    return null;
  }
  rest = rest.substring(kind.length + 1);


  final close = rest.indexOf(']');
  if (close <= 0) return null;
  final digits = rest.substring(0, close);
  final index = int.tryParse(digits);
  if (index == null || !_isDigits(digits)) return null;
  rest = rest.substring(close + 1);


  if (!rest.startsWith(' ')) return null;
  rest = rest.substring(1);


  final open = rest.indexOf('[');
  if (open <= 0) return null;
  final type = rest.substring(0, open);
  if (type.contains(']') || type.contains(' ')) return null;
  rest = rest.substring(open + 1);



  var cut = rest.lastIndexOf(_sep);
  while (cut >= 0) {
    final tag = rest.substring(0, cut);
    if (configTags.contains(tag)) {
      return CoreRejection(
        kind: kind,
        index: index,
        type: type,
        tag: tag,
        reason: rest.substring(cut + _sep.length),
      );
    }
    cut = cut == 0 ? -1 : rest.lastIndexOf(_sep, cut - 1);
  }
  return null;
}

bool _isDigits(String s) {
  if (s.isEmpty) return false;
  for (final c in s.codeUnits) {
    if (c < 0x30 || c > 0x39) return false;
  }
  return true;
}
