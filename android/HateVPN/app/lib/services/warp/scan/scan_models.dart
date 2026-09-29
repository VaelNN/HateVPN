










enum ScanProtocol {
  awg,
  masqueH3,
  masqueH2;

  bool get isMasque =>
      this == ScanProtocol.masqueH3 || this == ScanProtocol.masqueH2;
}




class AwgParams {
  const AwgParams({
    required this.ip,
    required this.jc,
    required this.jmin,
    required this.jmax,
  });

  final String ip;
  final int jc;
  final int jmin;
  final int jmax;
}





class ScanCandidate {
  const ScanCandidate({
    required this.ip,
    required this.port,
    required this.protocol,
    required this.sni,
    this.awgParams,
  });

  final String ip;
  final int port;
  final ScanProtocol protocol;
  final String sni;
  final AwgParams? awgParams;

  ScanCandidate copyWith({ScanProtocol? protocol, String? sni}) => ScanCandidate(
        ip: ip,
        port: port,
        protocol: protocol ?? this.protocol,
        sni: sni ?? this.sni,
        awgParams: awgParams,
      );


  String get endpoint => ip.contains(':') ? '[$ip]:$port' : '$ip:$port';





  String get nodeTitle => switch (protocol) {
        ScanProtocol.awg => '🔥⛈️ WARP AWG '
            '(${awgParams?.ip ?? 'quic'}${sni.isEmpty ? '' : ' $sni'})',
        ScanProtocol.masqueH3 =>
          '🔥🎭 WARP MASQUE (h3${sni.isEmpty ? '' : ': $sni'})',
        ScanProtocol.masqueH2 =>
          '🔥🎭 WARP MASQUE (h2${sni.isEmpty ? '' : ': $sni'})',
      };
}
