import '../context.dart';
import '../contract/errors.dart';
import 'request.dart';
import 'response.dart';



typedef Handler = Future<DebugResponse> Function(
  DebugRequest req,
  DebugContext ctx,
);









class Router {
  final List<_Route> _routes = [];

  void mount(String prefix, Handler handler) {
    assert(prefix.startsWith('/'), 'prefix must start with /');
    assert(!prefix.endsWith('/') || prefix == '/', 'prefix must not end with / (except root)');
    _routes.add(_Route(prefix, handler));
  }



  List<String> get prefixes => [for (final r in _routes) r.prefix];


  Handler? resolve(String path) {
    _Route? best;
    for (final r in _routes) {
      final matches = path == r.prefix || path.startsWith('${r.prefix}/');
      if (!matches) continue;
      if (best == null || r.prefix.length > best.prefix.length) {
        best = r;
      }
    }
    return best?.handler;
  }


  Future<DebugResponse> handle(DebugRequest req, DebugContext ctx) async {
    final h = resolve(req.path);
    if (h == null) throw NotFound('route: ${req.path}');
    return h(req, ctx);
  }
}

class _Route {
  _Route(this.prefix, this.handler);
  final String prefix;
  final Handler handler;
}
