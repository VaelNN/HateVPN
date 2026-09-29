import 'dart:async';

import '../../models/node_spec.dart';
import '../../vpn/box_vpn_client.dart';
import '../../vpn/cc_channel.dart';
import '../app_log.dart';
import '../builder/core_chain_capability.dart';
import 'probe_config.dart';
import 'probe_lifecycle.dart';




const kProbeVpnRunning = '__vpn_running__';


enum ProbeStatus {

  pending,


  ok,


  failed,


  broken,


  invalid,



  group,
}

class ProbeResult {
  const ProbeResult(this.status, {this.delayMs = 0, this.message = ''});

  final ProbeStatus status;
  final int delayMs;
  final String message;
}










class ProbeRunner {
  ProbeRunner({CcChannel? cc}) : _cc = cc ?? CcChannel.instance;

  final CcChannel _cc;
  bool _cancelled = false;



  static const _concurrency = 6;

  void cancel() => _cancelled = true;








  Future<String> run(
    List<NodeSpec?> nodes, {
    required String url,
    required int timeoutMs,
    required void Function(int index, ProbeResult result) onResult,
  }) async {
    _cancelled = false;



    final canceller = ProbeLifecycle.I.register(cancel);
    try {












      final coreVersion = await CoreVersionCache.ensure(
          () => BoxVpnClient().getCoreVersion());
      final batches = buildProbeBatches(nodes, coreVersion: coreVersion);



      final broken = batches.isEmpty
          ? buildProbeConfig(nodes, coreVersion: coreVersion).brokenByIndex
          : batches.first.brokenByIndex;
      broken.forEach((i, why) {
        onResult(
            i,
            ProbeResult(
              switch (why) {
                'broken' => ProbeStatus.broken,
                'group' => ProbeStatus.group,
                _ => ProbeStatus.invalid,
              },
              message: why,
            ));
      });
      if (batches.isEmpty) return '';

      for (final cfg in batches) {
        if (_cancelled) return '';
        if (cfg.configJson == null) continue;
        final err = await _cc.probeStart(cfg.configJson!);
        if (err.isNotEmpty) {



          if (_looksLikeVpnRunning(err)) return kProbeVpnRunning;
          AppLog.I.warning('Probe session failed to start: $err');
          return err;
        }
        try {
          await _runPool(
            cfg.tagByIndex,
            test: (tag) =>
                _cc.probeUrlTest(tag, link: url, timeoutMs: timeoutMs),
            onResult: onResult,
          );
        } finally {



          await _cc.probeStop();
        }
      }
      return '';
    } finally {
      ProbeLifecycle.I.deregister(canceller);
    }
  }

  static bool _looksLikeVpnRunning(String err) =>
      err.toLowerCase().contains('vpn is running');

  Future<void> _runPool(
    Map<int, String> tags, {
    required Future<CcDelayResult> Function(String tag) test,
    required void Function(int index, ProbeResult result) onResult,
  }) async {
    final queue = tags.entries.toList();
    var next = 0;
    Future<void> worker() async {
      while (true) {
        if (_cancelled) return;
        if (next >= queue.length) return;
        final entry = queue[next++];
        final r = await test(entry.value);
        if (_cancelled) return;
        onResult(
          entry.key,
          r.ok
              ? ProbeResult(ProbeStatus.ok, delayMs: r.delay)
              : ProbeResult(ProbeStatus.failed, message: r.error),
        );
      }
    }

    await Future.wait([
      for (var w = 0; w < _concurrency; w++) worker(),
    ]);
  }
}


class ProbeThresholds {
  const ProbeThresholds({
    this.greenMs = 250,
    this.yellowMs = 500,
    this.orangeMs = 700,
  });



  static const defaults = ProbeThresholds();

  final int greenMs;
  final int yellowMs;
  final int orangeMs;


  int bandOf(int delayMs) {
    if (delayMs <= greenMs) return 0;
    if (delayMs <= yellowMs) return 1;
    if (delayMs <= orangeMs) return 2;
    return 3;
  }
}
