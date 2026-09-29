












library;

import 'dart:async';

import '../../controllers/home_controller.dart';
import '../../controllers/subscription_controller.dart';
import '../app_log.dart';
import 'core_reject_guard.dart';
import 'core_reject_host.dart';
import 'core_reject_state.dart';

Completer<CoreRejectRun>? _activeGuardRun;






Future<String?> rebuildConfigSilently(
  HomeController home,
  SubscriptionController sub,
) async {
  final config = await sub.generateConfig();
  if (config == null) return null;
  final ok = await home.saveParsedConfig(config);
  if (!ok) {
    sub.configDirty = true;
    return null;
  }
  return home.state.configRaw;
}











Future<CoreRejectRun?> runCoreRejectGuard({
  required HomeController home,
  required SubscriptionController sub,
  Future<String?> Function()? rebuildAndSave,
  Future<CoreRejectPrompt> Function(int limit)? askPrompt,

  bool guard = true,

  bool headless = false,
}) async {
  if (!guard) {
    unawaited(home.start());
    return null;
  }
  final active = _activeGuardRun;
  if (active != null && !active.isCompleted) return active.future;

  final runCompleter = Completer<CoreRejectRun>();
  _activeGuardRun = runCompleter;

  CoreRejectState.I.beginRun();
  final host = AppCoreRejectHost(
    home: home,
    sub: sub,
    headless: headless,
    rebuildAndSave:
        rebuildAndSave ?? () => rebuildConfigSilently(home, sub),
    askPrompt: askPrompt,
  );
  final automaton = CoreRejectGuard(host);



  CoreRejectState.I.bindCancel(automaton.cancel);
  try {
    final run = await automaton.run();
    CoreRejectState.I.finish(run);
    if (run.outcome == CoreRejectOutcome.failed && run.error.isNotEmpty) {


      AppLog.I.warning('core reject guard: ${run.error}');
    }
    runCompleter.complete(run);
    return run;
  } catch (e, st) {
    runCompleter.completeError(e, st);
    rethrow;
  } finally {
    if (_activeGuardRun == runCompleter) _activeGuardRun = null;
  }
}
