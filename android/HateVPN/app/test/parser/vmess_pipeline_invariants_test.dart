import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../contract_paths.dart';
import 'package:lxbox/models/node_spec.dart';
import 'package:lxbox/models/node_warning.dart';
import 'package:lxbox/models/template_vars.dart';
import 'package:lxbox/services/contract/parse_warnings.dart';
import 'package:lxbox/services/contract/warning_codes.dart';
import 'package:lxbox/services/node_hash.dart';
import 'package:lxbox/services/parser/uri_parsers.dart';









const _identityFixture = 'test/fixtures/vmess/pipeline_identity_before.json';

Map<String, Map<String, dynamic>> _identityBefore() {
  final raw = jsonDecode(File(_identityFixture).readAsStringSync()) as Map;
  return (raw['cases'] as Map).map(
    (k, v) => MapEntry(k as String, (v as Map).cast<String, dynamic>()),
  );
}


List<String> _corpusUris() {
  final out = <String>[];
  final files = Directory('$kVendorRoot/corpus/uri/vmess')
      .listSync()
      .whereType<File>()
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    if (!f.path.endsWith('.uri')) continue;
    for (final line in f.readAsLinesSync()) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      out.add(t);
    }
  }
  return out;
}

void main() {
  final corpusSkip =
      corpusTestSkip('test/parser/vmess_pipeline_invariants_test.dart');

  setUpAll(loadTestRegistry);

  group('§472 инвариант 4 — identity vmess не меняется', () {
    test('каждый кейс корпуса даёт хеш из фикстуры', () {
      final before = _identityBefore();
      expect(before, hasLength(greaterThan(15)),
          reason: 'фикстура похудела — проверьте, не срезан ли корпус');
      for (final e in before.entries) {
        final uri = e.value['uri'] as String;
        final want = e.value['identity'] as String?;
        final spec = parseUri(uri);
        if (want == null) {



          expect(spec, isNull, reason: 'кейс ${e.key} стал разбираться');
          continue;
        }
        expect(spec, isNotNull, reason: 'кейс ${e.key} перестал разбираться');
        expect(
          legacyNodeIdentityHash(spec!),
          want,
          reason: 'identity кейса ${e.key} изменилась: у пользователей слетят '
              'выбор узла, отключения и цепочки',
        );
      }
    });
  });

  group('§472 инвариант 3 — parseUri(toUri()) ≈ spec', () {
















    bool transportFieldOutsideCanonicalUri(NodeSpec s) {
      final t = s.emit(TemplateVars.empty).map['transport'];
      if (t is! Map) return false;
      return t['mode'] != null || t['max_early_data'] != null;
    }











    bool cleartextWithWsHostFallback(NodeSpec s) {
      if (!s.rawSource.startsWith('vmess://')) return false;
      final t = s.emit(TemplateVars.empty).map['transport'];
      if (t is! Map || t['type'] != 'ws' || t.containsKey('headers')) {
        return false;
      }

      final tls = s.emit(TemplateVars.empty).map['tls'];
      return tls is Map && (tls['server_name']?.toString() ?? '').isNotEmpty;
    }

    test('весь корпус vmess переживает круг', () {
      var checked = 0;
      for (final u in _corpusUris()) {
        final a = parseUri(u);
        if (a == null) continue;
        if (transportFieldOutsideCanonicalUri(a)) continue;
        if (cleartextWithWsHostFallback(a)) continue;
        final b = parseUri(a.toUri());
        expect(b, isNotNull, reason: 'круг потерял узел: $u');
        expect(
          b!.emit(TemplateVars.empty).map,
          a.emit(TemplateVars.empty).map,
          reason: 'круг изменил тело: $u',
        );
        expect(legacyNodeIdentityHash(b), legacyNodeIdentityHash(a),
            reason: 'круг изменил identity: $u');
        checked++;
      }


      expect(checked, greaterThan(12));
    }, skip: corpusSkip);

    test('обе формы ссылки дают одно тело', () {



      const json = '{"v":"2","ps":"n","add":"h.example","port":"8443",'
          '"id":"11111111-1111-1111-1111-111111111111","net":"ws",'
          '"path":"/ws","scy":"aes-128-gcm","tls":"tls"}';
      final a = parseUri('vmess://${base64.encode(utf8.encode(json))}')!;
      final b = parseUri('vmess://${base64.encode(utf8.encode(
        'aes-128-gcm:11111111-1111-1111-1111-111111111111@h.example:8443'
        '?type=ws&path=%2Fws&tls=1',
      ))}#n')!;
      expect(b.emit(TemplateVars.empty).map, a.emit(TemplateVars.empty).map);
      expect(legacyNodeIdentityHash(b), legacyNodeIdentityHash(a));
    });
  });

  group('§472 инвариант 5 — цена разбора', () {



    test('2000 vmess-узлов разбираются за разумное время', () {
      const n = 2000;
      final uris = [
        for (var i = 0; i < n; i++)
          'vmess://${base64.encode(utf8.encode(jsonEncode({
                'v': '2',
                'ps': 'node$i',
                'add': 'example-$i.com',
                'port': '443',
                'id': '11111111-1111-1111-1111-11111111111$i',
                'net': 'ws',
                'path': '/x?ed=2560',
                'host': 'example-$i.com',
                'tls': 'tls',
                'fp': 'chrome',
                'alpn': 'h2,http/1.1',
                'scy': 'auto',
              })))}',
      ];


      for (var i = 0; i < 200; i++) {
        parseUri(uris[i]);
      }

      final nodes = <NodeSpec>[];
      var best = 1 << 30;
      for (var rep = 0; rep < 3; rep++) {
        nodes.clear();
        final sw = Stopwatch()..start();
        for (final u in uris) {
          final s = parseUri(u);
          if (s != null) nodes.add(s);
        }
        sw.stop();
        if (sw.elapsedMilliseconds < best) best = sw.elapsedMilliseconds;
      }
      expect(nodes, hasLength(n));
      expect(
        best,
        lessThan(3000),
        reason: 'разбор $n vmess-узлов конвейером: $best мс (лучший из трёх)',
      );
    });
  });

  group('§472 — коды vmess приходят из реестра, с путём и сырым значением', () {
    test('мусорный fp судит реестр по написанному автором', () {
      const json = '{"v":"2","ps":"n","add":"h.example","port":"443",'
          '"id":"11111111-1111-1111-1111-111111111111","net":"tcp",'
          '"tls":"tls","fp":"wat"}';
      final spec = parseUri('vmess://${base64.encode(utf8.encode(json))}')!;
      final w = spec.warnings
          .whereType<RegistryWarning>()
          .firstWhere((w) => w.code == 'utls_fp_unknown');
      expect(w.path, 'tls.utls.fingerprint');

      expect(w.value, 'wat');
      final tls = spec.emit(TemplateVars.empty).map['tls'] as Map;
      expect((tls['utls'] as Map)['fingerprint'], 'chrome');
    });

    test('§453 dial-поля контейнера идут мимо санитайзера и не теряются', () {



      const json = '{"v":"2","ps":"KA","add":"h.example","port":"443",'
          '"id":"11111111-1111-1111-1111-111111111111","net":"tcp",'
          '"tcp_keep_alive":"30s","tcp_keep_alive_interval":"15s",'
          '"disable_tcp_keep_alive":true}';
      final spec = parseUri('vmess://${base64.encode(utf8.encode(json))}')!;
      expect(spec.tcpKeepAlive?.idle, '30s');
      expect(spec.tcpKeepAlive?.interval, '15s');
      expect(spec.tcpKeepAlive?.disabled, isTrue);
      expect(spec.warnings.map(warningCodeOf), isNot(contains('unknown_key')));
    });
  });

  group('§472 — второй проход по emit() узла конвейера не дублирует коды', () {
    test('annotateAllWithRegistry на разобранном vmess ничего не добавляет',
        () {
      const json = '{"v":"2","ps":"n","add":"h.example","port":"443",'
          '"id":"11111111-1111-1111-1111-111111111111","net":"tcp",'
          '"tls":"tls","fp":"wat"}';
      final spec = parseUri('vmess://${base64.encode(utf8.encode(json))}')!;
      final before = spec.warnings.length;
      annotateAllWithRegistry([spec]);
      expect(spec.warnings, hasLength(before),
          reason: 'второй проход задвоил коды узла конвейера');
    });
  });
}
