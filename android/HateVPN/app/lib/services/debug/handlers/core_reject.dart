import '../../../controllers/subscription_controller.dart';
import '../../../models/core_reject_verdict.dart';
import '../../../models/node_warning.dart' show WarningSeverity;
import '../../../models/server_list.dart';
import '../../../services/node_hash.dart';
import '../../contract/registry_warning.dart';
import '../../core_reject/core_reject_guard.dart';
import '../../core_reject/core_reject_state.dart';
import '../context.dart';
import '../contract/errors.dart';
import '../transport/request.dart';
import '../transport/response.dart';


























Future<DebugResponse> coreRejectHandler(
  DebugRequest req,
  DebugContext ctx,
) async {
  return switch (req.path) {
    '/core_reject' => _guardState(req, ctx),
    '/core_reject/nodes' => _nodes(req, ctx),
    '/core_reject/banner' => _banner(req, ctx),
    '/core_reject/banner/dismiss' => _dismissBanner(req, ctx),
    '/core_reject/prompt' => switch (req.method) {
        'GET' => _promptState(req, ctx),
        'POST' => _answerPrompt(req, ctx),
        _ => throw BadRequest(
            'method ${req.method} not allowed on /core_reject/prompt'),
      },
    '/core_reject/cancel' => _cancel(req, ctx),
    '/core_reject/reset' => _reset(req, ctx),
    '/core_reject/enable' => _enable(req, ctx),
    '/core_reject/notifications' => _notifications(req, ctx),
    _ => throw NotFound('core_reject path: ${req.path}'),
  };
}

void _requirePost(DebugRequest req) {
  if (req.method != 'POST') {
    throw BadRequest('${req.path} requires POST, got ${req.method}');
  }
}

String _phaseWire(CoreRejectPhase p) => switch (p) {
      CoreRejectPhase.idle => 'idle',
      CoreRejectPhase.signalStart => 'signal_start',
      CoreRejectPhase.checking => 'checking',
      CoreRejectPhase.awaitingPrompt => 'awaiting_prompt',
      CoreRejectPhase.finalStart => 'final_start',
      CoreRejectPhase.done => 'done',
    };

String _outcomeWire(CoreRejectOutcome o) => switch (o) {
      CoreRejectOutcome.startedClean => 'started_clean',
      CoreRejectOutcome.startedWithDisabled => 'started_with_disabled',
      CoreRejectOutcome.failed => 'failed',
      CoreRejectOutcome.stoppedByUser => 'stopped_by_user',
    };

String _severityWire(WarningSeverity s) => switch (s) {
      WarningSeverity.info => 'info',
      WarningSeverity.warning => 'warning',
      WarningSeverity.error => 'error',
    };



Future<DebugResponse> _guardState(DebugRequest req, DebugContext ctx) async {
  final s = CoreRejectState.I;
  final outcome = s.lastOutcome;
  return JsonResponse({
    'phase': _phaseWire(s.phase),
    'round': s.round,
    'round_limit': kCoreRejectRoundLimit,
    'disabled': [for (final d in s.disabled) d.toJson()],
    'outcome': outcome == null ? null : _outcomeWire(outcome),
    'error': s.lastError,
  });
}



Future<DebugResponse> _nodes(DebugRequest req, DebugContext ctx) async {
  final sub = ctx.requireSub();
  return JsonResponse([
    for (final n in sub.coreRejectedNodes)
      {'source': n.source, 'tag': n.tag, 'reason': n.reason},
  ]);
}

Map<String, Object?> _bannerJson(CoreRejectState s) => {
      'visible': s.bannerVisible,
      'count': s.bannerNodes.length,
      'nodes': [for (final d in s.bannerNodes) d.toJson()],
    };

Future<DebugResponse> _banner(DebugRequest req, DebugContext ctx) async {
  if (req.method != 'GET') {
    throw BadRequest('method ${req.method} not allowed on /core_reject/banner');
  }
  return JsonResponse(_bannerJson(CoreRejectState.I));
}



Future<DebugResponse> _dismissBanner(DebugRequest req, DebugContext ctx) async {
  _requirePost(req);
  final s = CoreRejectState.I;
  s.dismissBanner();
  return JsonResponse({'ok': true, 'action': 'banner-dismiss', ..._bannerJson(s)});
}

Future<DebugResponse> _promptState(DebugRequest req, DebugContext ctx) async {
  final s = CoreRejectState.I;
  return JsonResponse({
    'pending': s.promptPending,
    'count': s.promptCount,
    'limit': kCoreRejectRoundLimit,
  });
}




Future<DebugResponse> _answerPrompt(DebugRequest req, DebugContext ctx) async {
  final s = CoreRejectState.I;

  final body = req.jsonBodyAsMap();
  final raw = (req.q('answer') ?? body['answer']?.toString() ?? '').trim();
  final answer = switch (raw.toLowerCase()) {
    'stop' => CoreRejectPrompt.stop,
    'keep' || 'keep_checking' => CoreRejectPrompt.keepChecking,
    _ => throw BadRequest('param "answer" must be stop|keep, got "$raw"'),
  };
  if (!s.promptPending) {
    if (answer == CoreRejectPrompt.keepChecking) {
      s.queuePromptAnswer(answer);
      return JsonResponse({
        'answered': true,
        'answer': 'keep',
        'queued': true,
      });
    }
    throw const Conflict('no pending prompt');
  }
  s.answerPrompt(answer);
  return JsonResponse({
    'answered': true,
    'answer': answer == CoreRejectPrompt.stop ? 'stop' : 'keep',
  });
}






Future<DebugResponse> _reset(DebugRequest req, DebugContext ctx) async {
  _requirePost(req);
  final s = CoreRejectState.I;
  if (s.guardActive) {
    throw const Conflict('guard already running');
  }
  s.resetRunState();
  return JsonResponse({'ok': true, 'action': 'core-reject-reset'});
}







Future<DebugResponse> _cancel(DebugRequest req, DebugContext ctx) async {
  _requirePost(req);
  final s = CoreRejectState.I;
  if (!s.cancelRun()) throw const Conflict('no run to cancel');
  return JsonResponse({
    'cancelled': true,
    'phase': _phaseWire(s.phase),
    'round': s.round,
  });
}





Future<DebugResponse> _enable(DebugRequest req, DebugContext ctx) async {
  _requirePost(req);
  final body = req.jsonBodyAsMap();
  final tag = (req.q('tag') ?? body['tag']?.toString() ?? '').trim();
  if (tag.isEmpty) {
    throw const BadRequest('param "tag" required');
  }
  final sub = ctx.requireSub();
  final enabled = await sub.enableNodeByCoreTag(tag);
  if (!enabled) throw NotFound('node by core tag: $tag');
  return JsonResponse({'enabled': enabled, 'tag': tag});
}







Future<DebugResponse> _notifications(DebugRequest req, DebugContext ctx) async {
  final sub = ctx.requireSub();
  final wanted = req.q('tag')?.trim();

  final byTag = <String, List<StoredWarning>>{};
  for (final e in sub.entries) {
    final list = e.list;
    switch (list) {
      case SubscriptionServers():
        for (final w in list.nodeWarnings.entries) {
          if (w.value.isNotEmpty) byTag[w.key] = w.value;
        }
      case FolderServers():
        for (final m in list.members) {
          if (m.warnings.isEmpty) continue;
          byTag[m.node?.tag ?? m.nameHint] = m.warnings;
        }
      case UserServer():
        if (list.warnings.isEmpty) continue;
        byTag[list.nodes.isEmpty ? list.name : list.nodes.first.tag] =
            list.warnings;
    }
  }

  if (wanted != null && wanted.isNotEmpty) {
    final ws = byTag[wanted] ?? _warningsForCoreTag(sub, wanted);
    if (ws == null) throw NotFound('node by core tag: $wanted');
    return JsonResponse(_renderWarnings(ws));
  }
  return JsonResponse({
    for (final e in byTag.entries) e.key: _renderWarnings(e.value),
  });
}

List<StoredWarning>? _warningsForCoreTag(
  SubscriptionController sub,
  String tag,
) {
  final node = sub.lastEmittedTagMap[tag];
  if (node == null) return null;
  for (final e in sub.entries) {
    final list = e.list;
    switch (list) {
      case SubscriptionServers():
        final hash = sourceNodeIdentities(list.nodes)[node];
        if (hash == null) continue;
        final ws = list.nodeWarnings[hash];
        if (ws != null && ws.isNotEmpty) return ws;
      case FolderServers():
        final at = list.members.indexWhere((m) => identical(m.node, node));
        if (at < 0) continue;
        final ws = list.members[at].warnings;
        if (ws.isNotEmpty) return ws;
      case UserServer():
        if (!list.nodes.any((n) => identical(n, node))) continue;
        if (list.warnings.isNotEmpty) return list.warnings;
    }
  }
  return null;
}



List<Map<String, Object?>> _renderWarnings(List<StoredWarning> ws) => [
      for (final w in ws)
        {
          'code': w.code,
          'severity': _severityWire(registrySeverity(w.code)),
          'params': {...w.params},
          'title_en': registryTitle(w.code, RegistryLang.en, params: w.params),
          'text_en': registryText(w.code, RegistryLang.en, params: w.params),
        },
    ];
