import 'dart:async';

import 'package:flutter/material.dart';

import '../../../controllers/home_controller.dart';
import '../../../controllers/subscription_controller.dart';
import '../../../models/home_state.dart';
import '../../../services/core_reject/core_reject_state.dart';
import '../../../services/crash_banner_state.dart';
import '../core_reject_ui.dart';
import '../../../services/crash_share.dart';
import '../../../services/haptic_service.dart';
import '../home_dialogs.dart';
import '../home_menus.dart';
import '../node_list_presenter.dart';
import 'app_banner.dart';
import '../../../services/l10n/locale_controller.dart';
import '../../../services/networks_direction.dart';







class HomeControls extends StatelessWidget {
  const HomeControls({
    super.key,
    required this.controller,
    required this.subController,
    required this.presenter,
    required this.connectingAnimChild,
    required this.state,
    required this.startActive,
    required this.startEnabled,
    required this.stopEnabled,
    required this.needsRestart,
    this.autoApplying = false,
    required this.errorTimerOnDismiss,
    required this.onStartWithAutoRefresh,
    required this.onRebuildAndClearDirty,
    required this.onRebuildAndReconnect,
    required this.onRebuildAndStart,
  });

  final HomeController controller;
  final SubscriptionController subController;
  final NodeListPresenter presenter;


  final Widget connectingAnimChild;
  final HomeState state;
  final bool startActive;
  final bool startEnabled;
  final bool stopEnabled;
  final bool needsRestart;



  final bool autoApplying;



  final VoidCallback errorTimerOnDismiss;

  final void Function() onStartWithAutoRefresh;
  final Future<void> Function() onRebuildAndClearDirty;
  final Future<void> Function() onRebuildAndReconnect;
  final Future<void> Function() onRebuildAndStart;





  Future<void> _shareCrash() async {
    final report = CrashBannerState.I.pending;
    if (report == null) return;
    await shareCrashReport(report);
    await CrashBannerState.I.markShown();
  }

  @override
  Widget build(BuildContext context) {
    final isConnecting = state.tunnel == TunnelStatus.connecting;
    final isStopping = state.tunnel == TunnelStatus.stopping;
    final canToggle = !state.busy && !isConnecting && !isStopping;
    final toggleEnabled = canToggle && (state.tunnelUp || state.configRaw.isNotEmpty);

    final hasNetworks = state.tunnelUp && state.networksNodes.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [


              AnimatedBuilder(
                animation: CoreRejectState.I,
                builder: (context, _) {





                  final checking = CoreRejectState.I.checking;
                  final guardActive = CoreRejectState.I.guardActive;
                  final pressable =
                      checking || (!guardActive && toggleEnabled);
                  return FilledButton.icon(



                autofocus: true,
                onPressed: pressable
                    ? () {
                        HapticService.I.onConnectTap();
                        if (checking) {
                          CoreRejectState.I.cancelRun();
                        } else if (state.tunnelUp) {
                          confirmStop(context, controller, state);
                        } else {
                          onStartWithAutoRefresh();
                        }
                      }
                    : null,
                icon: Icon(
                  state.tunnelUp || checking
                      ? Icons.stop_rounded
                      : Icons.play_arrow_rounded,
                  size: 20,
                ),
                label: Text(state.tunnelUp
                    ? getLocalText.s("Stop")


                    : checking
                        ? getLocalText.plural(
                            "Checking servers… (%d disabled)",
                            CoreRejectState.I.disabled.length)
                        : getLocalText.s("Start")),
                  );
                },
              ),
              const SizedBox(width: 8),


              Flexible(child: connectingAnimChild),
              const SizedBox(width: 8),
              _buildReloadButton(context),
            ],
          ),






          AnimatedBuilder(



            animation: Listenable.merge(
                [CrashBannerState.I, CoreRejectState.I]),
            builder: (context, _) => BannerStack(
              banners: activeBanners(
                state,
                configDirty: subController.configDirty,
                busy: subController.busy,
                crashPending: CrashBannerState.I.pending != null,
                coreRejected: CoreRejectState.I.bannerVisible
                    ? CoreRejectState.I.bannerNodes
                    : const [],
                autoApplying: autoApplying,
                actions: BannerActions(
                  onRebuild: () => unawaited(onRebuildAndClearDirty()),


                  onConfirmStop: () =>
                      confirmStop(context, controller, controller.state),
                  onClearError: errorTimerOnDismiss,
                  onShareCrash: () => unawaited(_shareCrash()),
                  onDismissCrash: () =>
                      unawaited(CrashBannerState.I.markShown()),
                  onShowCoreRejected: () => unawaited(showCoreRejectList(
                      context, CoreRejectState.I.bannerNodes,
                      subController: subController)),
                  onDismissCoreRejected: CoreRejectState.I.dismissBanner,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(getLocalText.s("Direction"),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).colorScheme.outline),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      isDense: true,



                      value: state.showingNetworks
                          ? kNetworksDirectionValue
                          : state.groups.contains(state.selectedGroup)
                              ? state.selectedGroup
                              : null,



                      hint: Text(getLocalText.s("Select direction"),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      items: state.groups
                          .map((g) => DropdownMenuItem(
                              value: g,
                              child: Text(state.groupLabelOf(g),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis)))
                          .followedBy([

                        if (hasNetworks)
                          const DropdownMenuItem(
                              value: kNetworksDirectionValue,
                              child: Text(kNetworksLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis)),
                      ]).toList(),
                      onChanged: (!state.tunnelUp ||
                              state.busy ||
                              (state.groups.isEmpty && !hasNetworks))
                          ? null
                          : (value) async {
                              if (value == kNetworksDirectionValue) {
                                controller.openNetworks();
                                return;
                              }
                              controller.setSelectedGroup(value);
                              await controller.applyGroup(value);
                            },
                    ),
                  ),
                ),
              ),




              InkWell(
                borderRadius: BorderRadius.circular(20),

                onTap: (!state.tunnelUp ||
                        state.busy ||
                        state.nodes.isEmpty ||
                        state.showingNetworks)
                    ? null
                    : () {
                        if (controller.massPingRunning) {
                          controller.cancelMassPing();
                        } else {





                          unawaited(controller.runMassUrltest(
                              order: presenter.computeDisplayList(state)));
                        }
                      },
                onLongPress: () => showPingSettings(context, controller),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    controller.massPingRunning ? Icons.stop_circle_outlined : Icons.speed,
                    color: (!state.tunnelUp ||
                            state.busy ||
                            state.nodes.isEmpty ||
                            state.showingNetworks)
                        ? Theme.of(context).disabledColor
                        : null,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }





  Widget _buildReloadButton(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dirty = subController.configDirty || needsRestart;
    final enabled = !state.busy && !subController.busy;
    final fg = dirty ? cs.onPrimaryContainer : null;
    final bg = dirty ? cs.primaryContainer : Colors.transparent;



    return Semantics(
      button: true,
      label: _defaultReloadLabel(state, dirty),
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,


        child: Builder(builder: (inkCtx) => InkWell(
          onTap: enabled ? () => _runDefaultReload(state) : null,
          onLongPress: enabled ? () => _showReloadMenu(inkCtx, state) : null,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(Icons.refresh, size: 20, color: fg),
          ),
        )),
      ),
    );
  }

  String _defaultReloadLabel(HomeState state, bool dirty) {
    if (!state.tunnelUp) return 'Rebuild config + connect';


    return dirty ? 'Rebuild config + reconnect' : 'Reload';
  }

  void _runDefaultReload(HomeState state) {
    HapticService.I.onConnectTap();
    if (!state.tunnelUp) {
      unawaited(onRebuildAndStart());
      return;
    }
    final dirty = subController.configDirty || needsRestart;
    if (dirty) {
      unawaited(onRebuildAndReconnect());
    } else {





      unawaited(controller.reloadVpn());
    }
  }

  Future<void> _showReloadMenu(BuildContext anchorCtx, HomeState state) async {
    final box = anchorCtx.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(anchorCtx).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final pos = box.localToGlobal(Offset.zero, ancestor: overlay);
    final size = box.size;
    final rect = RelativeRect.fromLTRB(
      pos.dx,
      pos.dy + size.height,
      overlay.size.width - pos.dx - size.width,
      overlay.size.height - pos.dy,
    );
    final reconnectLabel = state.tunnelUp ? 'Reconnect' : 'Connect';
    final rebuildReconnectLabel =
        state.tunnelUp ? 'Rebuild config + reconnect' : 'Rebuild config + connect';
    final choice = await showMenu<String>(
      context: anchorCtx,
      position: rect,
      items: [


        if (state.tunnelUp)
          PopupMenuItem(
            value: 'reload',
            child: Row(children: [
              const Icon(Icons.bolt, size: 18),
              const SizedBox(width: 12),
              Text(getLocalText.s("Reload")),
            ]),
          ),
        PopupMenuItem(
          value: 'reconnect',
          child: Row(children: [
            const Icon(Icons.sync, size: 18),
            const SizedBox(width: 12),
            Text(reconnectLabel),
          ]),
        ),
        PopupMenuItem(
          value: 'rebuild',
          child: Row(children: [
            const Icon(Icons.build_circle_outlined, size: 18),
            const SizedBox(width: 12),
            Text(getLocalText.s("Rebuild config only")),
          ]),
        ),
        PopupMenuItem(
          value: 'rebuild_reconnect',
          child: Row(children: [
            const Icon(Icons.refresh, size: 18),
            const SizedBox(width: 12),
            Text(rebuildReconnectLabel),
          ]),
        ),
      ],
    );
    if (!anchorCtx.mounted || choice == null) return;
    HapticService.I.onConnectTap();
    switch (choice) {
      case 'reload':
        unawaited(controller.reloadVpn());
      case 'reconnect':
        unawaited(controller.reconnect());
      case 'rebuild':
        unawaited(onRebuildAndClearDirty());
      case 'rebuild_reconnect':
        unawaited(onRebuildAndReconnect());
    }
  }
}
