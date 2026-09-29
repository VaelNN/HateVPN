import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/template_vars.dart';
import 'package:lxbox/services/contract/registry.dart';
import 'package:lxbox/services/node_hash.dart';
import 'package:lxbox/services/parser/engine/section_loader.dart';
import 'package:lxbox/services/parser/mappers/draft_sections.dart';
import 'package:lxbox/services/parser/uri_parsers.dart';












const _registryRoot = 'assets/contract';
const _draftRoot = 'assets/contract_draft';





















const Map<String, String> _delta480 = {
  'upper_type_ws': 'delta480: Type=ws теперь читается — появился transport ws',
  'upper_alpn': 'delta480: ALPN=h2 теперь читается — появился tls.alpn',
  'upper_fp': 'delta480: Fp=chrome теперь читается — появился tls.utls',
  'path_raw_plus': 'delta480 D133-14: было "/a b", стало "/a+b"',
  'path_encoded_slash_raw_plus': 'delta480 D133-14: было "/a b", стало "/a+b"',
};

Map<String, Map<String, dynamic>> _cases() {
  final f = File('test/fixtures/trojan/pipeline_identity_before.json');
  final raw = jsonDecode(f.readAsStringSync()) as Map;
  return (raw['cases'] as Map).map(
    (k, v) => MapEntry(k as String, (v as Map).cast<String, dynamic>()),
  );
}

void main() {
  final mirrored = Directory('$_registryRoot/registry').existsSync();
  final skip = mirrored ? null : 'зеркало реестра не найдено';

  setUpAll(() async {
    if (!mirrored) return;
    await ContractRegistry.I.loadFromDirectory(_registryRoot);
    await MapperSections.I.loadDrafts(dir: _draftRoot, files: kDraftFiles);
  });

  test('секция trojan исполняема и загружена', () {
    expect(MapperSections.I.has('uri', 'trojan'), isTrue,
        reason: 'без секции движок не работает вовсе — запасного '
            'рукописного пути у переехавшей схемы не осталось');
  }, skip: skip);

  test('35 кейсов снимка: identity, тег и тело байт в байт', () {
    final cases = _cases();
    expect(cases, hasLength(35));

    final diffs = <String>[];
    for (final e in cases.entries) {
      final uri = e.value['uri'] as String;
      final spec = parseUri(uri);
      final delta = _delta480[e.key];

      if (e.value['identity'] == null) {
        expect(spec, isNull, reason: 'кейс ${e.key}: был отбракован');
        continue;
      }
      if (spec == null) {
        diffs.add('${e.key}: перестал разбираться');
        continue;
      }

      final gotBody = jsonEncode(spec.emit(TemplateVars.empty).map);
      final wantBody = jsonEncode(e.value['body']);
      if (gotBody != wantBody) {
        diffs.add('${e.key}: тело разошлось с ожиданием фикстуры\n'
            '  ждали: $wantBody\n'
            '  вышло: $gotBody');
        continue;
      }
      expect(legacyNodeIdentityHash(spec), e.value['identity'],
          reason: 'identity кейса ${e.key}');
      expect(spec.tag, e.value['tag'], reason: 'тег кейса ${e.key}');




      if (delta == null) continue;
      final before = e.value['_before480'] as Map?;
      if (before == null) {
        diffs.add('${e.key}: помечен дельтой, но прежних значений в фикстуре '
            'нет — «было → стало» обязано быть записано ($delta)');
        continue;
      }
      if (jsonEncode(before['body']) == gotBody) {
        diffs.add('${e.key}: помечен дельтой, но тело не изменилось ($delta)');
      }
    }

    expect(diffs, isEmpty,
        reason: 'расхождения вне списка дельт чинятся в движке или в '
            'секции, а не правкой фикстуры:\n${diffs.join('\n')}');
  }, skip: skip);
}
