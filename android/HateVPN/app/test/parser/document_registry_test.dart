import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/services/contract/registry.dart';
import 'package:lxbox/services/parser/body_decoder.dart';
import 'package:lxbox/services/parser/engine/document.dart';
import 'package:lxbox/services/parser/engine/section_loader.dart';
import 'package:lxbox/services/parser/mappers/draft_sections.dart';











const _registryRoot = 'assets/contract';
const _draftRoot = 'assets/contract_draft';



final Map<String, String> _documents = {
  'список ссылок': 'trojan://pw@h.example:443#a\nvless://u@h2.example:443#b',
  'список с комментариями':
      '# заголовок\ntrojan://pw@h.example:443#a\n// ещё\n;и ещё\n',
  'base64-подписка': base64.encode(utf8.encode(
      'trojan://pw@h.example:443#a\nvless://u@h2.example:443#b')),
  'xray-массив':
      '[{"remarks":"x","outbounds":[{"protocol":"vless","settings":{}}]}]',
  'sing-box одиночный outbound':
      '{"type":"trojan","server":"h.example","server_port":443,"password":"p"}',
  'sing-box массив outbound-ов':
      '[{"type":"trojan","server":"h.example","server_port":443,"password":"p"}]',
  'sing-box полный конфиг':
      '{"log":{},"outbounds":[{"type":"trojan","server":"h.example",'
          '"server_port":443,"password":"p"}],"route":{}}',
  'sing-box конфиг из одних endpoints':
      '{"log":{},"endpoints":[{"type":"wireguard","name":"w"}]}',
  'массив sing-box-конфигов':
      '[{"outbounds":[{"type":"trojan","server":"h.example",'
          '"server_port":443,"password":"p"}]}]',
  'wg-quick .conf':
      '[Interface]\nPrivateKey = aaa\nAddress = 10.0.0.2/32\n\n[Peer]\n'
          'PublicKey = bbb\nEndpoint = h.example:51820\n',
  'wg-quick с комментарием над секцией':
      '# my node\n[Interface]\nPrivateKey = aaa\n\n[Peer]\nPublicKey = bbb\n'
          'Endpoint = h.example:51820\n',
  'clash': '{"proxies":[{"name":"a","type":"ss"}]}',
  'мусор': 'это просто текст без ссылок',
};


String _kindOf(DecodedBody b) => switch (b) {
      UriLines() => 'UriLines(${b.lines.length},${b.skippedComments})',
      IniConfig() => 'IniConfig',
      AmneziaConfig() => 'AmneziaConfig(${b.iniTexts.length})',
      JsonConfig() => 'JsonConfig(${b.source.kind})',
      DecodeFailure() => 'DecodeFailure',
    };

void main() {
  final mirrored = Directory('$_registryRoot/registry').existsSync();
  final skip = mirrored ? null : 'зеркало реестра не найдено';



  final legacy = <String, String>{
    for (final e in _documents.entries) e.key: _kindOf(decode(e.value)),
  };

  setUpAll(() async {
    if (!mirrored) return;
    await ContractRegistry.I.loadFromDirectory(_registryRoot);
    await MapperSections.I.loadDrafts(dir: _draftRoot, files: kDraftFiles);
  });

  test('реестр видов источника загружен и ветка default ровно одна', () {
    final reg = MapperSections.I.documents;
    expect(reg, isNotNull, reason: 'без реестра опознание осталось бы в коде');
    final defaults = reg!.sources.where((s) => s.isDefault).toList();
    expect(defaults, hasLength(1),
        reason: 'ровно одна ветка «всё остальное» на уровень');
  }, skip: skip);

  test('каждый документ опознаётся ОДНОЗНАЧНО (победитель по priority один)',
      () {
    final reg = MapperSections.I.documents!;
    final bad = <String>[];
    for (final e in _documents.entries) {
      final hits = reg.matchAll(e.value);
      if (hits.isEmpty) {

        final m = reg.detect(e.value, unwrappers: const {});
        if (m != null && m.source.isDefault) continue;
        bad.add('${e.key}: не опознан ни одной веткой');
        continue;
      }





      final best = hits.map((s) => s.priority).reduce((a, b) => a < b ? a : b);
      final winners = hits.where((s) => s.priority == best).toList();
      if (winners.length > 1) {
        bad.add('${e.key}: ничья priority=$best между '
            '${winners.map((s) => s.kind).join(", ")}');
      }
    }
    expect(bad, isEmpty,
        reason: 'неоднозначное опознание — тот же сниффер, только в данных:\n'
            '${bad.join("\n")}');
  }, skip: skip);







  test('запасные ветки совпадают с реестровыми по mapper и elements', () {
    final registry = MapperSections.I.documents!;
    final byKind = {for (final s in registry.sources) s.kind: s};
    final diffs = <String>[];
    for (final f in kFallbackDocumentSources) {
      final s = byKind[f.kind];


      if (s == null) {
        if (f.mapper != null) {
          diffs.add('${f.kind}: даёт узлы, а ветки в реестре нет');
        }
        continue;
      }
      if (f.mapper != s.mapper) {
        diffs.add('${f.kind}: mapper ${f.mapper} против ${s.mapper}');
      }
      if (f.elements != s.elements) {
        diffs.add('${f.kind}: elements ${f.elements} против ${s.elements}');
      }
    }
    expect(diffs, isEmpty, reason: diffs.join('\n'));
  }, skip: skip);

  test('реестр даёт ТУ ЖЕ форму, что прежний рукописный порядок', () {
    final diffs = <String>[];
    for (final e in _documents.entries) {
      final now = _kindOf(decode(e.value));
      if (now != legacy[e.key]) {
        diffs.add('${e.key}: было ${legacy[e.key]}, стало $now');
      }
    }
    expect(diffs, isEmpty, reason: diffs.join('\n'));
  }, skip: skip);

  test('вложенная оболочка: base64 от base64 снимается до предела глубины',
      () {
    const inner = 'trojan://pw@h.example:443#a';
    final once = base64.encode(utf8.encode(inner));
    final twice = base64.encode(utf8.encode(once));
    expect(_kindOf(decode(once)), 'UriLines(1,0)');
    expect((decode(once) as UriLines).lines.single, inner);
    expect((decode(twice) as UriLines).lines.single, inner);
  }, skip: skip);





  group('обход элементов объявлен реестром', () {
    test('у каждой ветки с mapper объявлен путь к элементам', () {
      final registry = MapperSections.I.documents!;
      for (final s in registry.sources) {
        if (s.mapper == null) continue;
        expect(s.elements, isNotNull,
            reason: '${s.kind}: вид даёт узлы, а где они лежат — не сказано');
      }
    }, skip: skip);

    test('грамматика elements разбирается движком, а не кодом разбора', () {



      const cfg = {
        'outbounds': [
          {'type': 'trojan'},
        ],
      };
      expect(DocumentRegistry.groupsFor('[].outbounds[]', [cfg]), [cfg],
          reason: 'каждый член корневого массива — самостоятельный конфиг');
      expect(DocumentRegistry.groupsFor('outbounds[]+endpoints[]', cfg), [cfg],
          reason: 'документ-объект и есть единственная группа');
      expect(
          DocumentRegistry.groupsFor(r'$self', {'type': 'trojan'}),
          [
            {
              'outbounds': [
                {'type': 'trojan'},
              ],
            },
          ],
          reason: 'документ сам себе элемент — одна группа с одним элементом');
      expect(
          DocumentRegistry.groupsFor('[]', [
            {'type': 'trojan'},
          ]),
          [
            {
              'outbounds': [
                {'type': 'trojan'},
              ],
            },
          ],
          reason: 'члены корневого массива принадлежат ОДНОМУ конфигу');


      expect(DocumentRegistry.groupsFor('[].outbounds[]', {'a': 1}), isNull);
      expect(DocumentRegistry.groupsFor(r'$self', [1, 2]), isNull);
    });
  });
}
