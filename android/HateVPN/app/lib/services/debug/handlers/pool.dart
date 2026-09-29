import '../context.dart';
import '../contract/errors.dart';
import '../transport/request.dart';
import '../transport/response.dart';











Future<DebugResponse> poolHandler(DebugRequest req, DebugContext ctx) async {
  if (req.path != '/pool') {
    throw NotFound('pool path: ${req.path}');
  }
  if (req.method != 'GET') {
    throw BadRequest('pool requires GET, got ${req.method}');
  }
  final tag = req.requiredQuery('tag');
  if (tag.isEmpty) throw const BadRequest('"tag" empty');

  final home = ctx.requireHome();
  final slots = await home.getPool(tag);


  if (slots == null) {
    throw const Conflict('cc client unavailable (tunnel down?)');
  }
  return JsonResponse({
    'tag': tag,
    'count': slots.length,
    'slots': [
      for (final s in slots)
        {'slot': s.slot, 'tag': s.tag, 'delay': s.delay, 'alive': s.alive},
    ],
  });
}
