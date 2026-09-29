import 'dart:convert';

import '../services/contract/protocol_level.dart';
import '../services/tag_resolver.dart';











class ConfigNode {
  const ConfigNode({
    required this.tag,
    required this.type,
    required this.kind,
    required this.detour,
    required this.isMarkedDetour,
    required this.detourRefCount,
    required this.raw,
    required this.transportLabel,
    required this.securityLabel,
  });


  final String tag;



  final String type;



  final String kind;



  final String? detour;



  final bool isMarkedDetour;


  final int detourRefCount;


  final Map<String, dynamic> raw;


  bool get isDetour => detourRefCount > 0;






  final String? transportLabel;








  final String? securityLabel;

  static String? _deriveTransport(String type, Map<String, dynamic> raw) {




    if (type == 'masque') {
      final net = raw['vhttp'];
      return (net is String && net.isNotEmpty) ? net : 'h3';
    }
    final tr = raw['transport'];
    if (tr is Map) {
      final t = tr['type'];
      if (t is String && t.isNotEmpty) return t == 'http' ? 'h2' : t;
    }

    if (const {'vless', 'vmess', 'trojan', 'anytls'}.contains(type)) {
      return 'tcp';
    }
    return null;
  }





  static String? _deriveSecurity(String type, Map<String, dynamic> raw) {
    final level = protocolLevelByRegistry(type, raw);
    if (level != null) return level;
    final tls = raw['tls'];
    if (tls is Map && tls['enabled'] == true) {
      final reality = tls['reality'];
      final base =
          (reality is Map && reality['enabled'] == true) ? 'Reality' : 'TLS';


      final flow = raw['flow'];
      return flow is String && flow.startsWith('xtls-rprx-vision')
          ? '$base+Vision'
          : base;
    }
    return null;
  }


  bool get isControl => kControlTypes.contains(type);


  static const kControlTypes = <String>{
    'selector', 'urltest', 'direct', 'block', 'dns',
  };
}









class ParsedConfig {
  const ParsedConfig._(this.byTag);

  const ParsedConfig.empty() : byTag = const <String, ConfigNode>{};

  final Map<String, ConfigNode> byTag;



  factory ParsedConfig.parse(String configRaw) {
    if (configRaw.isEmpty) return const ParsedConfig.empty();
    final byTag = <String, ConfigNode>{};
    final detourTargets = <String, int>{};
    try {
      final cfg = jsonDecode(configRaw) as Map<String, dynamic>;
      final raws = <(Map<String, dynamic>, String)>[
        for (final o in (cfg['outbounds'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>())
          (o, 'outbound'),
        for (final o in (cfg['endpoints'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>())
          (o, 'endpoint'),
      ];

      for (final (o, _) in raws) {
        final d = o['detour'];
        if (d is String && d.isNotEmpty) {
          detourTargets[d] = (detourTargets[d] ?? 0) + 1;
        }
      }


      for (final (o, kind) in raws) {
        final t = o['tag'];
        if (t is! String) continue;
        final d = o['detour'];
        final type = (o['type'] as String?) ?? '';
        byTag[t] = ConfigNode(
          tag: t,
          type: type,
          kind: kind,
          detour: (d is String && d.isNotEmpty) ? d : null,
          isMarkedDetour: TagResolver.isDetourMarker(t),
          detourRefCount: detourTargets[t] ?? 0,
          raw: o,
          transportLabel: ConfigNode._deriveTransport(type, o),
          securityLabel: ConfigNode._deriveSecurity(type, o),
        );
      }
    } catch (_) {

    }
    return ParsedConfig._(byTag);
  }

  ConfigNode? operator [](String tag) => byTag[tag];

  Iterable<ConfigNode> get nodes => byTag.values;

  bool get isEmpty => byTag.isEmpty;


  String kindOf(String tag) => byTag[tag]?.kind ?? 'outbound';


  Map<String, dynamic>? rawOf(String tag) => byTag[tag]?.raw;


  String? detourOf(String tag) => byTag[tag]?.detour;




  String? protocolOf(String tag) {
    final n = byTag[tag];
    return (n != null && !n.isControl && n.type.isNotEmpty) ? n.type : null;
  }



  List<Map<String, dynamic>> outboundChain(String tag) {
    final self = byTag[tag];
    if (self == null) return const [];
    final chain = <Map<String, dynamic>>[self.raw];
    final seen = <String>{tag};
    var cur = self.detour;
    while (cur != null && seen.add(cur)) {
      final next = byTag[cur];
      if (next == null) break;
      chain.add(next.raw);
      cur = next.detour;
    }
    return chain;
  }


  List<String> detourChain(String tag) {
    final chain = <String>[];
    final seen = <String>{tag};
    var cur = byTag[tag]?.detour;
    while (cur != null && seen.add(cur)) {
      chain.add(cur);
      cur = byTag[cur]?.detour;
    }
    return chain;
  }


  int get nodeCount => byTag.values.where((n) => !n.isControl).length;
}
