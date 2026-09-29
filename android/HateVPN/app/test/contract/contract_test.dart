import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../contract_paths.dart';
import 'package:lxbox/models/node_spec.dart';
import 'package:lxbox/models/singbox_entry.dart';
import 'package:lxbox/models/template_vars.dart';
import 'package:lxbox/services/contract/registry.dart';
import 'package:lxbox/services/parser/uri_parsers.dart';

import 'corpus_warnings.dart';

































const _endpointSchemes = {'wireguard', 'tailscale'};



const _thisSide = 'lxbox';









Set<String> _foreignExtensionSchemes() {
  final dir = Directory('$kRegistryRoot/registry/protocols');
  if (!dir.existsSync()) return const {};
  final out = <String>{};
  for (final f in dir.listSync().whereType<File>()) {
    if (!f.path.endsWith('.json')) continue;
    final data = json.decode(f.readAsStringSync()) as Map<String, dynamic>;
    final ext = data['extension'];
    if (ext is String && ext.isNotEmpty && ext != _thisSide) {
      out.add(data['scheme'] as String? ??
          f.uri.pathSegments.last.replaceFirst('.json', ''));
    }
  }
  return out;
}








const _canonScheme = <String, String>{
  'shadowsocks': 'ss',
};





















String _envelopeScheme(NodeSpec spec) {
  if (spec is SocksSpec && spec.version != '5') {
    return spec.toUri().split('://').first;
  }
  return _canonScheme[spec.protocol] ?? spec.protocol;
}










String? _readCorpusUri(File file) {
  final lines = file.readAsLinesSync();
  String? uri;
  for (final raw in lines) {
    final trimmed = raw.trimRight();
    if (trimmed.isEmpty) continue;
    if (trimmed.trimLeft().startsWith('#')) continue;
    uri = trimmed;
  }
  return uri;
}


Map<String, dynamic> _canonNode(NodeSpec spec) {
  final entry = _canonEntryMap(spec);

  final kind = spec.isGroup
      ? 'group'
      : (_endpointSchemes.contains(spec.protocol) ? 'endpoint' : 'outbound');

  final node = <String, dynamic>{
    'kind': kind,
    'scheme': _envelopeScheme(spec),
    if (spec.label.isNotEmpty) 'label': spec.label,
    'entry': entry,
  };

  if (spec.chained != null) {
    node['chain'] = [_canonNode(spec.chained!)];
  }





  final warnings = warningListOf(
      spec.warnings, _canonScheme[spec.protocol] ?? spec.protocol);
  if (warnings.isNotEmpty) node['warnings'] = warnings;

  return node;
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




Map<String, dynamic> _buildEnvelope({
  List<Map<String, dynamic>> nodes = const [],
  List<Map<String, dynamic>> dropped = const [],
}) {
  return {
    'v': 1,
    'nodes': nodes,
    if (dropped.isNotEmpty) 'dropped': dropped,
  };
}






bool _equalCanon(Map<String, dynamic> a, Map<String, dynamic> b) {
  final got = deepCopyEnvelope(a) as Map<String, dynamic>;
  final want = deepCopyEnvelope(b) as Map<String, dynamic>;
  normalizeWarnings(got, want);
  normalizeDrops(got, want);
  return canonEncode(got) == canonEncode(want);
}

void main() {
  if (corpusSuiteUnavailable('test/contract/contract_test.dart')) return;




  final updateGolden = Platform.environment['UPDATE_CONTRACT'] == '1';

  final root = Directory('$kVendorRoot/corpus/uri');

  final cases = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.uri'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  if (cases.isEmpty) {
    test('корпус контракта пуст', () {}, skip: 'нет .uri файлов в $root');
    return;
  }

  final foreign = _foreignExtensionSchemes();

  group('Contract corpus (URI)', () {





    setUpAll(() async {
      if (Directory('$kRegistryRoot/registry').existsSync()) {
        await ContractRegistry.I.loadFromDirectory(kRegistryRoot);
      }
    });

    for (final file in cases) {
      final rel = file.path
          .substring(root.path.length)
          .replaceFirst(RegExp(r'^[/\\]'), '')
          .replaceAll(r'\', '/');
      final name = rel.substring(0, rel.length - '.uri'.length);
      final scheme = rel.split('/').first;
      final basePath = file.path.substring(0, file.path.length - '.uri'.length);
      final baseExpectedPath = '$basePath.expected.json';
      final overridePath = '$basePath.expected.lxbox.json';

      test(name, () {
        if (foreign.contains(scheme)) {


          markTestSkipped('$scheme — extension чужой стороны, парсера нет');
          return;
        }

        final uri = _readCorpusUri(file);
        if (uri == null) {
          fail('$rel: не найдена строка с URI');
        }

        Map<String, dynamic> envelope;
        NodeSpec? spec;




        final verdict = XrayDropVerdict();
        try {
          spec = parseUri(uri, dropped: verdict);
        } catch (_) {
          spec = null;
        }

        if (spec == null) {





          envelope = _buildEnvelope(dropped: [
            {
              'ref': uri,
              'index': 0,
              'reason': 'parse_error',
              if (verdict.reason != null) 'code': verdict.reason!.code,
            },
          ]);
        } else {
          envelope = _buildEnvelope(nodes: [_canonNode(spec)]);
        }

        final overrideFile = File(overridePath);
        final baseFile = File(baseExpectedPath);

        if (updateGolden) {




          if (overrideFile.existsSync()) {
            overrideFile.writeAsStringSync(prettyPrintEnvelope(envelope));
          } else if (baseFile.existsSync()) {
            final base = json.decode(baseFile.readAsStringSync())
                as Map<String, dynamic>;
            if (!_equalCanon(envelope, base)) {
              overrideFile.writeAsStringSync(prettyPrintEnvelope(envelope));
            }
          } else {
            overrideFile.writeAsStringSync(prettyPrintEnvelope(envelope));
          }
          return;
        }




        final expectedFile =
            overrideFile.existsSync() ? overrideFile : baseFile;

        if (!expectedFile.existsSync()) {
          fail('$rel: нет ни ${baseFile.uri.pathSegments.last}, ни '
              'per-app override — кейс без ожидания не проверяет ничего');
        }

        final want = json.decode(expectedFile.readAsStringSync())
            as Map<String, dynamic>;
        if (!_equalCanon(envelope, want)) {
          fail(
            'расхождение с контрактом\n'
            '--- got ---\n${prettyPrintEnvelope(envelope)}'
            '--- want ---\n${prettyPrintEnvelope(want)}',
          );
        }
      });
    }
  });
}
