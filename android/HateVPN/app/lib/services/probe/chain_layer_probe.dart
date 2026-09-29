































import '../../models/tunnel_status.dart';
import '../../vpn/box_vpn_client.dart';
import '../../vpn/cc_channel.dart';
import 'probe_controller.dart';
import 'probe_lifecycle.dart';







String chainLayerTag(String chainTag, int pos) => '$chainTag#$pos';


class ChainLayerResult {
  const ChainLayerResult({
    required this.pos,
    required this.tag,
    required this.probeTag,
    this.cumulativeMs = 0,
    this.error = '',
    this.notReached = false,
  });


  final int pos;


  final String tag;


  final String probeTag;



  final int cumulativeMs;




  final String error;





  final bool notReached;

  bool get ok => error.isEmpty && !notReached;
}


class ChainProbeReport {
  const ChainProbeReport({
    required this.chainTag,
    required this.layers,
    required this.url,
    required this.timeoutMs,
  });

  final String chainTag;
  final List<ChainLayerResult> layers;


  final String url;
  final int timeoutMs;











  int? deltaAt(int i) {
    if (i <= 0 || i >= layers.length) return null;
    final cur = layers[i];
    final prev = layers[i - 1];
    if (!cur.ok || !prev.ok) return null;
    final cost = cur.cumulativeMs - prev.cumulativeMs;
    return cost < 0 ? 0 : cost;
  }
}



class ChainProbeUnavailable implements Exception {
  const ChainProbeUnavailable(this.reason);


  final String reason;


  bool get isVpnDown => reason == 'vpn_down';

  @override
  String toString() => reason;
}


class ChainLayerProbe {
  ChainLayerProbe({CcChannel? cc, BoxVpnClient? vpn})
      : _cc = cc ?? CcChannel.instance,
        _vpn = vpn ?? BoxVpnClient();

  final CcChannel _cc;
  final BoxVpnClient _vpn;

  bool _cancelled = false;



  void cancel() => _cancelled = true;
















  Future<ChainProbeReport> run(
    String chainTag, {
    required List<String> hops,
    String? url,
    int? timeoutMs,
  }) async {
    _cancelled = false;
    final canceller = ProbeLifecycle.I.register(cancel);
    try {
      if (hops.isEmpty) throw const ChainProbeUnavailable('no_positions');

      final vpnUp = (await _vpn.getVpnStatus()) == TunnelStatus.connected;
      if (!vpnUp) throw const ChainProbeUnavailable('vpn_down');

      final opts = await ProbeController.resolvePingOptions(
        overrideUrl: url,
        overrideTimeoutMs: timeoutMs,
      );

      final layers = <ChainLayerResult>[];
      var broken = false;
      for (var i = 0; i < hops.length; i++) {
        final probeTag = chainLayerTag(chainTag, i);





        if (broken || _cancelled) {
          layers.add(ChainLayerResult(
            pos: i,
            tag: hops[i],
            probeTag: probeTag,
            notReached: true,
          ));
          continue;
        }
        final r = await _cc.urlTestOutbound(
          probeTag,
          link: opts.url,
          timeoutMs: opts.timeoutMs,
        );
        if (!r.ok) broken = true;
        layers.add(ChainLayerResult(
          pos: i,
          tag: hops[i],
          probeTag: probeTag,
          cumulativeMs: r.ok ? r.delay : 0,
          error: r.error,
        ));
      }
      return ChainProbeReport(
        chainTag: chainTag,
        layers: layers,
        url: opts.url,
        timeoutMs: opts.timeoutMs,
      );
    } finally {
      ProbeLifecycle.I.deregister(canceller);
    }
  }
}







List<String>? chainHopsFromConfig(Map<String, dynamic>? raw) {
  if (raw == null) return null;
  if (raw['type'] != 'chain') return null;
  final list = raw['outbounds'];
  if (list is! List) return null;
  return [
    for (final h in list)
      if (h is String) h,
  ];
}
