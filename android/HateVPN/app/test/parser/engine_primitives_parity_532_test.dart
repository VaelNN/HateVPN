










import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/node_spec.dart';
import 'package:lxbox/models/node_warning.dart';
import 'package:lxbox/services/contract/registry.dart';
import 'package:lxbox/services/parser/body_decoder.dart';
import 'package:lxbox/services/parser/engine/section_loader.dart';
import 'package:lxbox/services/parser/mappers/draft_sections.dart';
import 'package:lxbox/services/parser/parse_all.dart';

const _registryRoot = 'assets/contract';
const _draftRoot = 'assets/contract_draft';

List<NodeSpec> _parse(String body, List<NodeWarning> dropped) =>
    parseAll(decode(body), dropped: dropped);

void main() {
  final mirrored = Directory('$_registryRoot/registry').existsSync();
  final skip = mirrored ? null : 'зеркало реестра не найдено';

  setUpAll(() async {
    if (!mirrored) return;
    await ContractRegistry.I.loadFromDirectory(_registryRoot);
    await MapperSections.I.loadDrafts(dir: _draftRoot, files: kDraftFiles);
  });

  group('§532 дефект 1–2 · версия протокола во входе Xray', () {
    test('version: 3 узлом старшей версии НЕ становится', () {



      final dropped = <NodeWarning>[];
      final nodes = _parse(
        '[{"remarks":"hy3","outbounds":[{"tag":"proxy","protocol":"hysteria",'
        '"settings":{"address":"hy.example","port":443,"version":3},'
        '"streamSettings":{"hysteriaSettings":{"version":3,"auth":"pw"}}}]}]',
        dropped,
      );
      expect(
        nodes.where((n) => n.protocol == 'hysteria'),
        isEmpty,
        reason: 'версия 3 ни одной ветке detect не принадлежит',
      );
      expect(nodes, isEmpty);
    });








    test('version: 2 даёт узел hysteria2', () {
      final dropped = <NodeWarning>[];
      final nodes = _parse(
        '[{"remarks":"hy2","outbounds":[{"tag":"proxy","protocol":"hysteria",'
        '"settings":{"address":"hy.example","port":443,"version":2},'
        '"streamSettings":{"hysteriaSettings":{"version":2,"auth":"pw"}}}]}]',
        dropped,
      );
      expect(nodes.map((n) => n.protocol), ['hysteria2']);
    });
  }, skip: skip);

  group('§532 дефект 2 · streamSettings и форма элемента', () {







    test('МУСОРНЫЙ тип streamSettings — узла нет (битая запись)', () {



      final dropped = <NodeWarning>[];
      final nodes = _parse(
        '[{"remarks":"tj","outbounds":[{"tag":"proxy","protocol":"trojan",'
        '"settings":{"servers":[{"address":"tj.example","port":443,'
        '"password":"pw"}]},"streamSettings":"none"}]}]',
        dropped,
      );
      expect(nodes, isEmpty);
    });
  }, skip: skip);

  group('§532 дефект 4 · булев на выходе без emit_as', () {
    test('необъявленный булев уезжает СЛОВОМ, как у эталона', () {



      final dropped = <NodeWarning>[];
      final nodes = _parse(
        'tuic://11111111-1111-1111-1111-111111111111:pass123@example-1.com:443'
        '?reduce_rtt=1&sni=example-1.com#w',
        dropped,
      );
      expect(nodes, hasLength(1));
      expect((nodes.single as TuicSpec).zeroRtt, isTrue);
      final uri = nodes.single.toUri();
      expect(uri, contains('reduce_rtt=true'));
      expect(uri, isNot(contains('reduce_rtt=1')));
    });

    test('ложь не пишется вовсе — «параметра нет» и есть её написание', () {
      final dropped = <NodeWarning>[];
      final nodes = _parse(
        'tuic://11111111-1111-1111-1111-111111111111:pass123@example-1.com:443'
        '?reduce_rtt=0&sni=example-1.com#w',
        dropped,
      );
      expect(nodes, hasLength(1));
      final uri = nodes.single.toUri();
      expect(uri, isNot(contains('reduce_rtt')));
    });
  }, skip: skip);
}
