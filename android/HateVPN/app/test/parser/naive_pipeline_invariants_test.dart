import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../contract_paths.dart';
import 'package:lxbox/models/node_spec.dart';
import 'package:lxbox/models/node_warning.dart';
import 'package:lxbox/models/template_vars.dart';
import 'package:lxbox/services/contract/parse_warnings.dart';
import 'package:lxbox/services/node_hash.dart';
import 'package:lxbox/services/parser/json_parsers.dart';
import 'package:lxbox/services/parser/uri_parsers.dart';








const _identityFixture = 'test/fixtures/naive/pipeline_identity_before.json';

Map<String, Map<String, dynamic>> _identityBefore() {
  final raw = jsonDecode(File(_identityFixture).readAsStringSync()) as Map;
  return (raw['cases'] as Map).map(
    (k, v) => MapEntry(k as String, (v as Map).cast<String, dynamic>()),
  );
}

List<String> _corpusUris() {
  final out = <String>[];
  final files = Directory('$kVendorRoot/corpus/uri/naive')
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

List<RegistryWarning> _registry(NodeSpec n) =>
    n.warnings.whereType<RegistryWarning>().toList();



List<String> _codes(NodeSpec n) => [for (final w in _registry(n)) w.code];

void main() {
  final corpusSkip = corpusTestSkip('test/parser/naive_pipeline_invariants_test.dart');

  setUpAll(() async {
    await loadTestRegistry();
  });

  group('§472 инвариант 4 — identity naive не меняется', () {
    test('каждый кейс корпуса даёт хеш из фикстуры', () {
      final before = _identityBefore();
      expect(before, hasLength(greaterThan(17)),
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
    test('весь корпус naive переживает круг', () {
      var checked = 0;
      for (final u in _corpusUris()) {
        final a = parseUri(u);
        if (a == null) continue;
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

      expect(checked, greaterThan(13));
    }, skip: corpusSkip);

    test('naive+quic переживает круг: написание схемы несёт QUIC', () {












      final a = parseUri('naive+quic://u:p@quic.example:443#q')!;
      expect(a.emit(TemplateVars.empty).map['quic'], isTrue);
      expect(a.toUri(), startsWith('naive+quic://'));
      final b = parseUri(a.toUri())!;
      expect(b.emit(TemplateVars.empty).map, a.emit(TemplateVars.empty).map,
          reason: 'написание схемы возвращает QUIC целиком');
    });
  });

  group('§472 инвариант 5 — цена разбора', () {
    test('2000 naive-узлов разбираются за разумное время', () {
      const n = 2000;
      final uris = [
        for (var i = 0; i < n; i++)
          'naive+https://user$i:pass$i@example-$i.com:443'
              '?extra-headers=X-Tag%3A%20v$i#node$i',
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
        reason: 'разбор $n naive-узлов конвейером: $best мс (лучший из трёх)',
      );
    });
  });

  group('§472 — naive: перевод, который остаётся за маппером', () {
    test('§465 — одиночный userinfo это PASSWORD', () {
      final only = parseUri('naive+https://secret@h.example#n')!;
      final body = only.emit(TemplateVars.empty).map;
      expect(body['password'], 'secret');
      expect(body.containsKey('username'), isFalse);


      final userOnly = parseUri('naive+https://alice:@h.example#n')!;
      final ub = userOnly.emit(TemplateVars.empty).map;
      expect(ub['username'], 'alice');
      expect(ub.containsKey('password'), isFalse);


      expect(userOnly.toUri(), contains('alice:@'));
    });

    test('naive+quic даёт quic: true и bbr, naive+https — нет', () {
      final quic = parseUri('naive+quic://u:p@h.example:443#q')!;
      final qb = quic.emit(TemplateVars.empty).map;
      expect(qb['quic'], isTrue);
      expect(qb['quic_congestion_control'], 'bbr');

      final https = parseUri('naive+https://u:p@h.example:443#h')!;
      expect(https.emit(TemplateVars.empty).map.containsKey('quic'), isFalse);
    });

    test('extra-headers: битая пара пропускается, остальные живут', () {


      final spec = parseUri('naive+https://u:p@h.example'
          '?extra-headers=X%20User%3Abad%0D%0AX-Good%3Aok#n')!;
      expect(spec.emit(TemplateVars.empty).map['extra_headers'],
          {'X-Good': 'ok'});
      expect(_codes(spec).where((c) => c == 'naive_extra_headers_invalid'),
          hasLength(1));
    });

    test('padding отбрасывается с кодом маппера', () {


      final spec =
          parseUri('naive+https://u:p@h.example?padding=true#n')!;
      expect(_codes(spec), contains('naive_padding_ignored'));
      expect(spec.emit(TemplateVars.empty).map.containsKey('padding'), isFalse);
    });

    test('TLS у naive всегда минимален: enabled + server_name', () {



      final spec = parseUri('naive+https://u:p@h.example:443#n')!;
      expect(spec.emit(TemplateVars.empty).map['tls'],
          {'enabled': true, 'server_name': 'h.example'});
      expect(_registry(spec).map((w) => w.code),
          isNot(contains('tls_field_unsupported_naive')));
    });

    test('пустой host отбраковывается (§463)', () {


      expect(parseUri('naive+https://'), isNull);
    });

    test('§453 dial-поля доезжают до тела и не теряются', () {
      final spec =
          parseUri('naive+https://u:p@h.example?tcp_keep_alive=30s#n')!;
      expect(spec.emit(TemplateVars.empty).map['tcp_keep_alive'], '30s');
      expect(_registry(spec).map((w) => w.code), isNot(contains('unknown_key')));
    });
  });

  group('§472 — дефект: QUIC терялся на входе тела', () {
    test('quic читается из тела обратно в модель', () {




      final node = parseSingboxEntry({
        'type': 'naive',
        'tag': 'n',
        'server': 'h.example',
        'server_port': 443,
        'username': 'u',
        'password': 'p',
        'quic': true,
        'quic_congestion_control': 'bbr',
        'tls': {'enabled': true, 'server_name': 'h.example'},
      })!;
      expect((node as NaiveSpec).quic, isTrue);

      final body = node.emit(TemplateVars.empty).map;
      expect(body['quic'], isTrue);
      expect(body['quic_congestion_control'], 'bbr');
    });

    test('без ключа quic узел остаётся на HTTP/2', () {
      final node = parseSingboxEntry({
        'type': 'naive',
        'tag': 'n',
        'server': 'h.example',
        'server_port': 443,
        'tls': {'enabled': true, 'server_name': 'h.example'},
      })!;
      expect((node as NaiveSpec).quic, isFalse);
    });
  });

  group('§472 — второй проход по emit() узла конвейера не дублирует коды', () {
    test('annotateAllWithRegistry на разобранном naive ничего не добавляет',
        () {
      final spec = parseUri('naive+https://u:p@h.example:443'
          '?padding=true&extra-headers=X-A%3A%20b#L')!;
      final before = spec.warnings.length;
      annotateAllWithRegistry([spec]);
      expect(spec.warnings, hasLength(before),
          reason: 'второй проход задвоил коды узла конвейера');
    });
  });
}
