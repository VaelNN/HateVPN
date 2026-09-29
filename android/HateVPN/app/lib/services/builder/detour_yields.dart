import 'dart:convert' show jsonDecode, jsonEncode;

import '../../models/node_warning.dart' show RegistryWarning;
import '../contract/body_edit.dart' show applyRegistryEdits, editBodyPath;
import '../contract/body_sanitizer.dart' show yieldToManaged;














List<RegistryWarning> yieldToBuildDetour(
  Map<String, dynamic> body, {
  bool authored = false,
}) {
  final edited = authored
      ? (jsonDecode(jsonEncode(body)) as Map).cast<String, dynamic>()
      : body;
  final ws = yieldToManaged(edited, 'detour');
  final out = applyRegistryEdits(
    body,
    scheme: '${body['type'] ?? ''}',
    authored: authored,
    edited: edited,
    warnings: ws,
  );
  final fragmentGone =
      out.any((w) => w.path == 'tls.fragment' && w.applied);
  if (fragmentGone) {
    final tls = body['tls'];
    if (tls is Map<String, dynamic> &&
        tls.containsKey('fragment_fallback_delay') &&
        tls['record_fragment'] != true) {
      editBodyPath(
        body,
        authored: authored,
        code: 'detour_with_tls_fragment',
        path: 'tls.fragment_fallback_delay',
        remove: true,
      );
    }
  }
  return out;
}
