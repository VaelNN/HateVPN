import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/template_vars.dart';
import 'package:lxbox/services/contract/registry.dart';
import 'package:lxbox/services/node_hash.dart';
import 'package:lxbox/services/parser/engine/section_loader.dart';
import 'package:lxbox/services/parser/ini_parser.dart';
import 'package:lxbox/services/parser/mappers/draft_sections.dart';
import 'package:lxbox/services/parser/uri_parsers.dart';




















const _registryRoot = 'assets/contract';



const Map<String, int> _expected = {
  'trojan': 35,
  'shadowsocks': 7,
  'vless': 10,
  'hysteria2': 5,
  'tuic': 3,
  'ssh': 2,
  'socks': 8,
  'vmess': 3,
  'anytls': 1,
  'naive': 1,
  'http': 2,
  'masque': 2,
  'wireguard': 9,
};


const int _expectedIni = 5;

Map<String, Map<String, dynamic>> _cases(String scheme) {
  final f = File('test/fixtures/$scheme/pipeline_identity_before.json');
  final raw = jsonDecode(f.readAsStringSync()) as Map;
  return (raw['cases'] as Map).map(
    (k, v) => MapEntry(k as String, (v as Map).cast<String, dynamic>()),
  );
}




Map<String, Map<String, dynamic>> _before480(String scheme) {
  final all = _cases(scheme);
  if (scheme == 'trojan') return all;
  return {
    for (final e in all.entries)
      if (e.key.startsWith('b480:')) e.key: e.value,
  };
}

void main() {
  final mirrored = Directory('$_registryRoot/registry').existsSync();
  final skip = mirrored ? null : 'зеркало реестра не найдено';

  setUpAll(() async {
    if (!mirrored) return;
    await ContractRegistry.I.loadFromDirectory(_registryRoot);


    await MapperSections.I
        .loadDrafts(dir: 'assets/contract_draft', files: kDraftFiles);
  });

  group('§480 снимок «до переезда» — ссылки', () {
    for (final entry in _expected.entries) {
      final scheme = entry.key;
      test('$scheme: хеш, тег и тело каждого кейса на месте', () {
        final before = _before480(scheme);
        expect(before, hasLength(entry.value),
            reason: 'снимок $scheme изменился в размере: было ${entry.value}, '
                'стало ${before.length}. Кейс снимка не убирают молча — либо '
                'правьте счётчик вместе с фикстурой, либо верните кейс');

        for (final e in before.entries) {
          final uri = e.value['uri'] as String;
          final want = e.value['identity'] as String?;
          final spec = parseUri(uri);

          if (want == null) {


            expect(e.value['dropped'], isTrue,
                reason: 'кейс ${e.key}: identity=null обязан нести dropped');
            expect(spec, isNull,
                reason: 'кейс ${e.key} СТАЛ разбираться. Если это и есть '
                    'починка — снимите значения заново и обновите фикстуру');
            continue;
          }

          expect(spec, isNotNull,
              reason: 'кейс ${e.key} перестал разбираться');
          expect(legacyNodeIdentityHash(spec!), want,
              reason: 'identity кейса ${e.key} изменилась: у пользователей '
                  'слетят выбор узла, отключения и цепочки');
          expect(spec.tag, e.value['tag'], reason: 'тег кейса ${e.key}');
          expect(jsonEncode(spec.emit(TemplateVars.empty).map),
              jsonEncode(e.value['body']),
              reason: 'тело кейса ${e.key} (эталоны сравниваются БАЙТ В БАЙТ, '
                  'включая порядок ключей)');
        }
      }, skip: skip);
    }
  });

  group('§480 снимок «до переезда» — INI', () {
    test('wireguard: INI-кейсы дают прежние хеш, тег и тело', () {
      final ini = {
        for (final e in _cases('wireguard').entries)
          if (e.key.startsWith('ini:b480_')) e.key: e.value,
      };
      expect(ini, hasLength(_expectedIni),
          reason: 'снимок INI изменился в размере');

      for (final e in ini.entries) {


        final spec = parseWireguardIni(e.value['ini'] as String,
            nameHint: 'file-hint');
        final want = e.value['identity'] as String?;
        if (want == null) {
          expect(e.value['dropped'], isTrue, reason: e.key);
          expect(spec, isNull, reason: 'кейс ${e.key} стал разбираться');
          continue;
        }
        expect(spec, isNotNull, reason: 'кейс ${e.key} перестал разбираться');
        expect(legacyNodeIdentityHash(spec!), want,
            reason: 'identity кейса ${e.key}');
        expect(spec.tag, e.value['tag'], reason: 'тег кейса ${e.key}');
        expect(spec.rawSource, e.value['ini'],
            reason: '§456 — источник INI-узла это сам INI, байт в байт');
        expect(jsonEncode(spec.emit(TemplateVars.empty).map),
            jsonEncode(e.value['body']),
            reason: 'тело кейса ${e.key}');
      }
    }, skip: skip);
  });
}
