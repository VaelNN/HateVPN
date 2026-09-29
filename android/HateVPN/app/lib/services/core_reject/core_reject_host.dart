








library;

import '../../controllers/home_controller.dart';
import '../../controllers/subscription_controller.dart';
import '../../models/core_reject_verdict.dart';
import '../../vpn/box_vpn_client.dart';
import '../app_log.dart';
import 'core_reject_guard.dart';
import 'core_reject_state.dart';





class AppCoreRejectHost implements CoreRejectHost {
  AppCoreRejectHost({
    required this.home,
    required this.sub,
    required this.rebuildAndSave,
    this.askPrompt,
    this.headless = false,
    BoxVpnClient? vpn,
  }) : _vpn = vpn ?? BoxVpnClient.I;

  final HomeController home;
  final SubscriptionController sub;
  final BoxVpnClient _vpn;


  final bool headless;



  final Future<String?> Function() rebuildAndSave;


  final Future<CoreRejectPrompt> Function(int limit)? askPrompt;

  @override
  Future<CoreAttempt> realStart() async {
    final error = headless
        ? await home.startAndAwaitVerdictHeadless()
        : await home.startAndAwaitVerdict();
    if (error == null) return const CoreAttempt.accepted();
    if (error.isEmpty) return const CoreAttempt.unavailable();
    return CoreAttempt.rejected(error);
  }

  @override
  Future<RebuiltConfig?> rebuild() async {
    final json = await rebuildAndSave();
    if (json == null || json.isEmpty) return null;


    return RebuiltConfig(
      configJson: json,
      tags: sub.lastEmittedTagMap.keys.toSet(),
    );
  }

  @override
  Future<CoreAttempt> check(String configJson) async {
    final r = await _vpn.checkConfig(configJson);

    if (r == null) return const CoreAttempt.unavailable();
    return r.ok ? const CoreAttempt.accepted() : CoreAttempt.rejected(r.error);
  }

  @override
  Future<CoreRejectNodeRef?> disableNode(String tag, String reason) async {
    final ref = await sub.disableNodeByCoreTag(tag, reason);
    AppLog.I.warning(ref != null
        ? 'core rejected node "$tag", disabled: $reason'
        : 'core rejected tag "$tag" with no matching node, no automation');
    return ref;
  }

  @override
  Future<CoreRejectPrompt> askKeepChecking(int disabledCount) async {
    final ask = askPrompt;
    if (ask != null) return ask(disabledCount);


    return CoreRejectState.I.askPrompt(disabledCount);
  }

  @override
  void onProgress(
    CoreRejectPhase phase,
    int round, {
    List<DisabledNode> disabledNodes = const [],
  }) =>
      CoreRejectState.I
          .onProgress(phase, round, disabledNodes: disabledNodes);
}
