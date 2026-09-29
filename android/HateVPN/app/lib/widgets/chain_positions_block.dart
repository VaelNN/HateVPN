










import 'dart:async';

import 'package:flutter/material.dart';

import '../services/l10n/locale_controller.dart';
import '../services/probe/chain_layer_probe.dart';



class ChainPositionsBlock extends StatefulWidget {
  const ChainPositionsBlock({
    super.key,
    required this.chainTag,
    required this.hops,
    this.probeFactory,
  });

  final String chainTag;


  final List<String> hops;


  final ChainLayerProbe Function()? probeFactory;

  @override
  State<ChainPositionsBlock> createState() => _ChainPositionsBlockState();
}

class _ChainPositionsBlockState extends State<ChainPositionsBlock> {
  ChainLayerProbe? _probe;
  bool _running = false;
  ChainProbeReport? _report;




  String _error = '';

  @override
  void dispose() {


    _probe?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = '';
      _report = null;
    });
    final probe = (widget.probeFactory ?? ChainLayerProbe.new)();
    _probe = probe;
    try {
      final report =
          await probe.run(widget.chainTag, hops: widget.hops);
      if (!mounted) return;
      setState(() => _report = report);
    } on ChainProbeUnavailable catch (e) {
      if (!mounted) return;
      setState(() => _error = switch (e.reason) {
            'vpn_down' => getLocalText.s(
                "Start the VPN to probe this chain — its hops exist only in the running core."),
            'no_positions' =>
              getLocalText.s("This chain has no positions to probe."),
            _ => e.reason,
          });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _running = false);
      _probe = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final report = _report;



    final layerError = report?.layers
        .where((l) => l.error.isNotEmpty)
        .map((l) => l.error)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          getLocalText.plural("Chain positions (%d)", widget.hops.length),
          style: theme.textTheme.titleSmall?.copyWith(
            color: cs.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          getLocalText.s(
              "Cumulative delay to each hop; (+X) is what that hop added."),
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const Divider(),
        for (var i = 0; i < widget.hops.length; i++)
          _positionRow(context, i, report),
        if (layerError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              layerError,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: OutlinedButton.icon(
            onPressed: _running ? null : () => unawaited(_run()),
            icon: _running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh, size: 18),
            label: Text(_running
                ? getLocalText.s("Measuring…")
                : report == null
                    ? getLocalText.s("Probe by position")
                    : getLocalText.s("Probe again")),
          ),
        ),
      ],
    );
  }

  Widget _positionRow(BuildContext context, int i, ChainProbeReport? report) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final layer =
        (report != null && i < report.layers.length) ? report.layers[i] : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,

            child: Text('${i + 1}.',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(widget.hops[i],
                style: const TextStyle(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Text(
            _measureText(i, layer, report),
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: layer == null
                  ? cs.onSurfaceVariant
                  : layer.ok
                      ? cs.onSurface
                      : cs.error,
            ),
          ),
        ],
      ),
    );
  }






  String _measureText(int i, ChainLayerResult? layer, ChainProbeReport? report) {

    if (layer == null) return '—';
    if (layer.notReached) return getLocalText.s("not reached");
    if (layer.error.isNotEmpty) return getLocalText.s("error");
    final delta = report?.deltaAt(i);

    return delta == null
        ? '${layer.cumulativeMs} ms'
        : '${layer.cumulativeMs} ms  (+$delta)';
  }
}
