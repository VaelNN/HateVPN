














import 'dart:io' show InternetAddress;
import 'dart:math';
import 'dart:typed_data';

class ScanPool {
  const ScanPool({
    required this.wgV4Cidr,
    required this.wgV6Cidr,
    this.wgEndpointsPreset = const [],
    this.wgRecommendedEndpoint = '',
    required this.wgPorts,
    required this.wgPortsExtra,
    required this.wgSniPool,
    required this.utlsFpPool,
    this.wgKeepalive = 0,
    this.masqueHostsPreset = const [],
    this.masqueRecommendedHost = '',
    required this.masqueV4Cidr,
    this.masqueH3HostsExtra = const [],
    this.masqueH2Exclude = const [],
    required this.masquePortsH3,
    required this.masquePortsH2,
    required this.masqueSniPool,
    this.masqueRecommendedSni = '',
    this.apiHosts = const [],
  });


  final List<String> wgV4Cidr;
  final List<String> wgV6Cidr;




  final List<String> wgEndpointsPreset;





  final String wgRecommendedEndpoint;


  final List<int> wgPorts;


  final List<int> wgPortsExtra;





  final List<String> wgSniPool;

  final List<String> utlsFpPool;










  final int wgKeepalive;







  final List<String> masqueHostsPreset;




  final String masqueRecommendedHost;



  final List<String> masqueV4Cidr;




  final List<String> masqueH3HostsExtra;



  final List<String> masqueH2Exclude;




  final List<int> masquePortsH3;
  final List<int> masquePortsH2;




  final List<String> masqueSniPool;



  final String masqueRecommendedSni;





  final List<String> apiHosts;


  List<String> get masqueH3Hosts {
    final seen = <String>{};
    return [
      for (final h in [...masqueHostsPreset, ...masqueH3HostsExtra])
        if (seen.add(h)) h,
    ];
  }



  List<String> masqueHostsFor(String network) =>
      network == 'h3' ? masqueH3Hosts : masqueHostsPreset;






  String? randomMasqueIp(String network, Random rng) {
    if (network == 'h3') {
      final hosts = masqueH3Hosts;
      return hosts.isEmpty ? null : hosts[rng.nextInt(hosts.length)];
    }
    if (masqueV4Cidr.isEmpty) return null;
    try {
      for (var i = 0; i < 16; i++) {
        final cidr = masqueV4Cidr[rng.nextInt(masqueV4Cidr.length)];
        final ip = randomIpInCidr(cidr, rng);
        if (!masqueH2Exclude.contains(ip)) return ip;
      }
    } catch (_) {
      return null;
    }
    return null;
  }



  bool get hasData {
    final wgOk =
        (wgV4Cidr.isNotEmpty || wgV6Cidr.isNotEmpty) && wgPorts.isNotEmpty;
    return wgOk || masqueV4Cidr.isNotEmpty || masqueH3Hosts.isNotEmpty;
  }


  List<int> masquePortsFor(String network) =>
      network == 'h2' ? masquePortsH2 : masquePortsH3;








  static ScanPool? fromFullJson(Map<String, dynamic>? json,
      {String region = ''}) {
    if (json == null) return null;
    if (region.isNotEmpty) json = applyRegion(json, region);
    final wg = (json['wireguard'] as Map?)?.cast<String, dynamic>() ?? const {};
    final mq = (json['masque'] as Map?)?.cast<String, dynamic>() ?? const {};
    final api = (json['api'] as Map?)?.cast<String, dynamic>() ?? const {};

    List<String> strs(Map m, String k) =>
        (m[k] as List?)?.map((e) => e.toString()).toList() ?? const [];
    List<int> ints(Map m, String k) =>
        (m[k] as List?)?.map((e) => (e as num).toInt()).toList() ?? const [];


    int intOr0(Map m, String k) {
      final v = m[k];
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v.trim()) ?? 0;
      return 0;
    }







    final h3 = (mq['h3'] as Map?)?.cast<String, dynamic>() ?? const {};
    final h2 = (mq['h2'] as Map?)?.cast<String, dynamic>() ?? const {};
    final hostsPreset = strs(mq, 'hosts_preset');
    final h2Cidr = h2.containsKey('v4_cidr') ? strs(h2, 'v4_cidr') : strs(mq, 'v4_cidr');
    final List<String> h3Extra;
    if (h3.containsKey('hosts_extra')) {
      h3Extra = strs(h3, 'hosts_extra');
    } else {
      h3Extra = [
        for (final c in strs(mq, 'h3_v4_cidr'))
          if (c.endsWith('/32') && !hostsPreset.contains(c.substring(0, c.length - 3)))
            c.substring(0, c.length - 3),
      ];
    }

    final pool = ScanPool(
      wgV4Cidr: strs(wg, 'v4_cidr'),
      wgV6Cidr: strs(wg, 'v6_cidr'),
      wgEndpointsPreset: strs(wg, 'endpoints_preset'),
      wgRecommendedEndpoint: (wg['recommended_endpoint'] as String?) ?? '',
      wgPorts: ints(wg, 'ports'),
      wgPortsExtra: ints(wg, 'ports_extra'),
      wgSniPool: strs(wg, 'sni_pool'),
      utlsFpPool: strs(wg, 'utls_fp_pool'),
      wgKeepalive: intOr0(wg, 'keepalive'),
      masqueHostsPreset: hostsPreset,
      masqueRecommendedHost: (mq['recommended_host'] as String?) ?? '',
      masqueV4Cidr: h2Cidr,
      masqueH3HostsExtra: h3Extra,
      masqueH2Exclude: strs(h2, 'exclude'),
      masquePortsH3: h3.containsKey('ports') ? ints(h3, 'ports') : ints(mq, 'ports_h3'),
      masquePortsH2: h2.containsKey('ports') ? ints(h2, 'ports') : ints(mq, 'ports_h2'),
      masqueSniPool: strs(mq, 'sni_pool'),
      masqueRecommendedSni: (mq['recommended_sni'] as String?) ?? '',


      apiHosts: strs(api, 'hosts')
          .map((h) => h.trim().replaceAll(RegExp(r'/+$'), ''))
          .where((h) => h.isNotEmpty)
          .toList(),
    );
    return pool.hasData ? pool : null;
  }


  static const locKey = 'loc';



  static List<String> regionsOf(Map<String, dynamic>? json) {
    final loc = json?[locKey];
    if (loc is! Map) return const [];
    return [
      for (final e in loc.entries)
        if (e.value is Map) e.key.toLowerCase(),
    ];
  }








  static Map<String, dynamic> applyRegion(
      Map<String, dynamic> json, String region) {
    final loc = json[locKey];
    final base = Map<String, dynamic>.from(json)..remove(locKey);
    if (loc is! Map) return base;


    Map<String, dynamic>? section(Object? v) =>
        v is Map ? v.cast<String, dynamic>() : null;
    var sec = section(loc[region.toLowerCase()]);
    final alias = sec?['alias'];
    if (alias is String) sec = section(loc[alias.toLowerCase()]);
    if (sec == null) return base;
    return deepMerge(base, sec);
  }



  static Map<String, dynamic> deepMerge(
      Map<String, dynamic> base, Map<String, dynamic> over) {
    final out = Map<String, dynamic>.from(base);
    for (final e in over.entries) {
      final b = out[e.key];
      final o = e.value;
      if (b is Map && o is Map) {
        out[e.key] = deepMerge(
            b.cast<String, dynamic>(), o.cast<String, dynamic>());
      } else {
        out[e.key] = o;
      }
    }
    return out;
  }
}




String randomIpInCidr(String cidr, Random rng) {
  final slash = cidr.indexOf('/');
  if (slash < 0) throw FormatException('not a CIDR: $cidr');
  final base = InternetAddress(cidr.substring(0, slash));
  final mask = int.parse(cidr.substring(slash + 1));
  final bytes = base.rawAddress;
  final totalBits = bytes.length * 8;
  if (mask < 0 || mask > totalBits) throw FormatException('bad mask: $cidr');
  final hostBits = totalBits - mask;


  var value = BigInt.zero;
  for (final b in bytes) {
    value = (value << 8) | BigInt.from(b);
  }
  final full = (BigInt.one << totalBits) - BigInt.one;
  final hostMask =
      hostBits == 0 ? BigInt.zero : (BigInt.one << hostBits) - BigInt.one;
  final network = value & (full ^ hostMask);
  final offset = _randomBigInt(hostBits, rng) & hostMask;
  final result = network | offset;


  final out = Uint8List(bytes.length);
  var v = result;
  for (var i = bytes.length - 1; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v = v >> 8;
  }
  return InternetAddress.fromRawAddress(out).address;
}



BigInt _randomBigInt(int bits, Random rng) {
  var v = BigInt.zero;
  var remaining = bits;
  while (remaining > 0) {
    final take = remaining >= 8 ? 8 : remaining;
    final r = rng.nextInt(1 << take);
    v = (v << take) | BigInt.from(r);
    remaining -= take;
  }
  return v;
}
