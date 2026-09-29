


















const Duration kDnsHealthWindow = Duration(seconds: 30);


const double kDnsHealthFailRatio = 0.20;


const int kDnsHealthMinFails = 3;


enum DnsHealthEventKind {
  dnsResolve,
  dnsFail,
  connActivity,
  other,
}


class DnsHealthSample {
  const DnsHealthSample({required this.kind, required this.ageMs});
  final DnsHealthEventKind kind;
  final int ageMs;
}


class DnsHealthStats {
  int _dnsTotal = 0;
  int _dnsFailed = 0;
  bool _connActivity = false;

  int get dnsTotal => _dnsTotal;
  int get dnsFailed => _dnsFailed;
  double get failRatio => _dnsTotal > 0 ? _dnsFailed / _dnsTotal : 0.0;
  bool get hasConnActivity => _connActivity;

  void add(DnsHealthSample s) {
    if (s.ageMs > kDnsHealthWindow.inMilliseconds) return;
    switch (s.kind) {
      case DnsHealthEventKind.dnsResolve:
        _dnsTotal++;
      case DnsHealthEventKind.dnsFail:
        _dnsTotal++;
        _dnsFailed++;
      case DnsHealthEventKind.connActivity:
        _connActivity = true;
      case DnsHealthEventKind.other:
        break;
    }
  }


  bool get unhealthy =>
      _connActivity &&
      _dnsFailed >= kDnsHealthMinFails &&
      failRatio >= kDnsHealthFailRatio;
}


bool evaluateDnsUnhealthy(Iterable<DnsHealthSample> samples) {
  final stats = DnsHealthStats();
  for (final s in samples) {
    stats.add(s);
  }
  return stats.unhealthy;
}
