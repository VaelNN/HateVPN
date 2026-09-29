import '../../support/active_time_tracker.dart';
import '../../support/support_message.dart';
import '../../support/support_state.dart';
import '../../version_info.dart';
import '../context.dart';
import '../contract/errors.dart';
import '../transport/request.dart';
import '../transport/response.dart';

















Future<DebugResponse> supportHandler(DebugRequest req, DebugContext ctx) async {
  return switch ((req.method, req.path)) {
    ('GET', '/support/state') => _state(),
    ('POST', '/support/reset') => _reset(req),
    ('POST', '/support/preview') => _preview(req, ctx),
    _ => throw NotFound('support: ${req.method} ${req.path}'),
  };
}

Future<DebugResponse> _state() async {
  final s = SupportState.I;
  return JsonResponse({
    'app_version': VersionInfo.I.version,
    'total_active_seconds': await ActiveTimeTracker.I.totalSeconds(),
    'state': {
      'active_seconds': await s.getInt('active_seconds'),
      'session_credited': await s.getInt('session_credited'),
      'read': await s.getStringMap('read'),
      'baseline_seconds': await s.getInt('baseline_seconds'),
      'baseline_version': await s.getString('baseline_version'),
      'snooze_after_seconds': await s.getInt('snooze_after_seconds'),
      'cache_json_bytes': (await s.getString('cache_json')).length,
    },
  });
}




Future<DebugResponse> _reset(DebugRequest req) async {
  final keepActive =
      (req.query['keep_active'] ?? 'true').toLowerCase() != 'false';
  final wiped = <String, Object>{
    'read': <String, String>{},
    'baseline_seconds': 0,
    'baseline_version': '',
    'snooze_after_seconds': 0,
    'cache_json': '',
    if (!keepActive) 'active_seconds': 0,
    if (!keepActive) 'session_credited': 0,
  };
  await SupportState.I.setAll(wiped);
  return JsonResponse({
    'ok': true,
    'action': 'support-reset',
    'kept_active_seconds': keepActive,
  });
}

Future<DebugResponse> _preview(DebugRequest req, DebugContext ctx) async {
  final home = ctx.home;
  if (home == null) throw const Conflict('home controller not ready');
  final message = SupportMessage.fromJson(req.jsonBodyAsMap());
  if (message == null) {
    throw const BadRequest(
        'body must be a feed message object: {"id", "i18n": {"en": {"title", "message", "links"}}}');
  }
  final dry = (req.query['dry'] ?? 'true').toLowerCase() != 'false';
  final snoozeHours = int.tryParse(req.query['snooze_hours'] ?? '') ?? 10;
  home.requestSupportPreview(SupportPreviewRequest(
    feed: SupportFeed(snoozeActiveHours: snoozeHours, messages: [message]),
    message: message,
    dryRun: dry,
  ));
  return JsonResponse({
    'ok': true,
    'action': 'support-preview',
    'id': message.id,
    'dry': dry,
  });
}
