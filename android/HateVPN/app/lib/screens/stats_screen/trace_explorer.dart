import 'package:flutter/material.dart';

import '../../services/traffic_profiler.dart';
import '../per_app_trace_tab/widgets/aggregate_axis.dart';
import '../per_app_trace_tab/widgets/aggregated_view.dart';
import '../per_app_trace_tab/widgets/live_view.dart';
import 'aggregate_detail_sheet.dart';
import 'profiler_filter.dart';
import 'profiler_filter_sheet.dart';
import 'traffic_event_detail_sheet.dart';
import '../../services/l10n/locale_controller.dart';

















class TraceExplorer extends StatefulWidget {
  const TraceExplorer({
    super.key,
    required this.events,
    required this.unattributed,
    required this.recording,
    required this.filter,
    this.showAppTab = true,
    this.includeAppsFilter = true,
    this.showRetention = false,
  });

  final List<TrafficEvent> events;
  final List<TrafficEvent> unattributed;
  final bool recording;


  final ProfilerFilter filter;


  final bool showAppTab;


  final bool includeAppsFilter;



  final bool showRetention;

  @override
  State<TraceExplorer> createState() => _TraceExplorerState();
}

enum _Mode { live, aggregated }

class _TraceExplorerState extends State<TraceExplorer> {
  _Mode _mode = _Mode.live;
  AggAxis _aggAxis = AggAxis.domain;



  bool _paused = false;
  List<TrafficEvent>? _frozenEvents;
  List<TrafficEvent>? _frozenUnattributed;

  ProfilerFilter get _filter => widget.filter;

  @override
  void initState() {
    super.initState();
    _filter.addListener(_onFilterChanged);


    TrafficProfiler.I.loadRetention().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(TraceExplorer old) {
    super.didUpdateWidget(old);
    if (old.filter != widget.filter) {
      old.filter.removeListener(_onFilterChanged);
      _filter.addListener(_onFilterChanged);
    }
  }

  @override
  void dispose() {
    _filter.removeListener(_onFilterChanged);
    super.dispose();
  }

  void _onFilterChanged() {
    if (mounted) setState(() {});
  }



  void _applySearchKey(String key, {bool switchToAggregated = false}) {
    final clean = key.trim();
    if (clean.isEmpty) return;
    setState(() {
      _filter.search = _filter.search == clean ? '' : clean;
      if (switchToAggregated) {
        _mode = _Mode.aggregated;
        _aggAxis = AggAxis.domain;
      }
    });
  }

  void _togglePause() {
    setState(() {
      _paused = !_paused;
      if (_paused) {
        _frozenEvents = List.of(widget.events);
        _frozenUnattributed = List.of(widget.unattributed);
      } else {
        _frozenEvents = null;
        _frozenUnattributed = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {

    final srcEvents = _paused ? (_frozenEvents ?? const []) : widget.events;
    final srcUnattr =
        _paused ? (_frozenUnattributed ?? const []) : widget.unattributed;

    return Column(
      children: [
        _controlBar(context),
        Expanded(child: _body(context, srcEvents, srcUnattr)),
      ],
    );
  }


  Widget _controlBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [

          if (_mode == _Mode.live)
            IconButton(
              tooltip: _paused
                  ? getLocalText.s("Resume")
                  : getLocalText.s("Pause"),
              icon: Icon(_paused ? Icons.play_arrow : Icons.pause, size: 22),
              color: _paused ? cs.error : cs.primary,
              onPressed: _togglePause,
            ),



          if (widget.showRetention) _retentionButton(context),

          _aggregateButton(context),
          const Spacer(),

          _filterButton(context),
        ],
      ),
    );
  }


  Widget _retentionButton(BuildContext context) {
    const opts = <(String, int)>[
      ('1m', 60),
      ('10m', 600),
      ('1h', 3600),
    ];
    final curSec = TrafficProfiler.I.retention.inSeconds;
    String curLabel() {
      for (final (l, s) in opts) {
        if (s == curSec) return l;
      }
      return '${(curSec / 60).round()}m';
    }

    return PopupMenuButton<int>(
      tooltip: getLocalText.s("Live retention window"),
      onSelected: (sec) async {
        await TrafficProfiler.I.setRetention(Duration(seconds: sec));
        if (mounted) setState(() {});
      },
      itemBuilder: (_) => [
        for (final (label, sec) in opts)
          PopupMenuItem(
            value: sec,
            child: Row(
              children: [
                Icon(
                  sec == curSec
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(getLocalText.s("Keep %s", label)),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history, size: 18),
            const SizedBox(width: 2),
            Text(curLabel(), style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }


  Widget _aggregateButton(BuildContext context) {
    final isLive = _mode == _Mode.live;
    final IconData icon;
    final String label;
    if (isLive) {
      icon = Icons.stream;
      label = 'Stream';
    } else {
      icon = Icons.summarize;
      label = _aggAxis == AggAxis.domain ? 'by Domain' : 'by IP';
    }
    return PopupMenuButton<String>(
      tooltip: getLocalText.s("Grouping"),
      onSelected: (v) => setState(() {
        switch (v) {
          case 'stream':
            _mode = _Mode.live;
          case 'domain':
            _mode = _Mode.aggregated;
            _aggAxis = AggAxis.domain;
          case 'ip':
            _mode = _Mode.aggregated;
            _aggAxis = AggAxis.ip;
        }
        if (_mode != _Mode.live) {
          _paused = false;
          _frozenEvents = null;
          _frozenUnattributed = null;
        }
      }),
      itemBuilder: (_) => [
        _aggMenuItem('stream', Icons.stream, 'Event stream', isLive),
        _aggMenuItem('domain', Icons.summarize, 'Group by Domain',
            !isLive && _aggAxis == AggAxis.domain),
        _aggMenuItem('ip', Icons.summarize, 'Group by IP',
            !isLive && _aggAxis == AggAxis.ip),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _aggMenuItem(
      String value, IconData icon, String label, bool selected) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 18,
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }




  ({Set<String> apps, bool hasUnattr, Set<String> rules, Set<String> outbounds})
      _collectSeen() {
    final apps = <String>{};
    final rules = <String>{};
    final outbounds = <String>{};
    var hasUnattr = false;
    for (final e in widget.events) {
      if (e.confidence == ConfidenceLevel.unattributed || e.process == null) {
        hasUnattr = true;
      }
      final p = e.process;
      if (p != null && p.isNotEmpty) {

        for (final seg in p.split(',')) {
          final t = seg.trim();
          if (t.isNotEmpty) apps.add(t);
        }
      }
      rules.add(e.rule ?? '');
      outbounds.addAll(e.outboundChain);
      outbounds.addAll(e.detourChain);
    }
    for (final e in widget.unattributed) {
      if (e.confidence == ConfidenceLevel.unattributed || e.process == null) {
        hasUnattr = true;
      }
    }
    return (
      apps: apps,
      hasUnattr: hasUnattr,
      rules: rules,
      outbounds: outbounds,
    );
  }

  void _openFilterSheet(BuildContext context) {
    final seen = _collectSeen();
    showProfilerFilterSheet(
      context,
      filter: _filter,
      showAppTab: widget.showAppTab,
      seenApps: seen.apps,
      hasUnattributed: seen.hasUnattr,
      seenRules: seen.rules,
      seenOutbounds: seen.outbounds,
    );
  }



  Widget _filterButton(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final n = widget.includeAppsFilter
        ? _filter.activeCount
        : _filter.activeCountNoApps;
    final active = n > 0;


    return Stack(
      clipBehavior: Clip.none,
      children: [
        TextButton.icon(
          icon: Icon(Icons.filter_list,
              size: 20, color: active ? cs.primary : null),
          label: Text(
              active
                  ? getLocalText.s("Filter (%d)", n)
                  : getLocalText.s("Filter"),
              style:
                  TextStyle(fontSize: 12, color: active ? cs.primary : null)),
          onPressed: () => _openFilterSheet(context),
        ),
        if (active)
          const Positioned(
            right: 6,
            top: 4,
            child: IgnorePointer(
              child: SizedBox(
                width: 9,
                height: 9,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _body(BuildContext context, List<TrafficEvent> srcEvents,
      List<TrafficEvent> srcUnattr) {
    if (_mode == _Mode.live) {
      return LiveView(
        recording: widget.recording,
        events: _applyFilter(srcEvents).toList().reversed.toList(),
        unattributed: _applyFilter(srcUnattr).toList().reversed.toList(),
        onOpenDetail: (e) => showTrafficEventDetailSheet(context, e,
            onSearchKey: _applySearchKey),
      );
    }


    final agg = computeTraceAggregates(srcEvents);
    return AggregatedView(
      events: srcEvents,
      byDomain: agg.byDomain,
      byIp: agg.byIp,
      axis: _aggAxis,
      search: _filter.search,
      onOpenAggregate: (key) => showAggregateDetailSheet(
        context,
        events: srcEvents,
        byDomain: agg.byDomain,
        byIp: agg.byIp,
        axis: _aggAxis,
        key: key,
        onSearchKey: (k) => _applySearchKey(k, switchToAggregated: true),
      ),
    );
  }

  Iterable<TrafficEvent> _applyFilter(Iterable<TrafficEvent> src) =>
      _filter.apply(src, includeApps: widget.includeAppsFilter);
}
