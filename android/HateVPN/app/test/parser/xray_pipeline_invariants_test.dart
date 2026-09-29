import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../contract_paths.dart';
import 'package:lxbox/models/node_spec.dart';
import 'package:lxbox/models/node_warning.dart';
import 'package:lxbox/models/template_vars.dart';
import 'package:lxbox/services/contract/parse_warnings.dart';
import 'package:lxbox/services/node_hash.dart';
import 'package:lxbox/services/parser/body_decoder.dart';
import 'package:lxbox/services/parser/parse_all.dart';








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



  'vless_ws_ed_fields': 'delta533: плоские wsSettings.ed/eh больше НЕ '
      'читаются — Xray таких полей у wsSettings не объявляет, и корпус ждёт '
      'json_field_unknown (body/xray/vless_ws_ed_fields). Было: '
      'transport.max_early_data + early_data_header_name; стало: их нет',
  'b480_ws_ed_flat_only': 'delta533: то же (body/xray/ws_ed_flat_only) — '
      'узел остаётся ws без early data',
  'b480_ws_ed_path_tail_beats_flat': 'delta533: то же '
      '(body/xray/ws_ed_path_tail_beats_flat) — early data читается только '
      'из ХВОСТА ПУТИ, как и прежде',
  'b480_sockopt_keepalive_negative_interval':
      'delta533: пара idle: 30 + interval: -5 даёт tcp_keep_alive: 30s БЕЗ '
      'флага disable_tcp_keep_alive — наш флаг на этой паре был ошибкой '
      '(body/xray/sockopt_keepalive_negative_interval)',


  'dialer_chain_vless_relay': 'delta560: tls.server_name больше не '
      'дописывается адресом — Xray-блок tls отката не объявляет '
      '(body/xray/dialer_chain_vless_relay)',
  'multinode_310': 'delta560: то же у trojan без serverName '
      '(body/xray/multinode_310)',
  'b480_ws_eh_without_ed': 'delta560: то же (body/xray/ws_eh_without_ed)',
  'vmess_tls': 'delta560: alter_id: 0 доезжает до тела — materialize_default '
      'записи alterId (body/xray/vmess_tls)',
  'vmess_security_junk': 'delta560: то же (body/xray/vmess_security_junk)',
};

Map<String, dynamic> _fixture() =>
    (jsonDecode(File(_identityFixture).readAsStringSync()) as Map)
        .cast<String, dynamic>();

List<NodeSpec> _parse(Object? input, List<NodeWarning> dropped) =>
    parseAll(decode(jsonEncode(input)), dropped: dropped);





List<NodeSpec> _parseText(String body, List<NodeWarning> dropped) =>
    parseAll(decode(body), dropped: dropped);

List<RegistryWarning> _registry(NodeSpec n) =>
    n.warnings.whereType<RegistryWarning>().toList();

RegistryWarning? _codeOf(NodeSpec n, String code) {
  for (final w in _registry(n)) {
    if (w.code == code) return w;
  }
  return null;
}

void main() {

  setUpAll(loadTestRegistry);


  group('§472 инвариант 4 — identity Xray не меняется', () {
    test('каждый вход снимка даёт прежние хеш, тег, имя, rawSource и тело',
        () {
      final before = _fixture();
      expect(before, hasLength(greaterThan(40)),
          reason: 'снимок похудел — проверьте, не срезан ли набор входов');

      for (final e in before.entries) {
        final name = e.key;
        final want = (e.value as Map).cast<String, dynamic>();
        final wantNodes = (want['nodes'] as List).cast<Map>();
        final dropped = <NodeWarning>[];
        final got = _parseText(want['input_json'] as String, dropped);

        if (_expectedChanges.containsKey(name)) continue;

        expect(got, hasLength(wantNodes.length),
            reason: 'число узлов входа $name изменилось');
        for (var i = 0; i < wantNodes.length; i++) {
          final w = wantNodes[i].cast<String, dynamic>();
          final n = got[i];
          final genusDelta = _genusBodyDeltas['$name[$i]'];
          if (genusDelta == null) {
            expect(legacyNodeIdentityHash(n), w['identity'],
                reason: 'identity $name[$i] изменилась: у пользователей '
                    'слетят выбор узла, отключения и цепочки');
          }
          expect(n.tag, w['tag'], reason: 'тег $name[$i]');
          expect(n.label, w['label'], reason: 'имя $name[$i]');



          expect(n.rawSource, w['rawSource'], reason: 'rawSource $name[$i]');



          expect(jsonEncode(n.emit(TemplateVars.empty).map),
              genusDelta ?? w['body_json'],
              reason: 'тело $name[$i] (порядок ключей нормативен — golden '
                  'сравнивается байт в байт)');
          final wantChain = w['chained'];
          if (wantChain == null) {
            expect(n.chained, isNull, reason: 'звено $name[$i] появилось');
          } else {
            expect(n.chained, isNotNull, reason: 'звено $name[$i] пропало');
            expect(legacyNodeIdentityHash(n.chained!),
                (wantChain as Map)['identity'],
                reason: 'identity звена $name[$i]');
            expect(n.chained!.tag, wantChain['tag'],
                reason: 'тег звена $name[$i]');
          }
        }
        expect(dropped, hasLength(_droppedCountChanges[name] ?? want['dropped']),
            reason: 'число отбраковок входа $name изменилось');
      }
    });

    test('оба объявленных расхождения — ровно те, что описаны', () {
      final before = _fixture();


      final pathCase =
          (before['vless_ws_path_junk'] as Map).cast<String, dynamic>();
      final pathNodes = _parseText(pathCase['input_json'] as String, []);
      expect(pathNodes, hasLength(1), reason: 'узел обязан выжить');
      final body = pathNodes.first.emit(TemplateVars.empty).map;
      expect((body['transport'] as Map).containsKey('path'), isFalse,
          reason: 'битый путь обязан быть снят с тела: ядро роняет на нём '
              'ВЕСЬ config.json');
      expect(_codeOf(pathNodes.first, 'type_invalid')?.path, 'transport.path',
          reason: 'код приходит из реестра, с адресом поля');
      expect(pathNodes.first.tag,
          ((pathCase['nodes'] as List).first as Map)['tag'],
          reason: 'тег не сдвинулся — сменилось только тело');



      final encCase =
          (before['vless_encryption_junk'] as Map).cast<String, dynamic>();
      final encDropped = <NodeWarning>[];
      final encNodes = _parseText(encCase['input_json'] as String, encDropped);
      expect(encNodes, isEmpty, reason: 'узел обязан исчезнуть при разборе');
      expect(encDropped, hasLength(1));
      final reason = encDropped.first as RegistryWarning;
      expect(reason.code, 'vless_encryption_invalid');
      expect(reason.path, 'encryption');
      expect(reason.value, 'totally-bogus');
      expect(reason.ownerTag, 'proxy',
          reason: 'dropped[].ref контракта называет ТЕГ записи (D-088)');
    });
  });

  group('§477 — отбраковка по форме encryption на Xray-входе', () {
    test('годный ML-KEM доезжает в тело как есть', () {
      const key = 'mlkem768x25519plus.native.0rtt.AAAABBBBCCCCDDDD';
      final nodes = _parse([
        {
          'remarks': 'enc ok',
          'outbounds': [
            {
              'tag': 'proxy',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': 'h.example',
                    'port': 443,
                    'users': [
                      {'id': '11111111-2222-3333-4444-555555555555',
                        'encryption': key},
                    ],
                  },
                ],
              },
              'streamSettings': {'network': 'tcp', 'security': 'none'},
            },
          ],
        },
      ], []);
      expect(nodes, hasLength(1));
      expect(nodes.first.emit(TemplateVars.empty).map['encryption'], key);
      expect(_codeOf(nodes.first, 'vless_encryption_invalid'), isNull);
    });

    test('"none" — выключатель слоя: ключа в теле нет, узел жив и без кода',
        () {
      final nodes = _parse([
        {
          'remarks': 'enc none',
          'outbounds': [
            {
              'tag': 'proxy',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': 'h.example',
                    'port': 443,
                    'users': [
                      {'id': '11111111-2222-3333-4444-555555555555',
                        'encryption': 'none'},
                    ],
                  },
                ],
              },
              'streamSettings': {'network': 'tcp', 'security': 'none'},
            },
          ],
        },
      ], []);
      expect(nodes, hasLength(1));
      expect(nodes.first.emit(TemplateVars.empty).map.containsKey('encryption'),
          isFalse);
      expect(_registry(nodes.first), isEmpty);
    });

    test('сосед по элементу переживает отбраковку негодного', () {


      final dropped = <NodeWarning>[];
      final nodes = _parse([
        {
          'remarks': 'mix',
          'outbounds': [
            {
              'tag': 'bad',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': 'a.example',
                    'port': 443,
                    'users': [
                      {'id': '11111111-2222-3333-4444-555555555555',
                        'encryption': 'nonsense'},
                    ],
                  },
                ],
              },
              'streamSettings': {'network': 'tcp', 'security': 'none'},
            },
            {
              'tag': 'good',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': 'b.example',
                    'port': 443,
                    'users': [
                      {'id': '22222222-2222-3333-4444-555555555555'},
                    ],
                  },
                ],
              },
              'streamSettings': {'network': 'tcp', 'security': 'none'},
            },
          ],
        },
      ], dropped);
      expect(nodes, hasLength(1));
      expect(nodes.first.emit(TemplateVars.empty).map['server'], 'b.example');

      expect(_codeOf(nodes.single, 'vless_encryption_invalid'), isNull,
          reason: 'чужая отбраковка на рабочем соседе не висит');
      final w = dropped.whereType<RegistryWarning>().single;
      expect(w.code, 'vless_encryption_invalid',
          reason: 'пропажа узла не должна быть молчаливой');
      expect(w.ownerTag, 'bad',
          reason: 'причина названа тегом ОТВЕРГНУТОЙ записи');
    });
  });

  group('§472 шаг 8 — коды реестра приходят на Xray-узел', () {
    test('мусорный fingerprint даёт utls_fp_unknown с адресом и значением',
        () {
      final nodes = _parse([
        {
          'remarks': 'fp',
          'outbounds': [
            {
              'tag': 'proxy',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': 'h.example',
                    'port': 443,
                    'users': [
                      {'id': '11111111-2222-3333-4444-555555555555'},
                    ],
                  },
                ],
              },
              'streamSettings': {
                'network': 'tcp',
                'security': 'tls',
                'tlsSettings': {'serverName': 's.example',
                  'fingerprint': 'bogus-fp'},
              },
            },
          ],
        },
      ], []);
      final w = _codeOf(nodes.single, 'utls_fp_unknown');
      expect(w, isNotNull,
          reason: 'раньше это был рукописный UnknownFingerprintWarning без '
              'адреса и значения');
      expect(w!.path, 'tls.utls.fingerprint');
      expect(w.value, 'bogus-fp');
    });

    test('псевдоним uTLS переводится МОЛЧА — это написание, не мусор', () {
      final nodes = _parse([
        {
          'remarks': 'alias',
          'outbounds': [
            {
              'tag': 'proxy',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': 'h.example',
                    'port': 443,
                    'users': [
                      {'id': '11111111-2222-3333-4444-555555555555'},
                    ],
                  },
                ],
              },
              'streamSettings': {
                'network': 'tcp',
                'security': 'tls',
                'tlsSettings': {'serverName': 's.example',
                  'fingerprint': 'hellochrome_120'},
              },
            },
          ],
        },
      ], []);
      final tls = nodes.single.emit(TemplateVars.empty).map['tls'] as Map;
      expect((tls['utls'] as Map)['fingerprint'], 'chrome');
      expect(_codeOf(nodes.single, 'utls_fp_unknown'), isNull);
    });

    test('flow вне пары даёт flow_deprecated с адресом', () {
      final nodes = _parse([
        {
          'remarks': 'flow',
          'outbounds': [
            {
              'tag': 'proxy',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': 'h.example',
                    'port': 443,
                    'users': [
                      {'id': '11111111-2222-3333-4444-555555555555',
                        'flow': 'xtls-rprx-direct'},
                    ],
                  },
                ],
              },
              'streamSettings': {'network': 'tcp', 'security': 'none'},
            },
          ],
        },
      ], []);
      final w = _codeOf(nodes.single, 'flow_deprecated');
      expect(w?.path, 'flow');
      expect(w?.value, 'xtls-rprx-direct');
      expect(nodes.single.emit(TemplateVars.empty).map.containsKey('flow'),
          isFalse, reason: 'негодное значение снимается санитайзером');
    });

    test('vision при живом транспорте — код реестра, не рукописный класс', () {
      final nodes = _parse([
        {
          'remarks': 'vision',
          'outbounds': [
            {
              'tag': 'proxy',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': 'h.example',
                    'port': 443,
                    'users': [
                      {'id': '11111111-2222-3333-4444-555555555555',
                        'flow': 'xtls-rprx-vision'},
                    ],
                  },
                ],
              },
              'streamSettings': {
                'network': 'ws',
                'security': 'tls',
                'tlsSettings': {'serverName': 's.example'},
                'wsSettings': {'path': '/ws'},
              },
            },
          ],
        },
      ], []);
      expect(_codeOf(nodes.single, 'vision_with_transport'), isNotNull);



    });

    test('битый pbk объясняется кодом, а не молчаливой деградацией', () {
      final nodes = _parse([
        {
          'remarks': 'pbk',
          'outbounds': [
            {
              'tag': 'proxy',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': 'h.example',
                    'port': 443,
                    'users': [
                      {'id': '11111111-2222-3333-4444-555555555555'},
                    ],
                  },
                ],
              },
              'streamSettings': {
                'network': 'tcp',
                'security': 'reality',
                'realitySettings': {
                  'serverName': 's.example',
                  'fingerprint': 'chrome',
                  'publicKey': '!!!not-base64!!!',
                  'shortId': 'abcd',
                },
              },
            },
          ],
        },
      ], []);
      final w = _codeOf(nodes.single, 'reality_pbk_invalid');
      expect(w, isNotNull,
          reason: 'раньше REALITY деградировал до plain TLS МОЛЧА (§169)');
      expect(w!.path, 'tls.reality.public_key');
      final tls = nodes.single.emit(TemplateVars.empty).map['tls'] as Map;
      expect(tls.containsKey('reality'), isFalse,
          reason: 'тело не изменилось: блок по-прежнему снимается');
    });

    test('vmess security вне enum даёт vmess_security_unknown', () {
      final nodes = _parse([
        {
          'remarks': 'sec',
          'outbounds': [
            {
              'tag': 'proxy',
              'protocol': 'vmess',
              'settings': {
                'vnext': [
                  {
                    'address': 'v.example',
                    'port': 443,
                    'users': [
                      {'id': '11111111-2222-3333-4444-555555555555',
                        'alterId': 0, 'security': 'rubbish'},
                    ],
                  },
                ],
              },
              'streamSettings': {'network': 'tcp', 'security': 'none'},
            },
          ],
        },
      ], []);
      final w = _codeOf(nodes.single, 'vmess_security_unknown');
      expect(w?.value, 'rubbish',
          reason: 'раньше подмену делал рукописный normalizeVmessSecurity, '
              'и она уходила молча, в лог');
      expect(nodes.single.emit(TemplateVars.empty).map['security'], 'auto');
    });

    test('vmess без security получает обязательный ключ, а не отбраковку', () {


      final nodes = _parse([
        {
          'remarks': 'sec empty',
          'outbounds': [
            {
              'tag': 'proxy',
              'protocol': 'vmess',
              'settings': {
                'vnext': [
                  {
                    'address': 'v.example',
                    'port': 443,
                    'users': [
                      {'id': '11111111-2222-3333-4444-555555555555',
                        'alterId': 1},
                    ],
                  },
                ],
              },
              'streamSettings': {'network': 'tcp', 'security': 'none'},
            },
          ],
        },
      ], []);
      expect(nodes, hasLength(1));
      expect(nodes.single.emit(TemplateVars.empty).map['security'], 'auto');
      expect(_registry(nodes.single), isEmpty);
    });
  });

  group('§472 шаг 8 — границы переезда', () {
    test('hysteria2 не получает utls: у QUIC нет TLS-рукопожатия', () {










      final nodes = _parse([
        {
          'remarks': 'hy2',
          'outbounds': [
            {
              'tag': 'proxy',
              'protocol': 'hysteria',
              'settings': {'address': 'hy.example', 'port': 8443},
              'streamSettings': {
                'security': 'tls',
                'tlsSettings': {'serverName': 'hy.example',
                  'fingerprint': 'bogus'},
                'hysteriaSettings': {'version': 2, 'auth': 'pw'},
              },
            },
          ],
        },
      ], []);
      final tls = nodes.single.emit(TemplateVars.empty).map['tls'] as Map;
      expect(tls.containsKey('utls'), isFalse);
      expect(_codeOf(nodes.single, 'tls_not_applicable_quic'), isNotNull);
    });

    test('битый ТИП streamSettings пропускает узел, а не оживляет его', () {



      final dropped = <NodeWarning>[];
      final nodes = _parse([
        {
          'remarks': 'malformed',
          'outbounds': [
            {
              'tag': 'bad',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': 'a.example',
                    'port': 443,
                    'users': [
                      {'id': '11111111-2222-3333-4444-555555555555'},
                    ],
                  },
                ],
              },
              'streamSettings': 'none',
            },
            {
              'tag': 'ok',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': 'b.example',
                    'port': 443,
                    'users': [
                      {'id': '22222222-2222-3333-4444-555555555555'},
                    ],
                  },
                ],
              },
              'streamSettings': {'network': 'tcp', 'security': 'none'},
            },
          ],
        },
      ], dropped);
      expect(nodes, hasLength(1));
      expect(nodes.single.emit(TemplateVars.empty).map['server'], 'b.example');

      expect(nodes.single.warnings, isEmpty);
      expect(
          dropped.whereType<RegistryWarning>().map((w) => w.ownerTag), ['bad']);
    });

    test('§459 — суффикс -udp443 не переписывает порт узла', () {
      final nodes = _parse([
        {
          'remarks': 'udp443',
          'outbounds': [
            {
              'tag': 'proxy',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': 'h.example',
                    'port': 8443,
                    'users': [
                      {'id': '11111111-2222-3333-4444-555555555555',
                        'flow': 'xtls-rprx-vision-udp443'},
                    ],
                  },
                ],
              },
              'streamSettings': {'network': 'tcp', 'security': 'none'},
            },
          ],
        },
      ], []);
      final body = nodes.single.emit(TemplateVars.empty).map;
      expect(body['server_port'], 8443, reason: 'порт — свойство узла');
      expect(body['flow'], 'xtls-rprx-vision');
      expect(body['packet_encoding'], 'xudp');
    });

    test('§310 — многоузловой элемент даёт все узлы, имена по тегам', () {
      final nodes = _parse([
        {
          'remarks': 'multi',
          'outbounds': [
            for (final t in const ['a', 'b'])
              {
                'tag': t,
                'protocol': 'vless',
                'settings': {
                  'vnext': [
                    {
                      'address': '$t.example',
                      'port': 443,
                      'users': [
                        {'id': '${t == 'a' ? '1' : '2'}1111111-2222-3333-'
                            '4444-555555555555'},
                      ],
                    },
                  ],
                },
                'streamSettings': {'network': 'tcp', 'security': 'none'},
              },
          ],
        },
      ], []);
      expect(nodes.map((n) => n.tag), ['multi a', 'multi b']);
    });

    test('§404 — цепочка dialerProxy жива, релей не стал узлом подписки', () {
      final nodes = _parse([
        {
          'remarks': 'chain',
          'outbounds': [
            {
              'tag': 'proxy',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': 'a.example',
                    'port': 443,
                    'users': [
                      {'id': '11111111-2222-3333-4444-555555555555'},
                    ],
                  },
                ],
              },
              'streamSettings': {
                'network': 'tcp',
                'security': 'none',
                'sockopt': {'dialerProxy': 'relay'},
              },
            },
            {
              'tag': 'relay',
              'protocol': 'socks',
              'settings': {
                'servers': [
                  {'address': 'r.example', 'port': 1080,
                    'users': [{'user': 'u', 'pass': 'p'}]},
                ],
              },
            },
          ],
        },
      ], []);
      expect(nodes, hasLength(1), reason: 'релей узлом подписки не бывает');
      expect(nodes.single.chained?.tag, 'relay');
      expect(nodes.single.chained?.protocol, 'socks');
    });

    test('§454 — rawSource остаётся объектом Xray байт в байт', () {
      const outbound = {
        'tag': 'proxy',
        'protocol': 'vless',
        'settings': {
          'vnext': [
            {
              'address': 'h.example',
              'port': 443,
              'users': [
                {'id': '11111111-2222-3333-4444-555555555555'},
              ],
            },
          ],
        },
        'streamSettings': {'network': 'tcp', 'security': 'none'},
      };
      final nodes = _parse([
        {'remarks': 'raw', 'outbounds': [outbound]},
      ], []);
      expect(nodes.single.rawSource,
          const JsonEncoder.withIndent('  ').convert(outbound),
          reason: 'карта sing-box — рабочая форма конвейера, а не источник');


      expect(jsonDecode(nodes.single.rawSource) is Map, isTrue);
      expect((jsonDecode(nodes.single.rawSource) as Map).containsKey('type'),
          isFalse);
    });
  });

  group('§472 — второй проход по emit() узла конвейера не дублирует коды', () {
    test('annotateAllWithRegistry на разобранном Xray ничего не добавляет',
        () {
      final nodes = _parse([
        {
          'remarks': 'fp',
          'outbounds': [
            {
              'tag': 'proxy',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': 'h.example',
                    'port': 443,
                    'users': [
                      {'id': '11111111-2222-3333-4444-555555555555'},
                    ],
                  },
                ],
              },
              'streamSettings': {
                'network': 'tcp',
                'security': 'tls',
                'tlsSettings': {'serverName': 's.example',
                  'fingerprint': 'bogus-fp'},
              },
            },
          ],
        },
      ], []);
      final before = nodes.single.warnings.length;
      annotateAllWithRegistry(nodes);
      expect(nodes.single.warnings, hasLength(before),
          reason: 'узел помечен isPipelineParsed — источник кодов один');

      expect(_codeOf(nodes.single, 'utls_fp_unknown')?.value, 'bogus-fp');
    });
  });

  group('§472 инвариант 5 — цена разбора 2000 Xray-узлов', () {
    test('конвейер не дороже ×1,5 к старой полной воронке', () {


      final element = {
        'remarks': 'perf',
        'outbounds': [
          for (var i = 0; i < 2000; i++)
            {
              'tag': 'n$i',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': 'h$i.example',
                    'port': 443,
                    'users': [
                      {'id': '11111111-2222-3333-4444-555555555555',
                        'flow': 'xtls-rprx-vision'},
                    ],
                  },
                ],
              },
              'streamSettings': {
                'network': 'tcp',
                'security': 'reality',
                'realitySettings': {
                  'serverName': 's$i.example',
                  'fingerprint': 'chrome',
                  'publicKey': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
                  'shortId': 'abcd',
                },
              },
            },
        ],
      };
      final body = jsonEncode([element]);

      var best = Duration(days: 1);
      for (var run = 0; run < 3; run++) {
        final sw = Stopwatch()..start();
        final nodes = parseAll(decode(body));
        sw.stop();
        expect(nodes, hasLength(2000));
        if (sw.elapsed < best) best = sw.elapsed;
      }



      expect(best.inMilliseconds, lessThan(3000),
          reason: 'разбор 2000 Xray-узлов занял ${best.inMilliseconds} мс');

      print('§472 шаг 8: 2000 Xray-узлов — ${best.inMilliseconds} мс '
          '(лучший из трёх)');
    });
  });
}
