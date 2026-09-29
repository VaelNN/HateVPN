import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/home_controller.dart';
import '../controllers/subscription_controller.dart';
import '../models/home_state.dart';
import '../models/validation.dart';
import '../services/app_log.dart';
import '../services/tag_resolver.dart';
import '../services/core_reject/core_reject_guard.dart';
import '../services/core_reject/core_reject_runner.dart';
import '../services/core_reject/core_reject_state.dart';
import 'home/core_reject_ui.dart';
import '../services/error_humanize.dart';
import '../services/support/active_time_tracker.dart';
import '../services/support/support_message.dart';
import '../services/support/support_nav.dart';
import '../services/version_info.dart';
import 'about_screen.dart';
import 'app_settings_screen.dart';
import 'config_screen.dart';
import 'debug_screen.dart';
import 'dns_settings_screen.dart';
import 'home/support_message_screen.dart';
import 'routing_screen.dart';
import 'settings_screen.dart';
import 'speed_test_screen.dart';
import 'stats_screen.dart';
import 'home/widgets/detour_cycle_sheet.dart';
import 'home/widgets/traffic_bar.dart';
import 'owner_navigation.dart';
import 'subscriptions_screen.dart';
import 'home/widgets/progress_banner.dart';
import 'home/widgets/nodes_header.dart';
import 'home/widgets/home_drawer.dart';
import 'home/widgets/home_controls.dart';
import 'home/widgets/add_server_cta.dart';
import 'home/widgets/node_list.dart';
import 'home/widgets/status_chip.dart';
import '../widgets/pool_view_dialog.dart';
import 'home/home_menus.dart';
import 'home/home_dialogs.dart';
import 'home/node_filter_view_model.dart';
import 'home/node_list_presenter.dart';
import 'home/source_lookup.dart';
import 'hate_connections_screen.dart';
import 'hate_home_view.dart';
import 'hate_settings_screen.dart';
import 'home/restore_backup.dart';
import 'home/startup_wizard.dart';
import '../services/debug/bootstrap.dart';
import '../services/debug/debug_registry.dart';
import '../services/haptic_service.dart';
import '../services/nav/home_return_observer.dart';
import '../services/settings_storage.dart';
import '../services/rule_set_auto_updater.dart';
import '../services/subscription/auto_updater.dart';
import '../services/update_checker.dart';
import '../vpn/box_vpn_client.dart';
import '../services/l10n/locale_controller.dart';
import 'home/widgets/template_warnings_snack.dart';
import '../widgets/double_back_to_exit.dart';
import '../services/probe/probe_lifecycle.dart';
import '../services/workspaces/workspace_controller.dart';
import 'home/widgets/workspace_menu.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  String? _chosenTag;
  String? _chosenName;
  String? _chosenSource;
  String? _connectionError;
  bool _selectionApplying = false;
  String? _selectionAttemptedForSession;

  Future<void> _loadHateSelection() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _chosenTag = prefs.getString('hatevpn_selected_tag');
      _chosenName = prefs.getString('hatevpn_selected_name');
      _chosenSource = prefs.getString('hatevpn_selected_source');
    });
  }

  Future<void> _chooseHateServer(String tag, String name, String source) async {
    setState(() {
      _chosenTag = tag;
      _chosenName = name;
      _chosenSource = source;
      _connectionError = null;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('hatevpn_selected_tag', tag);
    await prefs.setString('hatevpn_selected_name', name);
    await prefs.setString('hatevpn_selected_source', source);
    if (_controller.state.tunnelUp && _controller.state.nodes.contains(tag)) {
      _selectionAttemptedForSession = tag;
      await _controller.switchNode(tag);
    }
  }

  Future<void> _clearHateSelection() async {
    setState(() {
      _chosenTag = null;
      _chosenName = null;
      _chosenSource = null;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('hatevpn_selected_tag');
    await prefs.remove('hatevpn_selected_name');
    await prefs.remove('hatevpn_selected_source');
  }

  late final HomeController _controller;
  late final SubscriptionController _subController;
  late final AutoUpdater _autoUpdater;


  late final RuleSetAutoUpdater _ruleSetAutoUpdater;





  final Map<String, GlobalKey> _nodeRowKeys = {};

  GlobalKey _nodeRowKey(String tag) =>
      _nodeRowKeys.putIfAbsent(tag, () => GlobalKey());





  void _scrollToNode(String tag) {
    _controller.setHighlightedNode(tag);
    final ctx = _nodeRowKeys[tag]?.currentContext;
    if (ctx == null) return;
    unawaited(
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.3,
      ),
    );
  }



  void _showPool(String autoTag) {
    final base = autoTag.endsWith('-auto')
        ? autoTag.substring(0, autoTag.length - '-auto'.length)
        : autoTag;
    final label = _controller.state.groupLabels[base] ?? base;
    unawaited(
      showPoolDialog(
        context,
        autoTag: autoTag,
        title: label,
        fetch: _controller.getPool,
      ),
    );
  }



  late final Future<void> _controllerInit;
  late final AnimationController _connectingAnim;
  final BoxVpnClient _vpn = BoxVpnClient();



  Future<void>? _rebuildInFlight;





  bool _autoApplying = false;



  VoidCallback? _idleRetryListener;




  Timer? _updateCheckTimer;





  late final NodeFilterViewModel _filter;



  late final NodeListPresenter _nodeList;







  bool get _needsRestart {
    final state = _controller.state;
    return _subController.configDirty ||
        (state.tunnelUp && state.configChangedNeedRestart);
  }






  TunnelStatus _prevTunnel = TunnelStatus.disconnected;
  UiMsg? _prevError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHateSelection());
    WidgetsBinding.instance.addObserver(this);


    _subController = SubscriptionController();
    _autoUpdater = AutoUpdater(_subController);
    _subController.bindAutoUpdater(_autoUpdater);


    _ruleSetAutoUpdater = RuleSetAutoUpdater();
    _controller = HomeController(
      autoUpdater: _autoUpdater,
      ruleSetAutoUpdater: _ruleSetAutoUpdater,
    );




    _ruleSetAutoUpdater.bindOnChanged(
      () => _reactToSubscriptionUpdate(reload: false),
    );


    _autoUpdater.bindOnUpdateReaction(_reactToSubscriptionUpdate);

    _filter = NodeFilterViewModel()..addListener(_onFilterChanged);


    _nodeList = NodeListPresenter(
      controller: _controller,
      subController: _subController,
      filter: _filter,
    );
    _connectingAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );


    ActiveTimeTracker.I.uptimeMsProvider = _vpn.getTunnelUptimeMs;


    DebugRegistry.I.home = _controller;
    DebugRegistry.I.sub = _subController;
    DebugRegistry.I.autoUpdater = _autoUpdater;



    unawaited(applyDebugApiSettings());
    _controllerInit = _controller.init();
    unawaited(_controllerInit);
    unawaited(_initSubsAndAutoUpdate());

    _ruleSetAutoUpdater.start();
    unawaited(_loadHapticPref());

    unawaited(WorkspaceController.I.refresh());




    _prevTunnel = _controller.state.tunnel;
    _prevError = _controller.state.lastError;
    _controller.addListener(_onControllerChange);


    _prevNoNodesStamp = _subController.directionsWithoutNodesStamp;
    _subController.addListener(_onDirectionsWithoutNodes);

    _prevTemplateStamp = _subController.templateWarningsStamp;
    _subController.addListener(_onTemplateWarnings);


    _controller.onMemberSelected = (group, node) =>
        unawaited(_subController.rememberGroupMember(group, node, live: true));


    homeReturnObserver.setHandler(_onReturnToHome);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;



      unawaited(StartupWizard(context, _vpn).run());



      unawaited(_maybeShowSupport());
    });





    unawaited(_hydrateAndMaybeNotify());
    _updateCheckTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      unawaited(
        UpdateChecker.I.maybeCheck(localVersion: VersionInfo.I.version),
      );
    });
  }




  bool _updateSnackbarShown = false;
  Future<void> _hydrateAndMaybeNotify() async {
    await UpdateChecker.I.hydrate(localVersion: VersionInfo.I.version);
    final info = UpdateChecker.I.latest.value;
    if (info == null) return;
    if (_updateSnackbarShown) return;
    if (!mounted) return;


    await maybeShowUpdateSnackbar(
      context,
      info,
      onShown: () => _updateSnackbarShown = true,
    );
  }




  int _prevNoNodesStamp = 0;
  void _onDirectionsWithoutNodes() {
    final stamp = _subController.directionsWithoutNodesStamp;
    if (stamp == _prevNoNodesStamp) return;
    _prevNoNodesStamp = stamp;
    final names = _subController.directionsWithoutNodes;
    if (names.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final msg = names.length == 1
          ? getLocalText.s(
              "Direction \"%s\" matched no nodes — check its node filter.",
              names.first,
            )
          : getLocalText.plural(
              "%d directions matched no nodes — check their node filters.",
              names.length,
            );



      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    });
  }





  int _prevTemplateStamp = 0;
  void _onTemplateWarnings() {
    final stamp = _subController.templateWarningsStamp;
    if (stamp == _prevTemplateStamp) return;
    _prevTemplateStamp = stamp;
    final items = _subController.templateWarnings;
    if (items.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showTemplateWarningsSnack(context, items);
    });
  }

  void _onControllerChange() {
    final state = _controller.state;
    final now = state.tunnel;
    final nowError = state.lastError;




    final isConnecting = now == TunnelStatus.connecting;
    if (isConnecting && !_connectingAnim.isAnimating) {
      _connectingAnim.repeat();
    } else if (!isConnecting && _connectingAnim.isAnimating) {
      _connectingAnim.stop();
      _connectingAnim.reset();
    }







    final nowReason = state.stopReason;
    if (nowError != _prevError &&
        nowReason is StopPermissionLocation &&
        !_permissionDialogShowing) {
      _permissionDialogShowing = true;
      final permName = nowReason.permissions;

      _controller.clearError();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await showLocationPermissionDialog(context, permName);
        _permissionDialogShowing = false;
      });
    }




    if (nowError != _prevError &&
        nowError != null &&
        nowReason is! StopPermissionLocation) {
      final msg = nowError;
      if (mounted) setState(() => _connectionError = msg.render());
      _controller.clearError();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(msg.render()),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
      });
    }

    if (!state.tunnelUp) _selectionAttemptedForSession = null;
    if (state.tunnelUp) {
      if (_connectionError != null && mounted) {
        setState(() => _connectionError = null);
      }
      final tag = _chosenTag;
      if (tag != null &&
          state.nodes.contains(tag) &&
          state.activeInGroup != tag &&
          !_selectionApplying &&
          _selectionAttemptedForSession != tag &&
          !state.busy) {
        _selectionApplying = true;
        _selectionAttemptedForSession = tag;
        unawaited(
          _controller.switchNode(tag).whenComplete(() {
            _selectionApplying = false;
          }),
        );
      }
    }




    _filter.syncDirection(state.selectedGroup);



    final wasUp = _prevTunnel == TunnelStatus.connected;
    final isUp = now == TunnelStatus.connected;
    if (wasUp != isUp) {
      unawaited(ActiveTimeTracker.I.onTunnelChanged(isUp));
    } else if (isUp) {
      unawaited(ActiveTimeTracker.I.tick());
    }


    if (isUp) unawaited(_maybeShowSupport());



    final preview = _controller.takeSupportPreview();
    if (preview != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          _pushSupportMessage(
            preview.feed,
            preview.message,
            dryRun: preview.dryRun,
          ),
        );
      });
    }

    _prevTunnel = now;
    _prevError = nowError;
  }

  bool _permissionDialogShowing = false;
























  Future<bool> _stopForWorkspaceSwitch() async {
    _autoUpdater.halt();
    ProbeLifecycle.I.haltAll();
    final wasUp = _controller.state.tunnelUp;
    if (_controller.state.tunnel != TunnelStatus.disconnected) {
      await _controller.stop();
    }
    return wasUp;
  }

  Future<void> _initSubsAndAutoUpdate() async {
    await _subController.init();






    try {
      await Future.wait([_subController.rehydrationDone, _controllerInit]);
      if (mounted) {
        final hasEntries = _subController.entries.isNotEmpty;
        final emptyConfig = _controller.state.configRaw.isEmpty;
        final tunnelUp = _controller.state.tunnelUp;
        final dirty = _subController.configDirty;

        AppLog.I.info(
          'bootstrap: entries=$hasEntries emptyConfig=$emptyConfig '
          'tunnelUp=$tunnelUp dirty=$dirty',
        );


        final autoConnect = WorkspaceController.I.takePendingAutoConnect();
        if (hasEntries && emptyConfig && tunnelUp) {



          _controller.markConfigLoadError();
        } else if (hasEntries && (emptyConfig || dirty)) {









          await _rebuildAndClearDirty(silent: true);
          if (mounted) setState(() {});



          if (autoConnect && mounted) {
            if (!_subController.configDirty) {
              await _controller.start();
            } else {
              AppLog.I.warning(
                'workspaces: auto-connect skipped — config still dirty',
              );
            }
          }
        } else if (autoConnect) {
          AppLog.I.warning(
            'workspaces: auto-connect skipped — nothing to '
            'rebuild (entries=$hasEntries dirty=$dirty)',
          );
        }
      }
    } catch (e) {




      AppLog.I.error('Bootstrap skipped: ${humanizeError(e).renderEn()}');
    } finally {



      if (mounted) _autoUpdater.start();
    }
  }

  Future<void> _loadHapticPref() async {
    await HapticService.I.loadFromPrefs();
  }

  @override
  void dispose() {




    final idleRetry = _idleRetryListener;
    if (idleRetry != null) {
      _subController.removeListener(idleRetry);
      _idleRetryListener = null;
    }
    _updateCheckTimer?.cancel();
    _filter.removeListener(_onFilterChanged);
    _filter.dispose();
    _controller.removeListener(_onControllerChange);
    _subController.removeListener(_onDirectionsWithoutNodes);
    _subController.removeListener(_onTemplateWarnings);
    _controller.onMemberSelected = null;
    WidgetsBinding.instance.removeObserver(this);
    homeReturnObserver.clearHandler();
    _autoUpdater.dispose();
    _ruleSetAutoUpdater.dispose();





    _controller.dispose();
    _subController.dispose();
    _connectingAnim.dispose();
    super.dispose();
  }


  DateTime? _pausedAt;
  static const _bgSnackThreshold = Duration(seconds: 30);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed) {
      _controller.onAppResumed();
      _ruleSetAutoUpdater.onAppResumed();




      unawaited(_autoUpdater.maybeUpdateAll(UpdateTrigger.resumed));
      _maybeShowSupport();
      _maybeShowResumeSnack();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {



      _pausedAt = DateTime.now();
      _controller.onAppPaused();

      _ruleSetAutoUpdater.onAppPaused();
    }
  }




  void _maybeShowResumeSnack() {
    final pausedAt = _pausedAt;
    _pausedAt = null;
    if (pausedAt == null) return;
    if (DateTime.now().difference(pausedAt) < _bgSnackThreshold) return;
    if (!_controller.state.tunnelUp) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(getLocalText.s("Resumed — syncing tunnel…")),
        duration: const Duration(seconds: 2),
      ),
    );
  }


  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  SupportFeed? _supportFeed;
  DateTime? _supportNextFetchAt;
  bool _supportShown = false;
  bool _supportInFlight = false;












  Future<void> _maybeShowSupport() async {

    if (!_showUpstreamSupport) return;
    if (_supportShown || _supportInFlight || !mounted) return;
    if (_lifecycle != AppLifecycleState.resumed) return;
    final since = _controller.state.connectedSince;
    if (since == null) return;
    _supportInFlight = true;
    try {




      if (_supportFeed == null) {
        final next = _supportNextFetchAt;
        if (next != null && DateTime.now().isBefore(next)) return;
        _supportNextFetchAt = DateTime.now().add(const Duration(seconds: 30));
        _supportFeed = await SupportMessageService.I.fetchOrCached();
      }
      final feed = _supportFeed;
      if (feed == null || !mounted) return;
      final session = DateTime.now().difference(since).inSeconds;
      final m = await SupportMessageService.I.nextToShow(
        feed,
        currentSessionSeconds: session,
      );
      if (m == null || _supportShown || !mounted) return;
      _supportShown = true;
      await _pushSupportMessage(feed, m);
    } finally {
      _supportInFlight = false;
    }
  }

  bool get _showUpstreamSupport => false;


  Future<void> _pushSupportMessage(
    SupportFeed feed,
    SupportMessage m, {
    bool dryRun = false,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => SupportMessageScreen(
          feed: feed,
          message: m,
          dryRun: dryRun,
          buildScreen: _buildSupportScreen,
        ),
      ),
    );
  }





  Widget? _buildSupportScreen(SupportLinkAction a) {
    if (a.action == 'add') {


      return SubscriptionsScreen(
        subController: _subController,
        homeController: _controller,
        autoUpdater: _autoUpdater,
        initialInput: a.payload,
      );
    }
    if (a.action != 'route') return null;
    final segs = routeSegments(a);
    final tab = segs.length > 1 ? segs[1] : null;
    switch (segs.first) {
      case 'servers':
        return SubscriptionsScreen(
          subController: _subController,
          homeController: _controller,
          autoUpdater: _autoUpdater,
        );
      case 'routing':
        return RoutingScreen(
          subController: _subController,
          homeController: _controller,
          initialPresetsTab: tab == 'presets',
        );
      case 'dns':
        return DnsSettingsScreen(
          subController: _subController,
          homeController: _controller,
        );
      case 'vpn-settings':
        return SettingsScreen(
          subController: _subController,
          homeController: _controller,
        );
      case 'app-settings':
        return AppSettingsScreen(
          initialTab: switch (tab) {
            'appearance' => 1,
            'subscriptions' => 2,
            'diagnostics' => 3,
            'automation' => 4,
            _ => 0,
          },
        );
      case 'speedtest':
        return SpeedTestScreen(homeController: _controller);
      case 'stats':

        if (!_controller.state.tunnelUp) return null;
        return StatsScreen(
          configRaw: _controller.state.activeConfigRaw,
          subController: _subController,
          homeController: _controller,
          initialTab: switch (tab) {
            'connections' => StatsTab.connections,
            'live' => StatsTab.live,
            _ => StatsTab.overview,
          },
        );
      case 'config':
        return ConfigScreen(controller: _controller);
      case 'debug':
        return DebugScreen(
          initialTab: switch (tab) {
            'crashes' => 1,
            'oom' => 2,
            'profiling' => 3,
            _ => 0,
          },
        );
      case 'about':


        return AboutScreen(openDonate: tab == 'donate');
      case 'profiler':



        if (!_controller.state.tunnelUp) return null;
        return StatsScreen(
          configRaw: _controller.state.activeConfigRaw,
          subController: _subController,
          homeController: _controller,
          initialTab: StatsTab.live,
        );
    }
    return null;
  }


  void _onFilterChanged() {
    if (mounted) setState(() {});
  }

  void _showServerPicker(
    BuildContext context,
    String title,
    List<String> tags,
    String? selected,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: tags.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              );
            }
            final tag = tags[index - 1];
            return ListTile(
              title: Text(tag),
              trailing: selected == tag ? const Icon(Icons.check) : null,
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_controller.switchNode(tag));
              },
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_controller, _subController]),
      builder: (context, _) {
        final state = _controller.state;
        final available = state.configModel.nodes
            .where((node) => !node.isControl)
            .toList();
        final chosenStillExists =
            _chosenTag != null && state.configModel[_chosenTag!] != null;
        final selectedTag = chosenStillExists
            ? _chosenTag
            : state.activeInGroup != null &&
                  state.configModel[state.activeInGroup!] != null
            ? state.activeInGroup
            : available.firstOrNull?.tag;
        final owner = selectedTag == null
            ? null
            : ownerOfTag(selectedTag, _subController.entries);
        final source = owner == null
            ? null
            : _subController.entries[owner.entryIndex].displayName;
        final currentEntry = owner == null
            ? null
            : _subController.entries[owner.entryIndex];
        final bare = selectedTag == null || currentEntry == null
            ? null
            : TagResolver.stripPrefix(selectedTag, currentEntry.list.tagPrefix);
        final currentNode = currentEntry?.list.nodes
            .where((node) => node.tag == bare)
            .firstOrNull;
        final profileName = selectedTag == null
            ? null
            : chosenStillExists
            ? (_chosenName ?? selectedTag)
            : (currentNode?.label.isNotEmpty == true
                  ? currentNode!.label
                  : (bare ?? selectedTag));
        final profileCaption = selectedTag == null
            ? null
            : chosenStillExists
            ? (_chosenSource ?? source ?? 'Свой сервер')
            : (source ?? 'Свой сервер');

        void openConnections() => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => HateConnectionsScreen(
              subController: _subController,
              homeController: _controller,
              autoUpdater: _autoUpdater,
              selectedTag: selectedTag,
              onSelected: (tag, name, source) =>
                  unawaited(_chooseHateServer(tag, name, source)),
              onSelectedDeleted: () => unawaited(_clearHateSelection()),
            ),
          ),
        );

        return DoubleBackToExit(
          builder: (_, onDrawerChanged) => HateHomeView(
            state: state,
            profileName: profileName,
            profileCaption: profileCaption,
            error: _connectionError,
            onConnections: openConnections,
            onToggle: () {
              if (state.tunnelUp) {
                unawaited(_controller.stop());
              } else if (selectedTag == null) {
                openConnections();
              } else {
                unawaited(_startWithAutoRefresh());
              }
            },
            onSettings: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const HateSettingsScreen(),
              ),
            ),
          ),
        );
      },
    );
  }




  Future<void> _rebuildAndReconnect() async {
    await _rebuildConfig();
    if (!mounted) return;



    if (_showDetourCycleSheetIfAny()) return;
    await _controller.reconnect();
  }


  Future<void> _rebuildAndStart() async {
    await _rebuildConfig();
    if (!mounted) return;



    if (_showDetourCycleSheetIfAny()) return;
    await _controller.start();


  }



  bool _showDetourCycleSheetIfAny() {
    final cycles = _subController.lastFatalIssues
        .whereType<DetourCycle>()
        .toList();
    if (cycles.isEmpty) return false;
    unawaited(
      showDetourCycleSheet(context, cycles, onCulpritTap: _goToCulpritOwner),
    );
    return true;
  }





  void _goToCulpritOwner(String culpritTag) {
    Navigator.of(context).pop();
    unawaited(
      openTagOwner(
        context,
        culpritTag,
        subController: _subController,
        homeController: _controller,
        onOwnerNotFound: () {
          if (!mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SubscriptionsScreen(
                subController: _subController,
                homeController: _controller,
                autoUpdater: _autoUpdater,
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _startWithAutoRefresh() async {
    if (_connectionError != null) setState(() => _connectionError = null);






    if (!await confirmForeignVpnOverride(
      context: context,
      loadVpnMode: SettingsStorage.getVpnMode,
      isForeignVpnActive: _vpn.isForeignVpnActive,
    )) {
      return;
    }
    if (!mounted) return;





    final inFlight = _rebuildInFlight;
    if (inFlight != null) await inFlight;


    if (_subController.configDirty || _subController.groupDefaultsPending) {
      await _rebuildAndClearDirty();
    }
    if (!mounted) return;


    if (_showDetourCycleSheetIfAny()) return;







    await _runWithCoreRejectGuard();





  }









  Future<void> _runWithCoreRejectGuard() async {
    await runCoreRejectGuard(
      home: _controller,
      sub: _subController,


      rebuildAndSave: () async {
        final ok = await _rebuildConfig(silent: true);
        return ok ? _controller.state.configRaw : null;
      },
      askPrompt: (limit) async {
        if (!mounted) return CoreRejectPrompt.stop;

        final viaApi = CoreRejectState.I.askPrompt(limit);
        final viaUi = showCoreRejectPrompt(context, limit);
        final answer = await Future.any([viaApi, viaUi]);
        CoreRejectState.I.answerPrompt(answer);
        return answer;
      },
    );
  }










  Future<void> _rebuildAndClearDirty({bool silent = false}) {
    return _rebuildInFlight ??= () async {
      try {



        final autoReload = await SettingsStorage.getAutoReloadOnChange();
        if (!mounted) return;

        if (autoReload) setState(() => _autoApplying = true);
        final ok = await _rebuildConfig(silent: silent, autoReload: autoReload);
        if (mounted) setState(() {});





        if (ok && autoReload) await _maybeAutoReload();
      } finally {
        _rebuildInFlight = null;
        if (_autoApplying && mounted) setState(() => _autoApplying = false);
        _autoApplying = false;
      }
    }();
  }








  Future<void> _maybeAutoReload() async {
    if (!mounted) return;
    final state = _controller.state;

    if (!state.tunnelUp) return;
    if (!state.configChangedNeedRestart) {
      AppLog.I.debug('§338: reload skipped — config identical to running');
      return;
    }




    if (!_controller.canReload) {
      AppLog.I.warning(
        '§338: reload skipped — cooldown/not-connected, banner stays',
      );
      return;
    }
    AppLog.I.info('§338: auto-reload on settings change');
    await _controller.reloadVpn();
  }






  void _onReturnToHome() {
    if (!mounted) return;
    if (!_subController.configDirty) return;
    if (_subController.busy) {


      _retryRebuildWhenIdle();
      return;
    }
    unawaited(_rebuildAndClearDirty());
  }



  void _retryRebuildWhenIdle() {
    if (_idleRetryListener != null) return;
    void listener() {
      if (_subController.busy) return;
      _subController.removeListener(listener);
      _idleRetryListener = null;
      if (!mounted || !_subController.configDirty) return;
      unawaited(_rebuildAndClearDirty());
    }

    _idleRetryListener = listener;
    _subController.addListener(listener);
  }














  Future<void> _reactToSubscriptionUpdate({required bool reload}) async {
    if (!mounted) return;










    final inFlight = _rebuildInFlight;
    if (inFlight != null) {
      await inFlight;
      if (!mounted) return;
    }
    await _rebuildAndClearDirty(silent: true);
    if (!mounted) return;



    if (!reload) return;

    if (!_controller.state.tunnelUp) return;


    if (!_controller.state.configChangedNeedRestart) {
      AppLog.I.debug('§323: reload skipped — config identical to running');
      return;
    }


    await _controller.reloadVpn();
  }


















  void _showRebuildFailed() {
    if (_subController.lastFatalIssues.whereType<DetourCycle>().isNotEmpty) {
      return;
    }
    final err = _subController.lastError;
    if (err == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          getLocalText.s("Config rebuild failed: %s", err.render()),
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Future<bool> _rebuildConfig({
    bool silent = false,
    bool autoReload = false,
  }) async {
    final config = await _subController.generateConfig();
    if (config == null) {


      if (mounted && !silent) _showRebuildFailed();
      return false;
    }
    if (!mounted) {
      _subController.configDirty = true;
      return false;
    }
    final ok = await _controller.saveParsedConfig(config);
    if (!ok) {
      _subController.configDirty = true;
      return false;
    }
    if (mounted && !silent) {
      final nodeCount = ParsedConfig.parse(config).nodeCount;










      final needRestart = _controller.state.configChangedNeedRestart;
      final willAutoReload =
          autoReload && _controller.state.tunnelUp && needRestart;


      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !_controller.state.tunnelUp || !needRestart
                ? getLocalText.plural("Config rebuilt: %d nodes", nodeCount)
                : willAutoReload
                ? getLocalText.plural(
                    "Config rebuilt: %d nodes — reloading VPN",
                    nodeCount,
                  )
                : getLocalText.plural(
                    "Config rebuilt: %d nodes — restart VPN to apply",
                    nodeCount,
                  ),
          ),
        ),
      );
    }
    return true;
  }
}
