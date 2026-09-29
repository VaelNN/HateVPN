import 'dart:async';

import '../../vpn/box_vpn_client.dart';
import '../core_reject/core_reject_runner.dart';
import '../debug/context.dart';
import '../debug/contract/errors.dart';
import '../settings_storage.dart';
import '../subscription/auto_updater.dart';























Future<void> actionSwitchNode(String tag, DebugContext ctx) async {
  if (tag.isEmpty) throw const BadRequest('"tag" empty');
  final home = ctx.requireHome();
  if (home.state.selectedGroup == null) {
    throw const Conflict('no group selected — set group first');
  }




  if (!home.state.tunnelUp) {
    throw const Conflict('tunnel not connected');
  }
  unawaited(home.switchNode(tag));
}





Future<void> actionSetGroup(String group, DebugContext ctx) async {
  if (group.isEmpty) throw const BadRequest('"group" empty');
  final home = ctx.requireHome();
  if (!home.state.groups.contains(group)) {
    throw NotFound('group not found: "$group"');
  }
  home.setSelectedGroup(group);
  unawaited(home.applyGroup(group));
}




Future<int> actionRebuildConfig(DebugContext ctx) async {
  if (await SettingsStorage.getConfigLockedForDebug()) {
    throw const Conflict(
      'config_locked_for_debug=true — rebuild blocked.',
    );
  }
  final sub = ctx.requireSub();
  final home = ctx.requireHome();
  final json = await sub.generateConfig();
  if (json == null) {
    throw UpstreamError(
        'generate failed: ${sub.lastError?.renderEn() ?? ''}');
  }
  final saved = await home.saveParsedConfig(json);
  if (!saved) {
    throw const UpstreamError('saveParsedConfig returned false');
  }
  return json.length;
}



Future<void> actionRefreshSubs(bool force, DebugContext ctx) async {
  final updater = ctx.autoUpdater;
  if (updater == null) {
    throw const Conflict('auto updater not ready');
  }
  unawaited(updater.maybeUpdateAll(UpdateTrigger.manual, force: force));
}




Future<bool> actionResetNetwork(DebugContext ctx) async {
  final home = ctx.requireHome();
  if (!home.state.tunnelUp) {
    throw const Conflict('tunnel not up — resetNetwork is no-op');
  }
  return BoxVpnClient().resetNetwork();
}


Future<void> actionUrltestGroup(String group, DebugContext ctx) async {
  if (group.isEmpty) throw const BadRequest('"group" empty');
  final home = ctx.requireHome();
  if (!home.state.tunnelUp) {
    throw const Conflict('tunnel not connected');
  }
  unawaited(home.runGroupUrltest(group));
}










Future<void> actionStartVpn(DebugContext ctx, {bool guard = false}) async {
  final home = ctx.requireHome();
  if (!guard) {
    unawaited(home.start());
    return;
  }
  final sub = ctx.requireSub();
  unawaited(runCoreRejectGuard(home: home, sub: sub));
}


Future<void> actionStopVpn(DebugContext ctx) async {
  final home = ctx.requireHome();
  unawaited(home.stop());
}
