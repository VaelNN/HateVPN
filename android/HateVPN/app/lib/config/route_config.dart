import 'package:json5/json5.dart';







class RouteConfig {
  const RouteConfig._();


  static String? finalTag(String raw) {
    try {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      final dynamic decoded = json5Decode(trimmed);
      if (decoded is! Map) return null;
      final route = decoded['route'];
      if (route is! Map) return null;
      final f = route['final'];
      return f?.toString();
    } catch (_) {
      return null;
    }
  }
}
