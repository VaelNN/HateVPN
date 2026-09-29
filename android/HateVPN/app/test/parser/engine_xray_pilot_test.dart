import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/node_spec.dart';
import 'package:lxbox/models/node_warning.dart';
import 'package:lxbox/models/template_vars.dart';
import 'package:lxbox/services/contract/registry.dart';
import 'package:lxbox/services/node_hash.dart';
import 'package:lxbox/services/parser/body_decoder.dart';
import 'package:lxbox/services/parser/engine/section_loader.dart';
import 'package:lxbox/services/parser/mappers/draft_sections.dart';
import 'package:lxbox/services/parser/parse_all.dart';












const _registryRoot = 'assets/contract';
const _draftRoot = 'assets/contract_draft';
const _identityFixture = 'test/fixtures/xray/pipeline_identity_before.json';










const Map<String, int> _droppedCountChanges = {
  'hysteria_v1_skipped': 1,
  'malformed_stream': 1,
  'unsupported_protocol': 1,
};









const Map<String, String> _genusBodyDeltas = {
  'balancer_group[1]':
      '{"tag":"bal","type":"urltest","outbounds":["bal proxy"],'
          '"url":"http://example.com","interval":"30s"}',
};

const Map<String, String> _expectedChanges = {
  'vless_ws_path_junk': 'битый путь снят с тела (format url_path), узел жив',
  'vless_encryption_junk': 'узел отбракован при разборе (drop_node §477)',










  'vless_default_port': 'delta480: дефолт 443 снят по арбитру Xray — было: '
      'узел на 443; стало: ноль узлов и одна отбраковка '
      '(server port is missing or out of range)',



  'vless_ws_ed_fields': 'delta533: плоские wsSettings.ed/eh больше НЕ читаются '
      '(кейс body/xray/vless_ws_ed_fields — прав корпус, реестр даёт '
      'json_field_unknown) — было: transport.max_early_data + '
      'early_data_header_name; стало: их нет',
  'b480_ws_ed_flat_only':
      'delta533: то же — плоские ed/eh сняты, узел остаётся ws без early data '
      '(кейс body/xray/ws_ed_flat_only)',
  'b480_ws_ed_path_tail_beats_flat':
      'delta533: то же — плоские ed/eh сняты, хвост пути читается как прежде '
      '(кейс body/xray/ws_ed_path_tail_beats_flat)',
  'b480_sockopt_keepalive_negative_interval':
      'delta533: пара idle: 30 + interval: -5 даёт tcp_keep_alive: 30s БЕЗ '
      'флага disable_tcp_keep_alive — наш флаг на этой паре был ошибкой '
      '(кейс body/xray/sockopt_keepalive_negative_interval)',




  'dialer_chain_vless_relay': 'delta560: tls.server_name не дописывается '
      'адресом — запись sni блока tls#xray (registry/tls.json) не объявляет '
      'default_from; корпус body/xray/dialer_chain_vless_relay ждёт '
      'tls: {enabled: true}',
  'multinode_310': 'delta560: то же у trojan без serverName '
      '(body/xray/multinode_310)',
  'b480_ws_eh_without_ed': 'delta560: то же (body/xray/ws_eh_without_ed)',
  'vmess_tls': 'delta560: alter_id: 0 в теле Xray-vmess — корпус '
      'body/xray/vmess_tls ждёт alter_id: 0',
  'vmess_security_junk': 'delta560: то же (body/xray/vmess_security_junk)',
};











const Map<String, String> _newCaseDeltas = {
  'b480_xhttp_full_field_set':
      'старый код терял transport.xmux целиком (5 полей из extra)',
  'b480_xhttp_snake_case_extra':
      'старый код терял transport.xmux (max_concurrency, h_keep_alive_period)',
  'b480_xhttp_splithttp_alias_full':
      'старый код терял transport.xmux (max_concurrency) под именем splithttp',
  'b480_xhttp_empty_extra_member_keeps_flat':
      'старый код терял transport.xmux; пустой член extra.xmux по-прежнему '
          'не затирает плоское значение',
};

Map<String, dynamic> _fixture() =>
    (jsonDecode(File(_identityFixture).readAsStringSync()) as Map)
        .cast<String, dynamic>();

List<NodeSpec> _parseText(String body, List<NodeWarning> dropped) =>
    parseAll(decode(body), dropped: dropped);

void main() {
  final mirrored = Directory('$_registryRoot/registry').existsSync();
  final skip = mirrored ? null : 'зеркало реестра не найдено';

  setUpAll(() async {
    if (!mirrored) return;
    await ContractRegistry.I.loadFromDirectory(_registryRoot);
    await MapperSections.I.loadDrafts(dir: _draftRoot, files: kDraftFiles);
  });

  test('секции вида источника xray исполняемы и загружены', () {


    expect(MapperSections.I.typesFor('xray'), isNotEmpty);
    for (final type in MapperSections.I.typesFor('xray')) {
      expect(MapperSections.I.has('xray', type), isTrue,
          reason: 'секция xray/$type не исполняема');
    }
  }, skip: skip);

  test('опознание элемента: ровно одна секция на кейс корпуса', () {
    final before = _fixture();
    final ambiguous = <String>[];
    for (final e in before.entries) {
      final want = (e.value as Map).cast<String, dynamic>();
      final doc = jsonDecode(want['input_json'] as String);
      for (final el in (doc as List)) {
        final outbounds = (el as Map)['outbounds'];
        if (outbounds is! List) continue;
        for (final o in outbounds) {
          if (o is! Map) continue;
          final obj = o.cast<String, dynamic>();
          final protocol = obj['protocol']?.toString() ?? '';


          if (const {'freedom', 'blackhole', 'dns', 'loopback'}
              .contains(protocol)) {
            continue;
          }
          final hits = MapperSections.I.matchJsonAll('xray', obj);
          if (hits.length > 1) {
            ambiguous.add('${e.key}: $protocol → '
                '${hits.map((s) => s.singboxType).join(", ")}');
          }
        }
      }
    }
    expect(ambiguous, isEmpty,
        reason: 'элемент обязан опознаваться РОВНО одной секцией');
  }, skip: skip);

  test('входы снимка: identity, тег, имя, rawSource и тело байт в байт', () {
    final before = _fixture();






    expect(before, hasLength(greaterThanOrEqualTo(45)));




    for (final e in _newCaseDeltas.entries) {
      final c = before[e.key];
      expect(c, isNotNull, reason: 'кейс ${e.key} пропал из снимка: ${e.value}');
      final body = ((c! as Map)['nodes'] as List).first as Map;
      expect(body['body_json'], contains('"xmux"'),
          reason: '${e.key}: ${e.value}');
    }

    final diffs = <String>[];
    for (final e in before.entries) {
      final name = e.key;
      if (_expectedChanges.containsKey(name)) continue;
      final want = (e.value as Map).cast<String, dynamic>();
      final wantNodes = (want['nodes'] as List).cast<Map>();
      final dropped = <NodeWarning>[];
      final got = _parseText(want['input_json'] as String, dropped);

      if (got.length != wantNodes.length) {
        diffs.add('$name: узлов ${got.length}, ожидалось ${wantNodes.length}');
        continue;
      }
      for (var i = 0; i < wantNodes.length; i++) {
        final w = wantNodes[i].cast<String, dynamic>();
        final n = got[i];
        final gotBody = jsonEncode(n.emit(TemplateVars.empty).map);
        final genusDelta = _genusBodyDeltas['$name[$i]'];
        if (gotBody != (genusDelta ?? w['body_json'])) {
          diffs.add('$name[$i] тело:\n  было  ${w['body_json']}\n'
              '  стало $gotBody');
        }
        if (n.tag != w['tag']) {
          diffs.add('$name[$i] тег: было ${w['tag']}, стало ${n.tag}');
        }
        if (n.label != w['label']) {
          diffs.add('$name[$i] имя: было ${w['label']}, стало ${n.label}');
        }
        if (n.rawSource != w['rawSource']) {
          diffs.add('$name[$i] rawSource разошёлся');
        }
        if (genusDelta == null && legacyNodeIdentityHash(n) != w['identity']) {
          diffs.add('$name[$i] identity сдвинулась');
        }
        final wantChain = w['chained'];
        if (wantChain == null) {
          if (n.chained != null) diffs.add('$name[$i] звено появилось');
        } else if (n.chained == null) {
          diffs.add('$name[$i] звено пропало');
        } else if (legacyNodeIdentityHash(n.chained!) !=
            (wantChain as Map)['identity']) {
          diffs.add('$name[$i] identity звена сдвинулась');
        }
      }
      final wantDropped = _droppedCountChanges[name] ?? want['dropped'];
      if (dropped.length != wantDropped) {
        diffs.add('$name: отбраковок ${dropped.length}, '
            'ожидалось $wantDropped');
      }
    }
    expect(diffs, isEmpty, reason: diffs.join('\n'));
  }, skip: skip);
}
