import '../../models/node_spec.dart';
import '../../models/tunnel_status.dart';
import '../../vpn/box_vpn_client.dart';
import '../../vpn/cc_channel.dart';
import '../builder/core_chain_capability.dart';
import '../probe/probe_config.dart';
import '../probe/probe_lifecycle.dart';





class DiagnosticOutcome {
  const DiagnosticOutcome({
    required this.source,
    required this.result,
  });

  final DiagnosticSource source;
  final CcGetUrlResult result;

  bool get ok => result.ok;
}


enum DiagnosticSource {

  probe,


  live,
}












class NodeDiagnosticsRunner {
  NodeDiagnosticsRunner({CcChannel? cc, BoxVpnClient? vpn})
      : _cc = cc ?? CcChannel.instance,
        _vpn = vpn ?? BoxVpnClient();

  final CcChannel _cc;
  final BoxVpnClient _vpn;



  static const int kTimeoutMs = 10000;



  static const int kMaxBytes = 64 * 1024;

  bool _cancelled = false;



  void cancel() => _cancelled = true;














  Future<DiagnosticOutcome> run(
    NodeSpec? node, {
    required String url,
    required String liveTag,
  }) async {
    _cancelled = false;
    final canceller = ProbeLifecycle.I.register(cancel);
    try {
      final vpnUp = (await _vpn.getVpnStatus()) != TunnelStatus.disconnected;
      if (_cancelled) throw const DiagnosticUnavailable('cancelled');
      if (vpnUp) return await _runLive(url: url, tag: liveTag);
      if (node == null) throw const DiagnosticUnavailable('no_node');
      return await _runProbe(node, url: url);
    } finally {
      ProbeLifecycle.I.deregister(canceller);
    }
  }


  Future<DiagnosticOutcome> _runLive({
    required String url,
    required String tag,
  }) async {
    final r = await _cc.getUrlViaOutbound(
      tag,
      link: url,
      timeoutMs: kTimeoutMs,
      maxBytes: kMaxBytes,
    );
    return DiagnosticOutcome(source: DiagnosticSource.live, result: r);
  }






  Future<DiagnosticOutcome> _runProbe(
    NodeSpec node, {
    required String url,
  }) async {

    final coreVersion = await CoreVersionCache.ensure(_vpn.getCoreVersion);
    final cfg = buildProbeConfig([node], coreVersion: coreVersion);
    final tag = cfg.tagByIndex[0];
    if (cfg.configJson == null || tag == null) {


      throw DiagnosticUnavailable(cfg.brokenByIndex[0] ?? 'invalid node');
    }

    final err = await _cc.probeStart(cfg.configJson!);
    if (err.isNotEmpty) throw DiagnosticUnavailable(err);
    try {
      if (_cancelled) throw const DiagnosticUnavailable('cancelled');
      final r = await _cc.probeGetUrl(
        tag,
        link: url,
        timeoutMs: kTimeoutMs,
        maxBytes: kMaxBytes,
      );
      return DiagnosticOutcome(source: DiagnosticSource.probe, result: r);
    } finally {


      await _cc.probeStop();
    }
  }
}



class DiagnosticUnavailable implements Exception {
  const DiagnosticUnavailable(this.reason);

  final String reason;


  bool get isGroup => reason == 'group';

  @override
  String toString() => reason;
}
