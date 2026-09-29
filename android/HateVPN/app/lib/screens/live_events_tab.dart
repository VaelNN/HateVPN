















import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../controllers/home_controller.dart';
import '../controllers/subscription_controller.dart';
import '../services/traffic_profiler.dart';
import '../widgets/core_logs_hint_banner.dart';
import 'live_events_tab/dns_health_banner.dart';
import 'live_events_tab/recording_header.dart';
import 'live_events_tab/unattributed_banner.dart';
import 'per_app_trace_tab/session_json.dart';
import 'stats_screen/profiler_filter.dart';
import 'stats_screen/profiler_filters.dart';
import 'stats_screen/trace_explorer.dart';
import '../services/l10n/locale_controller.dart';
import '../widgets/app_bottom_sheet.dart';

class LiveEventsTab extends StatefulWidget {
  const LiveEventsTab({super.key, this.subController, this.homeController});



  final SubscriptionController? subController;
  final HomeController? homeController;

  @override
  State<LiveEventsTab> createState() => _LiveEventsTabState();
}

class _LiveEventsTabState extends State<LiveEventsTab> {
  StreamSubscription<Map<String, Object?>>? _sub;


  final List<TrafficEvent> _events = [];
  Timer? _ticker;








  static const _rebuildThrottle = Duration(milliseconds: 700);
  DateTime? _rebuiltAt;
  bool _pendingRebuild = false;
  Timer? _rebuildTimer;






  ProfilerFilter get _filter => ProfilerFilters.liveTab;

  @override
  void initState() {
    super.initState();



    final snapshot = TrafficProfiler.I.globalSnapshot(seconds: 60);
    _events.addAll(snapshot);
    _sub = TrafficProfiler.I.globalLiveStream().listen(_onEvent);
    TrafficProfiler.I.addListener(_onProfilerChanged);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && TrafficProfiler.I.isGlobalRecording) setState(() {});
    });
  }

  void _onProfilerChanged() {
    if (!mounted) return;
    setState(() {

      if (!TrafficProfiler.I.isGlobalRecording) return;
      _events.clear();
    });
  }

  void _toggleRecording() {
    if (TrafficProfiler.I.isGlobalRecording) {
      TrafficProfiler.I.stopGlobalRecording();
    } else {
      TrafficProfiler.I.startGlobalRecording();
    }
  }


  Future<void> _exportEvents() async {
    if (_events.isEmpty) return;
    final json =
        const JsonEncoder.withIndent('  ').convert(eventsToJson(_events));
    if (!mounted) return;
    await showAppBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share),
              title: Text(getLocalText.plural("Share %d events (JSON)", _events.length)),
              onTap: () {
                Navigator.pop(sheetCtx);
                SharePlus.instance.share(
                    ShareParams(text: json, subject: 'LxBox profiler export'));
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text(getLocalText.s("Copy JSON to clipboard")),
              onTap: () async {
                Navigator.pop(sheetCtx);
                await Clipboard.setData(ClipboardData(text: json));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(getLocalText.s("Export JSON copied"))),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _onEvent(Map<String, Object?> msg) {
    if (msg['event'] != 'traffic_event') return;
    final data = msg['data'];
    if (data is! Map) return;





    final now = DateTime.now();
    if (_rebuiltAt != null &&
        now.difference(_rebuiltAt!) < _rebuildThrottle) {

      if (!_pendingRebuild) {
        _pendingRebuild = true;
        final wait = _rebuildThrottle - now.difference(_rebuiltAt!);
        _rebuildTimer = Timer(wait, () {
          _pendingRebuild = false;
          if (mounted) _rebuildFromBuffer();
        });
      }
      return;
    }
    _rebuildFromBuffer();
  }




  void _rebuildFromBuffer() {
    if (!mounted) return;
    setState(() {
      final fresh = TrafficProfiler.I.globalRollingBuffer;
      _events
        ..clear()
        ..addAll(fresh);
    });
    _rebuiltAt = DateTime.now();
  }

  @override
  void dispose() {
    _sub?.cancel();
    TrafficProfiler.I.removeListener(_onProfilerChanged);

    _ticker?.cancel();
    _rebuildTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LiveRecordingHeader(
          eventCount: _events.length,
          onToggle: _toggleRecording,

          onExport: _exportEvents,
        ),
        const Divider(height: 1),
        const CoreLogsHintBanner(),
        if (TrafficProfiler.I.unattributedBannerActive)
          const UnattributedBanner(),

        if (TrafficProfiler.I.dnsHealthUnhealthy)
          DnsHealthBanner(
            subController: widget.subController,
            homeController: widget.homeController,
          ),
        Expanded(
          child: TraceExplorer(







            events: _events,
            unattributed: const [],
            recording: TrafficProfiler.I.isGlobalRecording,
            filter: _filter,

            showRetention: true,
          ),
        ),
      ],
    );
  }
}
