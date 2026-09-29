import '../context.dart';
import '../transport/request.dart';
import '../transport/response.dart';





Future<DebugResponse> pingHandler(DebugRequest req, DebugContext ctx) async {
  final uptime = ctx.now().difference(ctx.appStartedAt).inSeconds;
  return JsonResponse({
    'pong': true,
    'server': 'lxbox-debug',
    'uptime_seconds': uptime,
  });
}
