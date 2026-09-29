import 'package:flutter/material.dart';

import '../../../services/app_info_cache.dart';
import '../../../services/traffic_profiler.dart';
import '../../../services/format_utils.dart';
import '../../../services/process_name.dart';
import 'empty_view.dart';
import '../../../services/l10n/locale_controller.dart';













class LiveView extends StatelessWidget {
  const LiveView({
    super.key,
    required this.recording,
    required this.events,
    required this.unattributed,
    required this.onOpenDetail,
  });

  final bool recording;
  final List<TrafficEvent> events;
  final List<TrafficEvent> unattributed;
  final void Function(TrafficEvent e) onOpenDetail;

  @override
  Widget build(BuildContext context) {
    if (!recording && events.isEmpty && unattributed.isEmpty) {
      return const EmptyView(text: 'Start recording to see events.');
    }
    final cs = Theme.of(context).colorScheme;
    return CustomScrollView(
      slivers: [
        if (events.isEmpty && unattributed.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyView(text: 'Waiting for events…'),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => _eventTile(context, events[i]),
              childCount: events.length,
            ),
          ),
        if (unattributed.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              color: cs.surfaceContainerHigh,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  Icon(Icons.help_outline,
                      size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    getLocalText.s("System-wide events (no owner detected) — %d", unattributed.length),
                    style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => _eventTile(context, unattributed[i], dimmed: true),
              childCount: unattributed.length,
            ),
          ),
        ],
      ],
    );
  }

  Widget _eventTile(BuildContext context, TrafficEvent e,
      {bool dimmed = false}) {
    final cs = Theme.of(context).colorScheme;
    final ts = formatTime(e.ts);
    final tile = InkWell(
      onTap: () => onOpenDetail(e),
      child: _eventTileInner(context, cs, ts, e),
    );
    if (!dimmed) return tile;
    return Opacity(opacity: 0.62, child: tile);
  }





  Widget _eventTileInner(
      BuildContext context, ColorScheme cs, String ts, TrafficEvent e) {



    final (Color kindColor, String kindLabel) = switch (e.kind) {
      TrafficEventKind.dnsResolve => (cs.tertiary, 'DNS'),
      TrafficEventKind.dnsFail => (cs.error, 'DNS'),
      TrafficEventKind.tcpOpen => (cs.primary, 'TCP'),
      TrafficEventKind.tcpClose => (cs.outline, 'TCP·'),
      TrafficEventKind.udpOpen => (cs.secondary, 'UDP'),
    };






    final meta = <String>[];
    final routing = e.routingLineOf(compact: true);
    if (routing.isNotEmpty) meta.add(routing);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _appIcon(context, packageNameFromProcess(e.process ?? '')),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                Row(
                  children: [
                    Text(ts,
                        style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: cs.onSurfaceVariant)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: kindColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(kindLabel,
                          style: TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              color: kindColor)),
                    ),
                    const SizedBox(width: 6),
                    _confidenceBadge(context, e),
                    const SizedBox(width: 4),
                    Expanded(child: _eventSummary(context, e)),
                    if (e.issues.isNotEmpty)
                      Tooltip(
                        message: e.issues.map((a) => a.description).join('\n'),
                        child:
                            Icon(Icons.warning_amber, size: 14, color: cs.error),
                      ),
                    Icon(Icons.chevron_right,
                        size: 16, color: cs.onSurfaceVariant),
                  ],
                ),

                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          (e.process ?? '').isNotEmpty
                              ? e.process!
                              : getLocalText.s("(no owner)"),
                          style: TextStyle(
                              fontSize: 11,
                              color: (e.process ?? '').isNotEmpty
                                  ? cs.primary
                                  : cs.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_isCached(e)) ...[
                        const SizedBox(width: 6),
                        _cachedBadge(context, cs),
                      ],
                    ],
                  ),
                ),

                if (meta.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      meta.join('  ·  '),
                      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),


                if (e.cnameChain.isNotEmpty)
                  _subline(cs, '↳ CNAME ${e.cnameChain.join(" → ")}', mono: true),
                if (e.dnsRecordType != null &&
                    e.dnsRecordType != 'A' &&
                    e.dnsRecordType != 'AAAA' &&
                    e.dnsRecordType != 'CNAME')
                  _subline(cs, 'DNS record: ${e.dnsRecordType}', mono: true),
                if (e.processInferred)
                  _subline(cs, '〽 inferred from prior DNS', italic: true),
                if (e.backfilled)
                  _subline(cs, '〽 backfilled from pre-recording',
                      italic: true),
              ],
            ),
          ),
        ],
      ),
    );
  }




  Widget _appIcon(BuildContext context, String pkg) {
    const double size = 18;
    final cs = Theme.of(context).colorScheme;
    final placeholder = Icon(Icons.apps, size: size, color: cs.onSurfaceVariant);
    if (pkg.isEmpty) return placeholder;
    AppInfoCache.ensure(pkg);
    return AnimatedBuilder(
      animation: AppInfoCache.revision,
      builder: (context, _) {
        final icon = AppInfoCache.of(pkg)?.icon;
        if (icon == null) return placeholder;
        return ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Image.memory(icon,
              width: size, height: size, gaplessPlayback: true),
        );
      },
    );
  }



  static bool _isCached(TrafficEvent e) {
    final s = e.extra?['source']?.toString();
    return s == 'cached' || s == 'optimistic';
  }


  Widget _cachedBadge(BuildContext context, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: cs.secondary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cached, size: 10, color: cs.secondary),
          const SizedBox(width: 2),
          Text(getLocalText.s("cached"),
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: cs.secondary)),
        ],
      ),
    );
  }

  Widget _subline(ColorScheme cs, String text,
      {bool mono = false, bool italic = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontFamily: mono ? 'monospace' : null,
          fontStyle: italic ? FontStyle.italic : null,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }



  Widget _eventSummary(BuildContext context, TrafficEvent e) {
    const style = TextStyle(fontSize: 12);
    final ip = e.ip;
    final port = e.port;
    final domain = e.domain;

    final String text = switch (e.kind) {
      TrafficEventKind.dnsResolve =>
        ip != null ? '${domain ?? "?"} → $ip' : (domain ?? '?'),
      TrafficEventKind.dnsFail => 'DNS exchange failed: ${domain ?? "?"}',
      TrafficEventKind.tcpOpen || TrafficEventKind.udpOpen =>
        (domain != null && domain.isNotEmpty)
            ? '$domain:${port ?? "?"}'
            : '[${ip ?? "?"}]:${port ?? "?"}',
      TrafficEventKind.tcpClose => () {
          final bytes =
              '↑${formatBytes(e.upBytes ?? 0)} ↓${formatBytes(e.downBytes ?? 0)}';
          final hp = (domain != null && domain.isNotEmpty)
              ? '$domain:${port ?? "?"}'
              : '[${ip ?? "?"}]:${port ?? "?"}';
          return '$hp closed · $bytes';
        }(),
    };
    return Text(text, style: style, overflow: TextOverflow.ellipsis);
  }



  Widget _confidenceBadge(BuildContext context, TrafficEvent e) {
    final cs = Theme.of(context).colorScheme;
    if (e.confidence == ConfidenceLevel.verified) {
      return const SizedBox.shrink();
    }
    final (Color color, String label) = switch (e.confidence) {
      ConfidenceLevel.verified => (cs.onSurface, ''),
      ConfidenceLevel.secondary => (cs.tertiary, '🔗 sec'),
      ConfidenceLevel.inferred => (cs.secondary, '〽'),
      ConfidenceLevel.unattributed => (cs.error, '?'),
    };
    final msg = StringBuffer('confidence: ${e.confidence.name}');
    if (e.matchedVia != null) msg.write('\nmatched via: ${e.matchedVia}');
    if (e.shownBecause != null) msg.write('\nshown because: ${e.shownBecause}');
    return Tooltip(
      message: msg.toString(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10, fontFamily: 'monospace', color: color)),
      ),
    );
  }
}
