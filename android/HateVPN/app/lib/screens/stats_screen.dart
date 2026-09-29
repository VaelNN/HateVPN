import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/home_controller.dart';
import '../controllers/subscription_controller.dart';
import '../models/config_node.dart';
import '../services/format_utils.dart';
import '../services/traffic_profiler.dart';
import '../widgets/banner_palette.dart';
import '../vpn/box_vpn_client.dart';
import '../vpn/cc_channel.dart';
import 'connections_screen.dart';
import 'live_events_tab.dart';
import 'stats_screen/overview_models.dart';
import 'stats_screen/overview_tab.dart';
import '../services/l10n/locale_controller.dart';





enum StatsTab { overview, connections, live }




class StatsScreen extends StatefulWidget {
  const StatsScreen({
    super.key,
    this.configRaw = '',
    this.initialTab = StatsTab.overview,
    this.subController,
    this.homeController,
  });

  final String configRaw;
  final StatsTab initialTab;



  final SubscriptionController? subController;
  final HomeController? homeController;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  Map<String, OutboundGroup> _groups = {};
  int _totalUp = 0;
  int _totalDown = 0;
  int _totalConns = 0;
  int _memory = 0;
  int _goroutines = 0;
  int _connsIn = 0;
  int _connsOut = 0;
  Map<String, int> _byRule = const {};
  bool _loading = true;





  static const _connRecalc = Duration(milliseconds: 700);
  DateTime? _connRecalcAt;

  final _cc = CcChannel.instance;
  StreamSubscription<CcStatus>? _statusSub;
  StreamSubscription<List<CcConnection>>? _connSub;


  late final ParsedConfig _intro = ParsedConfig.parse(widget.configRaw);



  bool _currentSessionAllowBypass = false;
  final _vpn = BoxVpnClient();

  @override
  void initState() {
    super.initState();



    _statusSub = _cc.status.listen(_onStatus);
    _connSub = _cc.connections.listen(_onConnections);

    unawaited(_cc.connectScreen());


    unawaited(_cc.setStatusFast(true));
    unawaited(_refreshAllowBypass());
  }

  List<String> _detourChain(String tag) => _intro.detourChain(tag);

  @override
  void dispose() {
    _statusSub?.cancel();
    _connSub?.cancel();
    unawaited(_cc.disconnectScreen());

    unawaited(_cc.setStatusFast(false));
    super.dispose();
  }

  void _onStatus(CcStatus s) {
    if (!mounted) return;



    setState(() {
      _totalUp = s.uplinkTotal;
      _totalDown = s.downlinkTotal;
      _memory = s.memory;
      _goroutines = s.goroutines;
      _connsIn = s.connectionsIn;
      _connsOut = s.connectionsOut;
    });
  }

  void _onConnections(List<CcConnection> conns) {





    final now = DateTime.now();
    if (!_loading &&
        _connRecalcAt != null &&
        now.difference(_connRecalcAt!) < _connRecalc) {
      return;
    }


    unawaited(_refreshAllowBypass());





    final live = conns.where((c) => c.closedAt == 0).toList();
    _totalConns = live.length;

    final byRule = <String, int>{};
    final perRule = <String, OutboundGroup>{};
    for (final c in live) {


      final rule = ruleName(c.rule);
      byRule[rule] = (byRule[rule] ?? 0) + 1;




      final destPort = portOf(c.destination);
      final host = c.domain.isNotEmpty ? c.domain : hostOf(c.destination);

      final conn = Connection(
        host: host,
        destPort: destPort,
        network: c.network,
        rule: c.rule,
        upload: c.uplink,
        download: c.downlink,
        start: c.createdAt,
      );

      final existing = perRule[rule];
      if (existing != null) {
        existing.upload += c.uplink;
        existing.download += c.downlink;
        existing.connections.add(conn);
      } else {
        perRule[rule] = OutboundGroup(
          name: rule,
          upload: c.uplink,
          download: c.downlink,
          connections: [conn],
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _byRule = byRule;
      _groups = perRule;
      _loading = false;
    });


    _connRecalcAt = DateTime.now();
  }



  Future<void> _refreshAllowBypass() async {
    final v = await _vpn.getCurrentSessionAllowBypass();
    if (!mounted) return;
    if (v != _currentSessionAllowBypass) {
      setState(() => _currentSessionAllowBypass = v);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab.index,
      child: Builder(
        builder: (innerCtx) => Scaffold(
          appBar: AppBar(
            title: Text(getLocalText.s("Statistics")),
            actions: [


              if (_currentSessionAllowBypass)
                Tooltip(
                  message:
                      'VPN bypass is active in this session.\n\n'
                      'Apps can use bindProcessToNetwork() to skip the tunnel '
                      '(banking apps, WhatsApp, system services). '
                      'Some traffic may not go through VPN.\n\n'
                      'Disable in VPN Settings → System → Allow VPN bypass '
                      'and reload VPN to enforce strict tunnel.',
                  triggerMode: TooltipTriggerMode.tap,
                  showDuration: const Duration(seconds: 12),
                  waitDuration: const Duration(milliseconds: 100),
                  preferBelow: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(
                      Icons.warning_amber,
                      size: 22,
                      color: bannerIconColor(innerCtx, BannerSeverity.warning),
                    ),
                  ),
                ),
            ],
            bottom: TabBar(


              tabs: [
                Tab(
                    icon: const Icon(Icons.dashboard_outlined),
                    text: getLocalText.s("Stats")),
                Tab(icon: const Icon(Icons.link), text: getLocalText.s("Conns")),
                Tab(
                  icon: const Icon(Icons.podcasts),
                  child: AnimatedBuilder(
                    animation: TrafficProfiler.I,
                    builder: (_, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(getLocalText.s("Profiler")),
                        if (TrafficProfiler.I.unattributedBannerActive) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.warning_amber,
                            size: 14,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              OverviewTab(
                loading: _loading,
                groups: _groups,
                totalUp: _totalUp,
                totalDown: _totalDown,
                totalConns: _totalConns,
                memory: _memory,
                goroutines: _goroutines,
                connectionsIn: _connsIn,
                connectionsOut: _connsOut,
                byRule: _byRule,
                detourChain: _detourChain,
              ),
              const ConnectionsView(),
              LiveEventsTab(
                subController: widget.subController,
                homeController: widget.homeController,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
