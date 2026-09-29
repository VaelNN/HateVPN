import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../contract_paths.dart';
import 'package:lxbox/models/node_spec.dart';
import 'package:lxbox/models/node_warning.dart';
import 'package:lxbox/models/template_vars.dart';
import 'package:lxbox/services/contract/body_sanitizer.dart';
import 'package:lxbox/services/contract/parse_warnings.dart';
import 'package:lxbox/services/parser/engine/section_loader.dart';
import 'package:lxbox/services/parser/mappers/draft_sections.dart';
import 'package:lxbox/services/contract/warning_codes.dart';
import 'package:lxbox/services/node_hash.dart';
import 'package:lxbox/services/parser/uri_parsers.dart';


























const _identityFixture = 'test/fixtures/vless/pipeline_identity_before.json';

Map<String, Map<String, dynamic>> _identityBefore() {
  final raw = jsonDecode(File(_identityFixture).readAsStringSync()) as Map;
  return (raw['cases'] as Map).map(
    (k, v) => MapEntry(k as String, (v as Map).cast<String, dynamic>()),
  );
}


List<String> _corpusUris() {
  final out = <String>[];
  final files = Directory('$kVendorRoot/corpus/uri/vless')
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
      corpusTestSkip('test/parser/vless_pipeline_invariants_test.dart');

  setUpAll(() async {
    await loadTestRegistry();
    await MapperSections.I
        .loadDrafts(dir: 'assets/contract_draft', files: kDraftFiles);
  });

  group('§472 инвариант 4 — identity vless не меняется', () {
    test('каждый кейс корпуса даёт хеш из фикстуры', () {
      final before = _identityBefore();
      expect(before, hasLength(greaterThan(80)),
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

    test('identity всего корпуса vless считается и не пуста', () {
      final nodes = <NodeSpec>[];
      for (final u in _corpusUris()) {
        final spec = parseUri(u);
        if (spec != null) nodes.add(spec);
      }
      expect(nodes, isNotEmpty);

      expect(sourceNodeIdentities(nodes).length, nodes.length);
    }, skip: corpusSkip);
  });

  group('§472 инвариант 3 — parseUri(toUri()) ≈ spec', () {















    const notIdempotent = {'enc-pq', 'xhttp-mode-invalid', 'xhttp-bogus-plc'};











    bool hasExplicitRootPath(NodeSpec s) {
      final t = s.emit(TemplateVars.empty).map['transport'];
      return t is Map && t['path'] == '/';
    }

    test('весь корпус vless переживает круг', () {
      var checked = 0;
      for (final u in _corpusUris()) {
        final a = parseUri(u);
        if (a == null) continue;
        if (notIdempotent.contains(a.tag)) continue;
        if (hasExplicitRootPath(a)) continue;
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

      expect(checked, greaterThan(75));
    }, skip: corpusSkip);
  });

  group('§472 инвариант 5 — цена разбора', () {




















    test('2000 vless-узлов разбираются за разумное время', () {
      const n = 2000;
      final uris = [
        for (var i = 0; i < n; i++)
          'vless://11111111-1111-1111-1111-11111111111$i@example-$i.com:443'
              '?type=ws&path=%2Fx%3Fed%3D2560&security=reality'
              '&pbk=AwoRGB8mLTQ7QklQV15lbHN6gYiPlp2kq7K5wMfO1dw&sid=abcd'
              '&sni=example-$i.com&fp=chrome&alpn=h2,http/1.1#node$i',
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
        reason: 'разбор $n vless-узлов конвейером: $best мс (лучший из трёх)',
      );
    });
  });

  group('§472 — коды vless приходят из реестра, с путём и сырым значением', () {
    test('мусорный fp судит реестр по написанному автором', () {
      final spec = parseUri(
          'vless://u@h.example:443?security=tls&fp=bogus&sni=x.com#n')!;
      final w = spec.warnings
          .whereType<RegistryWarning>()
          .firstWhere((w) => w.code == 'utls_fp_unknown');
      expect(w.path, 'tls.utls.fingerprint');
      expect(w.value, 'bogus');
    });

    test('flow вне пары даёт flow_deprecated с путём', () {
      final spec = parseUri('vless://u@h.example:443?security=tls&sni=x.com'
          '&flow=xtls-rprx-direct#n')!;
      final w = spec.warnings
          .whereType<RegistryWarning>()
          .firstWhere((w) => w.code == 'flow_deprecated');
      expect(w.path, 'flow');
      expect(w.value, 'xtls-rprx-direct');
      expect(spec.emit(TemplateVars.empty).map.containsKey('flow'), isFalse);
    });

    test('мусорный packetEncoding — код реестра, поле снято', () {
      final spec = parseUri('vless://u@h.example:443?security=tls&sni=x.com'
          '&packetEncoding=teleport#n')!;
      final w = spec.warnings
          .whereType<RegistryWarning>()
          .firstWhere((w) => w.code == 'packet_encoding_unknown');
      expect(w.path, 'packet_encoding');
      expect(w.value, 'teleport');
      expect((spec as VlessSpec).packetEncoding, '');
    });

    test('негодный pbk снимает REALITY молча, кроме одного кода', () {



      final spec = parseUri('vless://u@h.example:443?security=tls&sni=x.com'
          '&pbk=enabled&sid=abcd&key_share=hybrid#n')!;
      final codes =
          spec.warnings.map(warningCodeOf).whereType<String>().toList();
      expect(codes, ['reality_pbk_invalid']);
      final tls = spec.emit(TemplateVars.empty).map['tls'] as Map;
      expect(tls.containsKey('reality'), isFalse);
    });

    test('sid только в другом регистре — нормализация без кода', () {


      final spec = parseUri('vless://u@h.example:443?security=reality&sni=x.com'
          '&pbk=AwoRGB8mLTQ7QklQV15lbHN6gYiPlp2kq7K5wMfO1dw&sid=ABCD#n')!;
      expect(spec.warnings.map(warningCodeOf),
          isNot(contains('reality_short_id_invalid')));
      final reality =
          (spec.emit(TemplateVars.empty).map['tls'] as Map)['reality'] as Map;
      expect(reality['short_id'], 'abcd');
    });

    test('§453 dial-поля идут мимо санитайзера и не теряются', () {



      final spec = parseUri('vless://u@h.example:443'
          '?tcp_keep_alive=30s&tcp_keep_alive_interval=15s'
          '&disable_tcp_keep_alive=1#KA')!;
      expect(spec.tcpKeepAlive?.idle, '30s');
      expect(spec.tcpKeepAlive?.interval, '15s');
      expect(spec.tcpKeepAlive?.disabled, isTrue);
      expect(spec.warnings.map(warningCodeOf), isNot(contains('unknown_key')));
    });

    test('encryption из ссылки доезжает до тела', () {


      final spec = parseUri('vless://u@h.example:443?security=none'
          '&encryption=mlkem768x25519plus.native.1rtt.AbCd#n')!;
      expect((spec as VlessSpec).encryption,
          'mlkem768x25519plus.native.1rtt.AbCd');
      expect(spec.emit(TemplateVars.empty).map['encryption'],
          'mlkem768x25519plus.native.1rtt.AbCd');
    });
  });

  group('§477 — vless encryption: форма по реестру', () {



    test('годное значение проходит: ключ 32, ключ 1184, padding-блоки', () {
      const key32 = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      for (final enc in [
        'mlkem768x25519plus.native.0rtt.$key32',
        'mlkem768x25519plus.xorpub.1rtt.100-50-50.$key32',
        'mlkem768x25519plus.random.0rtt.150-40-40.30-20-20.$key32',
      ]) {
        final spec = parseUri(
            'vless://u@h.example:443?security=none&encryption=$enc#n');
        expect(spec, isNotNull, reason: '$enc отбракован, хотя годен');
        expect(spec!.emit(TemplateVars.empty).map['encryption'], enc,
            reason: enc);
      }
    });

    test('края обрезаются тихо, в тело едет обрезанное', () {

      const enc = 'mlkem768x25519plus.native.0rtt.AAAAAAAAAAAAAAAAAAAAAAAA';
      final spec = parseUri('vless://u@h.example:443?security=none'
          '&encryption=${Uri.encodeQueryComponent('  $enc  ')}#n')!;
      expect(spec.emit(TemplateVars.empty).map['encryption'], enc);
      expect(spec.warnings.map(warningCodeOf),
          isNot(contains('vless_encryption_invalid')));
    });

    test('пробел ВНУТРИ сегмента законен', () {


      const enc = 'mlkem768x25519plus.native.0rtt. AAAAAAAAAAAAAAAAAAAAAAAA';
      final spec = parseUri('vless://u@h.example:443?security=none'
          '&encryption=${Uri.encodeQueryComponent(enc)}#n')!;
      expect(spec.emit(TemplateVars.empty).map['encryption'], enc);
    });

    test('пусто и ТОЧНОЕ none — слоя нет, кода нет', () {
      for (final enc in ['', 'none', '%20none%20']) {
        final spec = parseUri('vless://u@h.example:443?security=none'
            '&encryption=$enc#n')!;
        expect(spec.emit(TemplateVars.empty).map.containsKey('encryption'),
            isFalse,
            reason: 'encryption=$enc: поле не должно попадать в тело');
        expect(spec.warnings.map(warningCodeOf),
            isNot(contains('vless_encryption_invalid')),
            reason: 'encryption=$enc: выключатель — не повод для кода');
      }
    });

    test('None другого регистра — НЕ выключатель, узел отбракован', () {



      for (final enc in ['None', 'NONE']) {
        expect(
            parseUri(
                'vless://u@h.example:443?security=none&encryption=$enc#n'),
            isNull,
            reason: '$enc обязан отбраковать узел, а не выключить слой');
      }
    });

    test('негодная форма отбраковывает УЗЕЛ, а не снимает поле', () {


      for (final enc in [
        'mlkem768x25519plus.native.0rtt',
        'mlkem768x25519plus.native..0rtt.KEY',
        'mlkem1024x25519plus.native.0rtt.KEY',
        'MLKEM768X25519PLUS.native.0rtt.KEY',
        'garbage',
        'mlkem768x25519plus.native.0rtt.KEY.',
      ]) {
        expect(
            parseUri('vless://u@h.example:443?security=none'
                '&encryption=${Uri.encodeQueryComponent(enc)}#n'),
            isNull,
            reason: '$enc должен был отбраковать узел');
      }
    });

    test('в код уезжает СЫРОЕ значение, до обрезки', () {

      const raw = '  garbage  ';
      final res = RegistrySanitizer.sanitize(<String, dynamic>{
        'type': 'vless',
        'server': 'h.example',
        'server_port': 443,
        'uuid': '11111111-1111-1111-1111-111111111111',
        'encryption': raw,
      }, scheme: 'vless', coreVersion: '1.14.1-lx.4', applyCoreGates: false);

      expect(res.body, isNull, reason: 'drop_node: записи нет');
      final w = res.warnings
          .singleWhere((w) => w.code == 'vless_encryption_invalid');
      expect(w.path, 'encryption');
      expect(w.value, raw, reason: 'значение обязано быть сырым, до trim');
    });

    test('тело sing-box судится тем же правилом, что и ссылка', () {


      Map<String, dynamic> body(String enc) => <String, dynamic>{
            'type': 'vless',
            'server': 'h.example',
            'server_port': 443,
            'uuid': '11111111-1111-1111-1111-111111111111',
            'encryption': enc,
          };
      Map<String, dynamic>? clean(String enc) => RegistrySanitizer.sanitize(
            body(enc),
            scheme: 'vless',
            coreVersion: '1.14.1-lx.4',
            applyCoreGates: false,
          ).body;


      expect(clean('none')?.containsKey('encryption'), isFalse);

      expect(clean('None'), isNull);

      expect(clean('  mlkem768x25519plus.native.0rtt.KEYKEYKEY  ')?['encryption'],
          'mlkem768x25519plus.native.0rtt.KEYKEYKEY');
    });
  });

  group('§472 — второй проход по emit() узла конвейера не дублирует коды', () {
    test('annotateAllWithRegistry на разобранном vless ничего не добавляет',
        () {
      final spec = parseUri(
          'vless://u@h.example:443?security=tls&fp=bogus&sni=x.com#n')!;
      final before = spec.warnings.length;
      annotateAllWithRegistry([spec]);
      expect(spec.warnings, hasLength(before),
          reason: 'второй проход задвоил коды узла конвейера');
    });
  });
}
