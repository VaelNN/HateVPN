import 'package:flutter/foundation.dart';

import '../../vpn/box_vpn_client.dart';
import '../app_log.dart';
import '../core_reject/core_reject_state.dart';
import '../debug/context.dart';
import '../debug/contract/errors.dart';
import '../debug/debug_registry.dart';
import 'event_emitter.dart';
import 'handlers.dart' as handlers;















const kVpnStopRequestedAction = 'vpn-stop-requested';

void registerAutomationBridge() {
  BoxVpnClient.I.registerAutomationActionHandler(_dispatch);
}

void _dispatch(String name, Map<String, dynamic> args) {



  final ctx = DebugContext(
    registry: DebugRegistry.I,
    appStartedAt: DateTime.now(),
  );



  Future<void> run() async {
    switch (name) {





      case kVpnStopRequestedAction:
        CoreRejectState.I.cancelRun();
      case 'switch-node':
        await handlers.actionSwitchNode(_str(args, 'tag'), ctx);
      case 'set-group':
        await handlers.actionSetGroup(_str(args, 'group'), ctx);
      case 'rebuild-config':
        await handlers.actionRebuildConfig(ctx);
      case 'refresh-subs':
        await handlers.actionRefreshSubs(_bool(args, 'force'), ctx);
      case 'reset-network':
        await handlers.actionResetNetwork(ctx);
      case 'urltest-group':
        await handlers.actionUrltestGroup(_str(args, 'group'), ctx);
      default:
        AppLog.I.warning('[automation] unknown action "$name"');
        return;
    }
  }

  run().then((_) {
    AppLog.I.info('[automation] action $name → ok');
  }).catchError((Object e) {
    final signal = automationErrorSignal(e);

    AppLog.I.warning('[automation] action $name → ERROR ${signal.code}: $e');

    AutomationEventEmitter.I.emitVpnError(signal.code, signal.message);
  });
}

String _str(Map<String, dynamic> args, String key) =>
    args[key]?.toString() ?? '';

bool _bool(Map<String, dynamic> args, String key) {
  final v = args[key];
  if (v is bool) return v;



  if (v is String) {
    final s = v.toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }
  return false;
}








@visibleForTesting
({String code, String message}) automationErrorSignal(Object e) {
  if (e is DebugError) return (code: e.code, message: e.message);
  return (code: 'error', message: 'internal error');
}
