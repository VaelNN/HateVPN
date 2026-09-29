import '../../../controllers/subscription_controller.dart';
import '../../../models/node_spec.dart';
import '../../../models/template_vars.dart';
import '../../contract/body_sanitizer.dart' show carriesPrivateKeyByRegistry;
import '../../tag_resolver.dart';
import '../context.dart';
import '../contract/errors.dart';
import '../transport/request.dart';
import '../transport/response.dart';










Future<DebugResponse> nodesHandler(DebugRequest req, DebugContext ctx) async {
  if (req.path != '/nodes/link') throw NotFound('nodes path: ${req.path}');
  if (req.method != 'GET') {
    throw BadRequest('method ${req.method} not allowed on /nodes/link');
  }
  return _link(req, ctx);
}


















Future<DebugResponse> _link(DebugRequest req, DebugContext ctx) async {
  final sub = ctx.requireSub();
  final tag = (req.q('tag') ?? '').trim();
  if (tag.isEmpty) throw const BadRequest('param "tag" required');

  final hit = _findByTag(tag, sub);
  if (hit == null) throw NotFound('node by tag: $tag');

  if (!req.qBool('reveal')) {
    return JsonResponse({
      'tag': hit.tag,
      'protocol': hit.protocol,
      'private_key': carriesPrivateKeyByRegistry(hit.emit(TemplateVars.empty).map),
      'error': 'reveal required',
    });
  }

  final uri = hit.toUri();
  if (uri.isEmpty) {
    return JsonResponse({
      'tag': hit.tag,
      'protocol': hit.protocol,
      'error': 'node has no link form',
    });
  }
  return JsonResponse({
    'tag': hit.tag,
    'protocol': hit.protocol,
    'uri': uri,

    'private_key': carriesPrivateKeyByRegistry(hit.emit(TemplateVars.empty).map),
  });
}




NodeSpec? _findByTag(String tag, SubscriptionController sub) {
  for (final e in sub.entries) {
    final base = TagResolver.stripPrefix(tag, e.tagPrefix);
    for (final n in e.list.nodes) {
      for (NodeSpec? hop = n; hop != null; hop = hop.chained) {
        if (hop.tag == base || hop.tag == tag) return hop;
      }
    }
  }
  return null;
}
