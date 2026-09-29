







library;

const int _base = 36;
const int _tMin = 1;
const int _tMax = 26;
const int _skew = 38;
const int _damp = 700;
const int _initialBias = 72;
const int _initialN = 128;
const int _delimiter = 0x2D;


int _encodeDigit(int d) => d + (d < 26 ? 97 : 22);

int _adapt(int delta, int numPoints, bool firstTime) {
  delta = firstTime ? delta ~/ _damp : delta ~/ 2;
  delta += delta ~/ numPoints;
  var k = 0;
  while (delta > ((_base - _tMin) * _tMax) ~/ 2) {
    delta ~/= _base - _tMin;
    k += _base;
  }
  return k + ((_base - _tMin + 1) * delta) ~/ (delta + _skew);
}



String punycodeEncode(String input) {
  final codePoints = input.runes.toList();
  final output = StringBuffer();


  var basicCount = 0;
  for (final cp in codePoints) {
    if (cp < 0x80) {
      output.writeCharCode(cp);
      basicCount++;
    }
  }
  final handled = basicCount;
  if (basicCount > 0) output.writeCharCode(_delimiter);

  var n = _initialN;
  var delta = 0;
  var bias = _initialBias;
  var processed = handled;

  while (processed < codePoints.length) {

    var m = 0x7fffffff;
    for (final cp in codePoints) {
      if (cp >= n && cp < m) m = cp;
    }
    delta += (m - n) * (processed + 1);
    n = m;

    for (final cp in codePoints) {
      if (cp < n) delta++;
      if (cp == n) {
        var q = delta;
        for (var k = _base;; k += _base) {
          final t = k <= bias
              ? _tMin
              : (k >= bias + _tMax ? _tMax : k - bias);
          if (q < t) break;
          output.writeCharCode(_encodeDigit(t + (q - t) % (_base - t)));
          q = (q - t) ~/ (_base - t);
        }
        output.writeCharCode(_encodeDigit(q));
        bias = _adapt(delta, processed + 1, processed == handled);
        delta = 0;
        processed++;
      }
    }
    delta++;
    n++;
  }
  return output.toString();
}





String domainToAscii(String input) {
  if (!input.runes.any((r) => r >= 0x80)) return input;
  return input.split('.').map((label) {
    if (label.isEmpty) return label;
    if (!label.runes.any((r) => r >= 0x80)) return label;
    return 'xn--${punycodeEncode(label)}';
  }).join('.');
}
