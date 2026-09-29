import '../context.dart';
import 'request.dart';
import 'response.dart';
import 'router.dart';




typedef Next = Future<DebugResponse> Function();


typedef Middleware = Future<DebugResponse> Function(
  DebugRequest req,
  DebugContext ctx,
  Next next,
);















Future<DebugResponse> runPipeline(
  DebugRequest req,
  DebugContext ctx,
  List<Middleware> middlewares,
  Handler terminal,
) {
  var i = 0;
  Future<DebugResponse> next() {
    if (i >= middlewares.length) return terminal(req, ctx);
    final mw = middlewares[i++];
    return mw(req, ctx, next);
  }

  return next();
}
