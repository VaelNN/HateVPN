import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_info_cache.dart';
import '../services/format_utils.dart';
import '../services/rule_name_resolver.dart';
import '../vpn/cc_channel.dart';
import 'connections_screen/connection_detail_sheet.dart';
import '../services/l10n/locale_controller.dart';









const Duration oneWayMinAge = Duration(seconds: 3);

bool isOneWayStuck({
  required String network,
  required int upload,
  required int download,
  required DateTime? startTime,
  required bool closed,
  DateTime? now,
}) {
  if (closed) return false;
  if (network != 'tcp') return false;
  if (startTime == null) return false;
  final age = (now ?? DateTime.now()).difference(startTime);
  if (age < oneWayMinAge) return false;
  return (upload > 0 && download == 0) || (upload == 0 && download > 0);
}






String ruleName(String rule) => RuleNameResolver.I.resolve(rule);








class ConnectionsView extends StatefulWidget {
  const ConnectionsView({super.key});

  @override
  State<ConnectionsView> createState() => _ConnectionsViewState();
}

class _ConnectionsViewState extends State<ConnectionsView> {
  final _cc = CcChannel.instance;
  StreamSubscription<List<CcConnection>>? _sub;



  final Map<String, CcConnection> _byId = {};
  final Set<String> _closedIds = {};
  final Map<String, DateTime> _closedAt = {};
  bool _accumulate = false;
  bool _loading = true;




  static const _closedWindow = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _sub = _cc.connections.listen(_onConnections);
  }

  void _onConnections(List<CcConnection> conns) {
    if (!mounted) return;




    final liveIds = conns
        .where((c) => c.closedAt == 0)
        .map((c) => c.id)
        .where((id) => id.isNotEmpty)
        .toSet();
    final now = DateTime.now();


    for (final c in conns) {
      if (c.closedAt > 0 && c.id.isNotEmpty && _closedIds.add(c.id)) {
        _closedAt[c.id] = now;
      }
    }


    for (final id in _byId.keys.toList()) {
      if (id.isNotEmpty && !liveIds.contains(id) && _closedIds.add(id)) {
        _closedAt[id] = now;
      }
    }


    for (final c in conns) {
      if (c.id.isNotEmpty) _byId[c.id] = c;
    }

    if (!_accumulate) {
      _closedIds.removeWhere((id) {
        final at = _closedAt[id];
        final expired = at == null || now.difference(at) > _closedWindow;
        if (expired) {
          _byId.remove(id);
          _closedAt.remove(id);
        }
        return expired;
      });
    }




    if (!_loading &&
        _rebuildAt != null &&
        now.difference(_rebuildAt!) < _rebuildThrottle) {
      return;
    }
    _rebuildAt = now;
    setState(() => _loading = false);
  }


  static const _rebuildThrottle = Duration(milliseconds: 700);
  DateTime? _rebuildAt;


  List<CcConnection> get _sorted {
    final list = _byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _closeConnection(String id) async {
    if (id.isEmpty) return;
    await _cc.closeConnection(id);
  }

  Future<void> _closeAll() async {

    final liveNow = _byId.values
        .where((c) => c.closedAt == 0 && c.id.isNotEmpty)
        .map((c) => c.id)
        .toList();
    final ok = await _cc.closeConnections();
    if (!mounted) return;
    if (ok) {




      final now = DateTime.now();
      setState(() {
        for (final id in liveNow) {
          if (_closedIds.add(id)) _closedAt[id] = now;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(liveNow.isEmpty
              ? getLocalText.s("No active connections to close")
              : getLocalText.plural("Closed %d connections", liveNow.length)),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(getLocalText.s("Failed to close connections (tunnel down?)")),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = _sorted;
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [

              IconButton(
                tooltip: _accumulate
                    ? getLocalText.s("Keeping all closed (tap for 30s window)")
                    : getLocalText.s("Closed kept 30s (tap to keep all)"),
                icon: Icon(
                  _accumulate ? Icons.history_toggle_off : Icons.history,
                ),
                onPressed: () {
                  setState(() {
                    _accumulate = !_accumulate;
                    if (!_accumulate) {

                      _byId.removeWhere((id, _) => _closedIds.contains(id));
                      _closedIds.clear();
                      _closedAt.clear();
                    }
                  });
                },
              ),
              const Spacer(),



              Text(
                getLocalText.s("%1\$d active / %2\$d total", list
                        .where((c) =>
                            c.closedAt == 0 && !_closedIds.contains(c.id))
                        .length, list.length),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              if (list.isNotEmpty)
                IconButton(
                  tooltip: getLocalText.s("Close all"),
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _closeAll,
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? Center(child: Text(getLocalText.s("No active connections")))
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) => _buildTile(list[i]),
                    ),
        ),
      ],
    );
  }



  Widget _buildTile(CcConnection conn) {
    final network = conn.network;
    final destPort = portOf(conn.destination);

    final host = conn.domain.isNotEmpty ? conn.domain : hostOf(conn.destination);
    final display = destPort.isNotEmpty ? '$host:$destPort' : host;

    final upload = conn.uplink;
    final download = conn.downlink;
    final id = conn.id;
    final closed = conn.isClosed || _closedIds.contains(id);

    final startTime = conn.createdAt > 0
        ? DateTime.fromMillisecondsSinceEpoch(conn.createdAt)
        : null;
    final endTime = closed
        ? (conn.closedAt > 0
            ? DateTime.fromMillisecondsSinceEpoch(conn.closedAt)
            : (_closedAt[id] ?? DateTime.now()))
        : DateTime.now();
    final duration = startTime != null ? endTime.difference(startTime) : null;

    final oneWay = isOneWayStuck(
      network: network,
      upload: upload,
      download: download,
      startTime: startTime,
      closed: closed,
    );

    final cs = Theme.of(context).colorScheme;
    final rule = ruleName(conn.rule);

    return Container(

      color: oneWay && !closed
          ? Color.alphaBlend(Colors.pink.withValues(alpha: 0.16), cs.surface)
          : null,
      child: Opacity(
        opacity: closed ? 0.5 : 1.0,
        child: InkWell(
          onTap: () => unawaited(showConnectionDetailSheet(
            context,
            conn,
            oneWay: oneWay,
            closed: closed,
            onClose: (cid) => unawaited(_closeConnection(cid)),
          )),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [



                Row(
                  children: [
                    _appIcon(conn.packageName, network: network, closed: closed),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        display,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '↑${formatBytes(upload)} ↓${formatBytes(download)}',
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: IconButton(
                        icon: const Icon(Icons.close, size: 14),
                        padding: EdgeInsets.zero,
                        tooltip: getLocalText.s("Close"),
                        onPressed: (closed || id.isEmpty)
                            ? null
                            : () => _closeConnection(id),
                      ),
                    ),
                  ],
                ),




                Padding(
                  padding: const EdgeInsets.only(left: 22, top: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          conn.routingLineOf(compact: true, ruleLabel: rule),
                          style: TextStyle(fontSize: 11, color: cs.primary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (closed) ...[
                        const SizedBox(width: 6),
                        Text(getLocalText.s("closed"),
                            style: TextStyle(
                                fontSize: 10, color: cs.onSurfaceVariant)),
                      ],
                      if (duration != null) ...[
                        const SizedBox(width: 6),
                        Text(formatDurationCoarse(duration),
                            style: TextStyle(
                                fontSize: 10, color: cs.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }





  Widget _appIcon(String pkg, {required String network, required bool closed}) {
    const double size = 16;
    final cs = Theme.of(context).colorScheme;
    final fallback = Icon(
      closed
          ? Icons.check_circle_outline
          : (network == 'udp' ? Icons.swap_horiz : Icons.arrow_forward),
      size: size,
      color: closed ? cs.primary : cs.onSurfaceVariant,
    );
    if (pkg.isEmpty) return fallback;
    AppInfoCache.ensure(pkg);
    return AnimatedBuilder(
      animation: AppInfoCache.revision,
      builder: (context, _) {
        final icon = AppInfoCache.of(pkg)?.icon;
        if (icon == null) return fallback;
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.memory(icon,
              width: size, height: size, gaplessPlayback: true),
        );
      },
    );
  }


}
