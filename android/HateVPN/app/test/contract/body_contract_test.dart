import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../contract_paths.dart';
import 'package:lxbox/models/node_spec.dart';
import 'package:lxbox/models/node_warning.dart';
import 'package:lxbox/models/singbox_entry.dart';
import 'package:lxbox/models/template_vars.dart';
import 'package:lxbox/services/contract/registry.dart';
import 'package:lxbox/services/contract/warning_codes.dart';
import 'package:lxbox/services/parser/body_decoder.dart';
import 'package:lxbox/services/parser/parse_all.dart';

import 'corpus_warnings.dart';



























const _thisSide = 'lxbox';





String _readCorpusBody(File file) {
  final lines = file.readAsLinesSync();
  var start = 0;
  while (start < lines.length && lines[start].trimLeft().startsWith('#')) {
    start++;
  }
  return lines.sublist(start).join('\n');
}











String _canonScheme(String protocol) {
  if (_genusValues().contains(protocol)) return 'group';
  return switch (protocol) {
    'shadowsocks' => 'ss',
    _ => protocol,
  };
}

Set<String> _genusValues() {
  for (final name in ContractRegistry.I.protocolNames) {
    final proto = ContractRegistry.I.rawProtocol(name);
    final genus = (proto?['genus'] as Map?)?.cast<String, dynamic>();
    final values = (genus?['values'] as List?)?.whereType<String>();
    if (values != null && values.isNotEmpty) return values.toSet();
  }
  return const <String>{};
}


String _nodeSignature(NodeSpec spec) {
  final SingboxEntry raw = spec.emit(TemplateVars.empty);
  final map = raw.map;
  final server = map['server'] ?? _wgPeerServer(map) ?? '';
  final port = map['server_port'] ?? _wgPeerPort(map) ?? 0;
  return '${_canonScheme(spec.protocol)}|$server|$port';
}




Map<String, dynamic> _canonEntryMap(NodeSpec spec) {
  final SingboxEntry raw = spec.emit(TemplateVars.empty);
  final copy = Map<String, dynamic>.from(raw.map);
  copy.remove('tag');
  copy.remove('detour');
  return _canonValue(copy) as Map<String, dynamic>;
}



Object? _canonValue(Object? v) {
  if (v is Map) {
    final out = <String, dynamic>{};
    v.forEach((k, val) => out[k as String] = _canonValue(val));
    return out;
  }
  if (v is List) {
    return [for (final val in v) _canonValue(val)];
  }
  return v;
}


Object? _wgPeerServer(Map<String, dynamic> map) {
  final peers = map['peers'];
  if (peers is List && peers.isNotEmpty && peers.first is Map) {
    return (peers.first as Map)['address'];
  }
  return null;
}

Object? _wgPeerPort(Map<String, dynamic> map) {
  final peers = map['peers'];
  if (peers is List && peers.isNotEmpty && peers.first is Map) {
    return (peers.first as Map)['port'];
  }
  return null;
}


List<String> _expectedSignatures(Map<String, dynamic> data) {
  final nodes = (data['nodes'] as List?) ?? const [];
  final out = <String>[];
  for (final n in nodes) {
    final node = n as Map<String, dynamic>;
    final entry = (node['entry'] as Map?)?.cast<String, dynamic>() ?? {};
    final server = entry['server'] ?? _wgPeerServer(entry) ?? '';
    final port = entry['server_port'] ?? _wgPeerPort(entry) ?? 0;
    out.add('${node['scheme']}|$server|$port');
  }
  return out;
}







List<String> _expectedDropped(Map<String, dynamic> data) {
  final out = <String>[];
  for (final d in (data['dropped'] as List?) ?? const []) {
    final rec = (d as Map).cast<String, dynamic>();
    final code = rec['code'];
    out.add(code == null ? '${rec['ref']}' : '${rec['ref']}|$code');
  }
  return out..sort();
}






String _droppedRef(NodeWarning w) => switch (w) {
      DialerProxyUnusableWarning(:final ownerTag, :final label) =>
        ownerTag.isNotEmpty ? ownerTag : label,


      RegistryWarning(:final ownerTag) when ownerTag.isNotEmpty => ownerTag,
      _ => w.runtimeType.toString(),
    };


List<String> _chainLabels(NodeSpec spec) {
  final out = <String>[];
  for (var hop = spec.chained; hop != null; hop = hop.chained) {
    out.add(hop.label);
  }
  return out;
}

List<String> _expectedChainLabels(Map<String, dynamic> node) {
  final out = <String>[];
  var chain = node['chain'];
  while (chain is List && chain.isNotEmpty) {
    final hop = (chain.first as Map).cast<String, dynamic>();
    out.add('${hop['label'] ?? ''}');
    chain = hop['chain'];
  }
  return out;
}














const Map<String, String> _pendingWarningNodes = {};

void main() {
  if (corpusSuiteUnavailable('test/contract/body_contract_test.dart')) return;

  final root = Directory('$kVendorRoot/corpus/body');

  final cases = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.body'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  group('contract corpus: subscription bodies', () {
    setUpAll(() async {
      if (Directory('$kRegistryRoot/registry').existsSync()) {
        await ContractRegistry.I.loadFromDirectory(kRegistryRoot);
      }
    });

    for (final file in cases) {
      final name = file.path.substring(root.path.length + 1);
      final base = file.path.substring(0, file.path.length - '.body'.length);
      test(name, () {



        final overrideFile = File('$base.expected.lxbox.json');
        final baseFile = File('$base.expected.json');
        final expectedFile =
            overrideFile.existsSync() ? overrideFile : baseFile;
        if (!expectedFile.existsSync()) {
          markTestSkipped('нет ожиданий лаунчера: ${baseFile.path}');
          return;
        }

        final expected =
            jsonDecode(expectedFile.readAsStringSync()) as Map<String, dynamic>;





        final ext = (expected['meta'] as Map?)?['extension'];
        if (ext is String && ext.isNotEmpty && ext != _thisSide) {
          markTestSkipped('meta.extension=$ext — схемы у LxBox нет');
          return;
        }

        final decoded = decode(_readCorpusBody(file));
        final dropped = <NodeWarning>[];
        final specs = parseAll(decoded, dropped: dropped);

        final got = specs.map(_nodeSignature).toList()..sort();
        final want = _expectedSignatures(expected)..sort();
        expect(got, want,
            reason: 'состав узлов тела разошёлся с лаунчером\n'
                '  получено: $got\n  ожидалось: $want');





        final gotBySig = <String, List<String>>{};
        for (final spec in specs) {
          (gotBySig[_nodeSignature(spec)] ??= [])
              .add(canonEncode(_canonEntryMap(spec)));
        }
        final wantBySig = <String, List<String>>{};
        for (final wantNode
            in ((expected['nodes'] as List?) ?? const [])
                .cast<Map<String, dynamic>>()) {
          final entry =
              (wantNode['entry'] as Map?)?.cast<String, dynamic>() ?? {};
          final srv = entry['server'] ?? _wgPeerServer(entry) ?? '';
          final prt = entry['server_port'] ?? _wgPeerPort(entry) ?? 0;
          final sig = '${wantNode['scheme']}|$srv|$prt';
          (wantBySig[sig] ??= []).add(canonEncode(_canonValue(entry)));
        }
        for (final sig in wantBySig.keys) {
          final g = (gotBySig[sig] ?? const <String>[]).toList()..sort();
          final w = wantBySig[sig]!.toList()..sort();
          if (canonEncode(g) != canonEncode(w)) {
            fail('тело узла $sig разошлось с контрактом\n'
                '--- got ---\n${g.join('\n')}\n'
                '--- want ---\n${w.join('\n')}');
          }
        }



        final wantDropped = _expectedDropped(expected);
        final gotDropped = <String>[];
        for (final w in dropped) {
          final code = warningCodeOf(w);
          final ref = _droppedRef(w);
          gotDropped.add(
              wantDropped.any((e) => e == ref) ? ref : '$ref|${code ?? ''}');
        }
        gotDropped.sort();
        expect(gotDropped, wantDropped,
            reason: 'отбраковка (ref/code) разошлась с контрактом');




        final wantNodes =
            ((expected['nodes'] as List?) ?? const []).cast<Map<String, dynamic>>();
        for (final wantNode in wantNodes) {
          final wantChain = _expectedChainLabels(wantNode);
          if (wantChain.isEmpty) continue;
          final entry = (wantNode['entry'] as Map?)?.cast<String, dynamic>() ?? {};
          final sig =
              '${wantNode['scheme']}|${entry['server'] ?? ''}|${entry['server_port'] ?? 0}';
          final spec = specs.firstWhere((s) => _nodeSignature(s) == sig,
              orElse: () => throw StateError('узел $sig не найден'));
          expect(_chainLabels(spec), wantChain,
              reason: 'канон хопа: label звеньев обязан быть сырым тегом '
                  'релея (D-085), без маркера ⚙');
        }






        final sigSeen = <String, int>{};
        for (final wantNode in wantNodes) {
          final scheme = '${wantNode['scheme']}';
          final entry =
              (wantNode['entry'] as Map?)?.cast<String, dynamic>() ?? {};
          final srv = entry['server'] ?? _wgPeerServer(entry) ?? '';
          final prt = entry['server_port'] ?? _wgPeerPort(entry) ?? 0;
          final sig = '$scheme|$srv|$prt';
          final pending = _pendingWarningNodes['$name|$sig'];
          if (pending != null) {
            markTestSkipped('warnings[] узла $sig: $pending');
            continue;
          }
          final matched = specs.where((s) => _nodeSignature(s) == sig).toList();
          if (matched.isEmpty) continue;
          final nth = sigSeen[sig] = (sigSeen[sig] ?? -1) + 1;
          final spec0 = nth < matched.length ? matched[nth] : matched.first;








          final gotW = warningListOf(spec0.warnings, scheme);
          final gotNode = <String, dynamic>{
            if (gotW.isNotEmpty) 'warnings': gotW,
          };
          final want = deepCopyEnvelope(wantNode) as Map<String, dynamic>;
          normalizeNodeWarnings(gotNode, want);
          normalizeNodeWarnings(want, null);
          final g = canonEncode(gotNode['warnings'] ?? const []);
          final w = canonEncode(want['warnings'] ?? const []);
          if (g != w) {
            fail('warnings[] узла $sig разошлись с контрактом\n'
                '--- got ---\n$g\n--- want ---\n$w');
          }
        }
      });
    }
  });
}
