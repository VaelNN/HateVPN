import 'dart:convert';

import '../../config/consts.dart' show kDirectOutboundTag;
import '../../models/node_spec.dart';
import '../../models/node_warning.dart';
import '../../models/singbox_entry.dart';
import '../builder/detour_yields.dart' show yieldToBuildDetour;
import '../builder/registry_gate.dart';













class ProbeConfig {
  const ProbeConfig({
    required this.configJson,
    required this.tagByIndex,
    required this.brokenByIndex,
  });


  final String? configJson;


  final Map<int, String> tagByIndex;





  final Map<int, String> brokenByIndex;
}


const kProbeDnsTag = 'local-dns';



















const kProbeMaxNaivePerConfig = 1;





const _naiveOutboundType = 'naive';


























const kProbeMaxWireguardPerConfig = 4;







const _wireguardEndpointType = 'wireguard';







ProbeConfig buildProbeConfig(
  List<NodeSpec?> nodes, {
  String coreVersion = '',
}) =>
    buildProbeBatches(nodes, coreVersion: coreVersion).firstOrNull ??
    ProbeConfig(
      configJson: null,
      tagByIndex: const {},
      brokenByIndex: _brokenOf(nodes, coreVersion),
    );
















List<ProbeConfig> buildProbeBatches(
  List<NodeSpec?> nodes, {
  String coreVersion = '',
}) {
  final built = <int, _Built>{};
  final broken = <int, String>{};
  for (var i = 0; i < nodes.length; i++) {
    final e = _buildOne(nodes[i], coreVersion);
    if (e is String) {
      broken[i] = e;
    } else {
      built[i] = e as _Built;
    }
  }
  if (built.isEmpty) return const [];





  final groups = <List<int>>[];
  final plain = <int>[];
  final costly = <int>[];
  for (final i in built.keys) {
    final b = built[i]!;
    ((b.naiveCount > 0 || b.wireguardCount > 0) ? costly : plain).add(i);
  }
  var naiveInCurrent = 0;
  var wireguardInCurrent = 0;
  for (final i in costly) {
    final b = built[i]!;
    final overflow = naiveInCurrent + b.naiveCount > kProbeMaxNaivePerConfig ||
        wireguardInCurrent + b.wireguardCount > kProbeMaxWireguardPerConfig;
    if (groups.isEmpty || overflow) {
      groups.add(<int>[]);
      naiveInCurrent = 0;
      wireguardInCurrent = 0;
    }
    groups.last.add(i);
    naiveInCurrent += b.naiveCount;
    wireguardInCurrent += b.wireguardCount;
  }
  if (plain.isNotEmpty) {


    if (groups.isEmpty) {
      groups.add(plain);
    } else {
      groups.first.insertAll(0, plain);
    }
  }




  for (final g in groups) {
    g.sort();
  }

  return [
    for (var g = 0; g < groups.length; g++)
      _assemble(groups[g], built, brokenByIndex: g == 0 ? broken : const {}),
  ];
}

Map<int, String> _brokenOf(List<NodeSpec?> nodes, String coreVersion) {
  final broken = <int, String>{};
  for (var i = 0; i < nodes.length; i++) {
    final e = _buildOne(nodes[i], coreVersion);
    if (e is String) broken[i] = e;
  }
  return broken;
}


class _Built {
  _Built(
    this.entries,
    this.mainIndexInEntries,
    this.detourCount,
    this.naiveCount,
    this.wireguardCount,
  );

  final List<SingboxEntry> entries;
  final int mainIndexInEntries;
  final int detourCount;


  final int naiveCount;




  final int wireguardCount;
}


Object _buildOne(NodeSpec? node, String coreVersion) {
  if (node == null) return 'broken';




  if (node.isGroup) return 'group';



  if (node is TailscaleSpec) return 'no-address';
  try {
    final raw = node.getEntries(null);

    final entries = <SingboxEntry>[...raw.detours, raw.main];













    final gate = applyRegistryGate(entries, coreVersion: coreVersion);
    if (gate.dropped.isNotEmpty) return 'invalid: ${_dropReason(gate)}';
    var naive = 0;
    var wireguard = 0;
    for (final e in entries) {




      if (e.map['type'] == _naiveOutboundType) {
        naive++;
        e.map.remove('insecure_concurrency');
      }



      if (e is Endpoint && e.map['type'] == _wireguardEndpointType) {
        wireguard++;
      }
    }
    return _Built(
      entries,
      entries.length - 1,
      raw.detours.length,
      naive,
      wireguard,
    );
  } catch (e) {
    return 'invalid: $e';
  }
}



String _dropReason(RegistryGateReport gate) {
  final d = gate.dropped.first;
  final codes = <String>{
    for (final w in (gate.warningsByEmittedTag[d.tag] ?? const <NodeWarning>[])
        .whereType<RegistryWarning>())
      w.code,
  };
  if (codes.isNotEmpty) return '${d.tag}: ${codes.join(', ')}';
  return gate.warnings.firstOrNull ?? '${d.tag}: dropped by registry';
}

ProbeConfig _assemble(
  List<int> indexes,
  Map<int, _Built> built, {
  required Map<int, String> brokenByIndex,
}) {
  final outbounds = <Map<String, dynamic>>[
    {'type': 'direct', 'tag': kDirectOutboundTag},
  ];
  final endpoints = <Map<String, dynamic>>[];
  final tagByIndex = <int, String>{};
  final usedTags = <String>{kDirectOutboundTag, kProbeDnsTag};

  String allocate(String base) {
    final b = base.isEmpty ? 'node' : base;
    if (usedTags.add(b)) return b;
    for (var i = 2;; i++) {
      final candidate = '$b-$i';
      if (usedTags.add(candidate)) return candidate;
    }
  }

  for (final i in indexes) {
    final b = built[i]!;

    for (var k = 0; k < b.detourCount; k++) {
      b.entries[k].map['tag'] = allocate(b.entries[k].tag);
    }
    final main = b.entries[b.mainIndexInEntries];
    final mainTag = allocate(main.tag);
    main.map['tag'] = mainTag;
    if (b.detourCount > 0) {
      main.map['detour'] = b.entries[0].tag;



      yieldToBuildDetour(main.map);
    }
    for (final e in b.entries) {
      switch (e) {
        case Outbound():
          outbounds.add(e.map);
        case Endpoint():
          endpoints.add(e.map);
      }
    }
    tagByIndex[i] = mainTag;
  }

  if (tagByIndex.isEmpty) {
    return ProbeConfig(
      configJson: null,
      tagByIndex: tagByIndex,
      brokenByIndex: brokenByIndex,
    );
  }

  final config = <String, dynamic>{
    'log': {'level': 'error'},
    'dns': {
      'servers': [
        {'type': 'local', 'tag': kProbeDnsTag},
      ],
    },
    'outbounds': outbounds,
    if (endpoints.isNotEmpty) 'endpoints': endpoints,
    'route': {

      'default_domain_resolver': kProbeDnsTag,
    },
  };
  return ProbeConfig(
    configJson: jsonEncode(config),
    tagByIndex: tagByIndex,
    brokenByIndex: brokenByIndex,
  );
}




String buildScanProbeConfigJson() => jsonEncode(<String, dynamic>{
      'log': {'level': 'error'},
      'dns': {
        'servers': [
          {'type': 'local', 'tag': kProbeDnsTag},
        ],
      },
      'outbounds': [
        {'type': 'direct', 'tag': kDirectOutboundTag},
      ],
      'route': {'default_domain_resolver': kProbeDnsTag},
    });

