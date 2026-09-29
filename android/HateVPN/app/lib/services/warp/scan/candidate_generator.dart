



import 'dart:math';

import 'scan_models.dart';
import 'scan_pool.dart';

class CandidateGenerator {
  CandidateGenerator(
    this._pool, {
    Random? rng,
    double empiricalPortRatio = 0.3,


    bool allowV6 = false,
  })  : _rng = rng ?? Random.secure(),
        _empiricalRatio = empiricalPortRatio,
        _allowV6 = allowV6;

  final ScanPool _pool;
  final Random _rng;
  final bool _allowV6;


  final double _empiricalRatio;


  List<ScanCandidate> seed(int n) => List.generate(n, (_) => _one());

  ScanCandidate _one() {
    final proto = _pickProtocol();
    return proto == ScanProtocol.awg
        ? _wgCandidate(proto)
        : _masqueCandidate(proto);
  }



  static const _awgIpModes = ['quic', 'quic', 'quic', 'dns', 'stun'];

  ScanCandidate _wgCandidate(ScanProtocol proto) {
    final useV6 = _allowV6 && _pool.wgV6Cidr.isNotEmpty && _rng.nextBool();
    final cidr = _pick(useV6 ? _pool.wgV6Cidr : _pool.wgV4Cidr);
    return ScanCandidate(
      ip: randomIpInCidr(cidr, _rng),
      port: _pickWgPort(),
      protocol: proto,
      sni: _pool.wgSniPool.isEmpty ? '' : _pick(_pool.wgSniPool),
      awgParams: _randomAwg(),
    );
  }




  AwgParams _randomAwg() => AwgParams(
        ip: _pick(_awgIpModes),
        jc: 4,
        jmin: 40,
        jmax: 70,
      );

  ScanCandidate _masqueCandidate(ScanProtocol proto) {




    final net = proto == ScanProtocol.masqueH2 ? 'h2' : 'h3';
    return ScanCandidate(
      ip: _pool.randomMasqueIp(net, _rng) ?? '',
      port: _pickMasquePort(proto),
      protocol: proto,
      sni: _pool.masqueSniPool.isEmpty ? '' : _pick(_pool.masqueSniPool),
    );
  }




  int _pickMasquePort(ScanProtocol proto) {
    final ports = proto == ScanProtocol.masqueH2
        ? _pool.masquePortsH2
        : _pool.masquePortsH3;
    return ports.isEmpty ? 443 : _pick(ports);
  }



  ScanProtocol _pickProtocol() {
    final opts = _protocols();
    return opts[_rng.nextInt(opts.length)];
  }

  List<ScanProtocol> _protocols() => <ScanProtocol>[


        if ((_pool.wgV4Cidr.isNotEmpty || _pool.wgV6Cidr.isNotEmpty) &&
            _pool.wgPorts.isNotEmpty)
          ScanProtocol.awg,


        if (_pool.masqueH3Hosts.isNotEmpty) ScanProtocol.masqueH3,
        if (_pool.masqueV4Cidr.isNotEmpty) ScanProtocol.masqueH2,
      ];

  int _pickWgPort() {
    final useExtra = _pool.wgPortsExtra.isNotEmpty &&
        _rng.nextDouble() < _empiricalRatio;
    final ports = useExtra ? _pool.wgPortsExtra : _pool.wgPorts;
    return _pick(ports);
  }

  T _pick<T>(List<T> xs) => xs[_rng.nextInt(xs.length)];




  List<ScanCandidate> variations(String ip, {int limit = 12}) {
    final protos = _protocols();
    if (protos.isEmpty) return const [];
    final out = <ScanCandidate>[];
    for (final p in protos) {
      out.add(_variationOne(ip, p));
    }
    while (out.length < limit) {
      out.add(_variationOne(ip, protos[_rng.nextInt(protos.length)]));
    }
    return out.take(limit).toList();
  }

  ScanCandidate _variationOne(String ip, ScanProtocol p) {
    final isWg = p == ScanProtocol.awg;
    final sniPool = isWg ? _pool.wgSniPool : _pool.masqueSniPool;
    return ScanCandidate(
      ip: ip,
      port: isWg ? _pickWgPort() : _pickMasquePort(p),
      protocol: p,
      sni: sniPool.isEmpty ? '' : _pick(sniPool),
      awgParams: isWg ? _randomAwg() : null,
    );
  }
}
