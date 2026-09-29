import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/services/contract/registry.dart';
import 'package:lxbox/services/parser/engine/section_loader.dart';

import '../contract_paths.dart';












Map<String, dynamic> _merge(Map<String, dynamic> b, Map<String, dynamic> o) =>
    MapperSections.mergeOverlayForTest(b, o);


Map<String, dynamic> _mergeOld(
  Map<String, dynamic> base,
  Map<String, dynamic> overlay,
) {
  final out = {...base};
  for (final e in overlay.entries) {
    final ov = e.value;
    final b = out[e.key];
    if (ov is Map && b is Map && !ov.containsKey('source')) {
      out[e.key] = {...b.cast<String, dynamic>(), ...ov.cast<String, dynamic>()};
    } else {
      out[e.key] = ov;
    }
  }
  return out;
}

Map<String, dynamic>? _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : null;

void main() {
  setUpAll(loadTestRegistry);

  test('m3: запись оверлея без source замещает запись реестра целиком', () {
    final base = {
      'a': {
        'source': ['query.a'],
        'maps_to': 'a',
        'implies': {'b': true},
      },
    };
    final overlay = {
      'a': {
        'sets': {'x': 1},
      },
    };
    expect(_merge(base, overlay)['a'], {
      'sets': {'x': 1},
    });
  });

  test('группа по-прежнему сливается поимённо', () {
    final base = {
      'ws': {
        'path': {'source': ['query.path'], 'maps_to': 'transport.path'},
        'host': {'source': ['query.host'], 'maps_to': 'transport.headers.Host'},
      },
    };
    final overlay = {
      'ws': {
        'path': {'source': ['query.p'], 'maps_to': 'transport.path'},
      },
    };
    final ws = _merge(base, overlay)['ws'] as Map;
    expect(ws.keys, containsAll(['path', 'host']));
    expect((ws['path'] as Map)['source'], ['query.p']);
  });

  test('снимок: все оверлеи contract_draft сливаются как до правки', () {
    final pairs = <(String, Map<String, dynamic>, Map<String, dynamic>)>[];
    for (final kind in const ['uri', 'xray', 'singbox']) {
      final dir = Directory('assets/contract_draft/$kind');
      if (!dir.existsSync()) continue;
      for (final f in dir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.json')) continue;
        final doc = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        if (doc['_overlay'] != true) continue;
        final name = f.uri.pathSegments.last.replaceAll('.json', '');


        final ov = _map(_map(doc['mappers'])?[kind]);
        final base =
            _map(_map(ContractRegistry.I.rawProtocol(name)?['mappers'])?[kind]);
        if (ov != null && base != null) pairs.add(('$kind/$name', base, ov));


        final blocks = _map(doc['blocks']);
        final regBlocks =
            _map(ContractRegistry.I.rawShared('$name.json')?['blocks']);
        if (blocks != null && regBlocks != null) {
          for (final d in blocks.entries) {
            final o = _map(d.value);
            final b = _map(regBlocks[d.key]);
            if (o != null && b != null) {
              pairs.add(('$kind/$name#${d.key}', b, o));
            }
          }
        }
      }
    }







    expect(pairs.length, greaterThanOrEqualTo(5),
        reason: 'сверка не должна быть пустой: '
            '${pairs.map((p) => p.$1).toList()}');
    for (final (id, base, ov) in pairs) {
      expect(jsonEncode(_merge(base, ov)), jsonEncode(_mergeOld(base, ov)),
          reason: 'оверлей $id сливается иначе, чем до правки');
    }
  });
}
