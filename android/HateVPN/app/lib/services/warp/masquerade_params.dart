









class QuicParams {
  const QuicParams({
    this.sni = '',
    this.ip = 'quic',
    this.ib = 'chrome',
    this.jc = 4,
    this.jmin = 40,
    this.jmax = 70,
  });

  final String sni;
  final String ip;
  final String ib;
  final int jc;
  final int jmin;
  final int jmax;

  QuicParams copyWith({
    String? sni,
    String? ip,
    String? ib,
    int? jc,
    int? jmin,
    int? jmax,
  }) =>
      QuicParams(
        sni: sni ?? this.sni,
        ip: ip ?? this.ip,
        ib: ib ?? this.ib,
        jc: jc ?? this.jc,
        jmin: jmin ?? this.jmin,
        jmax: jmax ?? this.jmax,
      );
}
