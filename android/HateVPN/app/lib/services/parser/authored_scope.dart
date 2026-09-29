










library;

import '../contract/body_sanitizer.dart' show BodySource;

bool _authored = false;


bool get parsingAuthoredBody => _authored;


BodySource get singboxBodySource =>
    _authored ? BodySource.singbox : BodySource.other;



T withAuthoredBody<T>(bool on, T Function() body) {
  final prev = _authored;
  _authored = on;
  try {
    return body();
  } finally {
    _authored = prev;
  }
}





bool _own = false;

bool get parsingOwnSource => _own;

T withOwnSource<T>(bool on, T Function() body) {
  final prev = _own;
  _own = on;
  try {
    return body();
  } finally {
    _own = prev;
  }
}
