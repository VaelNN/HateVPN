import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/node_spec.dart';
import 'package:lxbox/models/node_warning.dart';
import 'package:lxbox/models/template_vars.dart';
import 'package:lxbox/services/contract/warning_codes.dart';
import 'package:lxbox/services/parser/body_decoder.dart';
import 'package:lxbox/services/parser/parse_all.dart';
import 'package:lxbox/services/parser/uri_parsers.dart';

import 'engine_test_setup.dart';









const _uuid = '11111111-1111-1111-1111-111111111111';

String? _codeOf(NodeWarning w) => warningCodeOf(w);

Set<String> _codes(Iterable<NodeWarning> ws) =>
    {for (final w in ws) _codeOf(w) ?? w.runtimeType.toString()};


String _xrayBody(Map<String, dynamic> outbound) {
  final o = <String, dynamic>{'tag': 'proxy', ...outbound};
  return '[{"remarks":"t","outbounds":[${_json(o)}]}]';
}

String _json(Object? v) => switch (v) {
      final Map<String, dynamic> m =>
        '{${m.entries.map((e) => '"${e.key}":${_json(e.value)}').join(',')}}',
      final List<dynamic> l => '[${l.map(_json).join(',')}]',
      final String s => '"$s"',
      null => 'null',
      _ => '$v',
    };


Map<String, dynamic> _vlessSettings() => {
      'protocol': 'vless',
      'settings': {
        'vnext': [
          {
            'address': 'a.example',
            'port': 443,
            'users': [
              {'id': _uuid, 'encryption': 'none'},
            ],
          },
        ],
      },
    };

void main() {
  setUpAll(loadEngineSections);


  group('3a — `on_invalid: drop transport_unsupported` ИСПОЛНЯЕТСЯ', () {




    for (final network in const ['kcp', 'quic']) {
      test('Xray-JSON `network: $network` → узла нет, код назван', () {
        final dropped = <NodeWarning>[];
        final nodes = parseAll(
          decode(_xrayBody({
            ..._vlessSettings(),
            'streamSettings': {'network': network, 'security': 'none'},
          })),
          dropped: dropped,
        );

        expect(nodes, isEmpty,
            reason: 'сервер, который ждёт $network, plain-TCP не примет — '
                'узел обязан быть снят, а не уехать голым');
        expect(_codes(dropped), contains('transport_unsupported'),
            reason: 'отбраковка обязана быть НАЗВАННОЙ: молчаливое снятие — '
                'тот же дефект, что и молчаливая подмена');
      });
    }

    test('`allow` — законное имя таблицу ПРОХОДИТ и узел цел', () {


      for (final network in const ['ws', 'grpc', 'httpupgrade', 'xhttp']) {
        final dropped = <NodeWarning>[];
        final nodes = parseAll(
          decode(_xrayBody({
            ..._vlessSettings(),
            'streamSettings': {'network': network, 'security': 'none'},
          })),
          dropped: dropped,
        );
        expect(nodes, hasLength(1), reason: '$network — канон ядра, не мусор');
        expect(nodes.single.emit(const TemplateVars()).map['transport'],
            isA<Map<String, dynamic>>().having(
                (m) => m['type'], 'type', network));
      }
    });

    test('`tcp`/`raw`/пусто — отсутствие транспорта, а не мусор', () {
      for (final network in const ['tcp', 'raw', '']) {
        final nodes = parseAll(decode(_xrayBody({
          ..._vlessSettings(),
          'streamSettings': {'network': network, 'security': 'none'},
        })));
        expect(nodes, hasLength(1), reason: '«$network» = транспорта нет');
        expect(nodes.single.emit(const TemplateVars()).map['transport'], isNull);
      }
    });
  });


  group('3b — обфускация заголовком → отбраковка узла', () {



    test('URI `headerType=http` → узла нет, код `transport_header_unsupported`',
        () {
      final dropped = XrayDropVerdict();
      final node = parseUri(
        'vless://$_uuid@192.0.2.14:58387'
        '?encryption=none&type=raw&headerType=http&security=none#t',
        dropped: dropped,
      );
      expect(node, isNull,
          reason: 'узел выглядел рабочим и не работал: сервер, ждущий '
              'камуфляж, получал h2-рукопожатие и обрывал соединение');
      expect(_codeOf(dropped.reason!), 'transport_header_unsupported');
    });

    test('URI `type=http` прямым текстом — НАСТОЯЩИЙ H2, узел цел', () {


      final node = parseUri(
        'vless://$_uuid@192.0.2.14:443?encryption=none&type=http&security=tls'
        '&host=cdn.example#t',
      );
      expect(node, isNotNull);
      final tr = node!.emit(const TemplateVars()).map['transport']
          as Map<String, dynamic>?;
      expect(tr?['type'], 'http');
    });

    for (final spelling in const ['tcpSettings', 'rawSettings']) {
      test('Xray-JSON `$spelling.header.type = http` → узла нет', () {


        final dropped = <NodeWarning>[];
        final nodes = parseAll(
          decode(_xrayBody({
            ..._vlessSettings(),
            'streamSettings': {
              'network': 'tcp',
              'security': 'none',
              spelling: {
                'header': {'type': 'http'},
              },
            },
          })),
          dropped: dropped,
        );
        expect(nodes, isEmpty,
            reason: 'прежде форма терялась АБСОЛЮТНО МОЛЧА: узел собирался '
                'чистым TCP');
        expect(_codes(dropped), contains('transport_header_unsupported'));
      });
    }

    test('`header.type = none` — отсутствие обфускации, кода нет', () {
      final dropped = <NodeWarning>[];
      final nodes = parseAll(
        decode(_xrayBody({
          ..._vlessSettings(),
          'streamSettings': {
            'network': 'tcp',
            'security': 'none',
            'tcpSettings': {
              'header': {'type': 'none'},
            },
          },
        })),
        dropped: dropped,
      );
      expect(nodes, hasLength(1));
      expect(_codes(nodes.single.warnings),
          isNot(contains('transport_header_unsupported')));
    });
  });


  group('3c — неизвестный ключ ВНУТРИ объявленных контейнеров', () {



    test('лист внутри контейнера → info-код с ПОЛНЫМ путём', () {
      final nodes = parseAll(decode(_xrayBody({
        ..._vlessSettings(),
        'streamSettings': {
          'network': 'ws',
          'security': 'none',
          'wsSettings': {'path': '/x', 'zzzUnknown': 'v'},
        },
      })));
      expect(nodes, hasLength(1),
          reason: 'непрочитанный лист узел НЕ ломает — он лишь не доезжает');
      final w = nodes.single.warnings
          .where((w) => _codeOf(w) == 'json_field_unknown')
          .toList();
      expect(w.map((e) => (e as RegistryWarning).path),
          contains('streamSettings.wsSettings.zzzUnknown'));
    });

    test('контейнер-РОДИТЕЛЬ неизвестным не зовётся', () {



      final nodes = parseAll(decode(_xrayBody({
        ..._vlessSettings(),
        'streamSettings': {
          'network': 'ws',
          'security': 'none',
          'wsSettings': {'path': '/x'},
        },
      })));
      final paths = nodes.single.warnings
          .whereType<RegistryWarning>()
          .where((w) => w.code == 'json_field_unknown')
          .map((w) => w.path)
          .toSet();
      expect(paths, isNot(contains('streamSettings.wsSettings')));
      expect(paths, isNot(contains('streamSettings')));
    });

    test('`nested_quiet` — поддерево `sockopt` молчит целиком', () {

      final nodes = parseAll(decode(_xrayBody({
        ..._vlessSettings(),
        'streamSettings': {
          'network': 'tcp',
          'security': 'none',
          'sockopt': {'tcpNoDelay': true, 'zzzWhatever': 7},
        },
      })));
      final paths = nodes.single.warnings
          .whereType<RegistryWarning>()
          .where((w) => w.code == 'json_field_unknown')
          .map((w) => w.path)
          .toList();
      expect(paths.where((p) => p?.startsWith('streamSettings.sockopt') ?? false),
          isEmpty,
          reason: 'sockopt объявлен nested_quiet у всех девяти xray-секций');
    });

    test('путь-родитель: запись, читающая объект ЦЕЛИКОМ, читает и листья', () {


      final nodes = parseAll(decode(_xrayBody({
        ..._vlessSettings(),
        'streamSettings': {
          'network': 'ws',
          'security': 'none',
          'wsSettings': {
            'path': '/x',
            'headers': {'Host': 'cdn.example', 'X-Anything': 'v'},
          },
        },
      })));
      final paths = nodes.single.warnings
          .whereType<RegistryWarning>()
          .where((w) => w.code == 'json_field_unknown')
          .map((w) => w.path)
          .toList();
      expect(paths.where((p) => p?.contains('headers') ?? false), isEmpty);
    });
  });


  group('3d — баннер-обманка панели опознаётся по ЦЕЛИ', () {


    test('`vless://…@0.0.0.0:1#expired` среди строк → узла нет, info-код', () {
      final body = [
        'vless://$_uuid@example-1.com:443?encryption=none&security=none#node-a',
        'vless://00000000-0000-0000-0000-000000000000@0.0.0.0:1'
            '?encryption=none&security=none#%E2%9A%A0%20Subscription%20expired',
      ].join('\n');
      final dropped = <NodeWarning>[];
      final nodes = parseAll(decode(body), dropped: dropped);

      expect(nodes, hasLength(1), reason: 'сосед обязан остаться на месте');
      expect(nodes.single.server, 'example-1.com');
      expect(_codes(dropped), contains('provider_banner_link'));
    });

    test('баннер ЕДИНСТВЕННОЙ записью тела: узлов нет, причина названа', () {


      final dropped = <NodeWarning>[];
      final nodes = parseAll(
        decode('socks://127.0.0.1:1080#Subscription%20expired'),
        dropped: dropped,
      );
      expect(nodes, isEmpty);
      expect(_codes(dropped), contains('provider_banner_link'));
    });

    test('ремарка после `#` доживает до человека сообщением провайдера', () {

      final dropped = XrayDropVerdict();
      final node = parseUri('socks://127.0.0.1:1080#Traffic%20limit%20reached',
          dropped: dropped);
      expect(node, isNull);
      final w = dropped.reason!;
      expect(w.code, 'provider_banner_link');
      expect(w.params['message'], 'Traffic limit reached');
    });

    test('ПОРТ признаком НЕ является — судится только адрес', () {

      for (final target in const ['0.0.0.0', '127.0.0.1', '[::1]', 'localhost']) {
        expect(parseUri('socks://$target:1080#x'), isNull,
            reason: '$target сервером не бывает ни при какой схеме');
      }

      expect(parseUri('socks://example-1.com:1#x'), isNotNull,
          reason: 'порт 1 сам по себе баннера не доказывает');
    });
  });


  group('3e — socks `decode_requires_separator`', () {

    test('base64(«user:pass») — пароль больше НЕ теряется', () {


      final node = parseUri(
          'socks5://dGVzdHVzZXI6dGVzdHBhc3MxMjM@example-1.com:1080#s5');
      final body = node!.emit(const TemplateVars()).map;
      expect(body['username'], 'testuser');
      expect(body['password'], 'testpass123');
    });

    test('пароль с двоеточием ВНУТРИ — `limit: 2` его ловит', () {
      final node = parseUri(
          'socks5://dGVzdHVzZXI6cGE6c3MxMjM@example-2.com:1080#s5c');
      final body = node!.emit(const TemplateVars()).map;
      expect(body['username'], 'testuser');
      expect(body['password'], 'pa:ss123');
    });

    test('ВТОРАЯ ПОЛОВИНА признака: открытое одиночное имя не ломается', () {


      final node = parseUri('socks4://useridonly@example-1.com:1080#s4');
      final body = node!.emit(const TemplateVars()).map;
      expect(body['username'], 'useridonly');
      expect(body['password'], isNull);
    });

    test('разделитель ВО ВХОДЕ снимает конвейер: форма открытая', () {
      final node = parseUri('socks5://user1:pass1@example-1.com:1080#open');
      final body = node!.emit(const TemplateVars()).map;
      expect(body['username'], 'user1');
      expect(body['password'], 'pass1');
    });
  });


  group('3f — слой `extra` у vmess приезжает УЖЕ ОБЪЕКТОМ', () {


    test('объект внутри контейнера: xmux и x_padding_bytes доезжают', () {

      const uri = 'vmess://eyJhZGQiOiAiZXhhbXBsZS0xLmNvbSIsICJhaWQiOiAiMCIsICJl'
          'eHRyYSI6IHsibm9HUlBDSGVhZGVyIjogdHJ1ZSwgInNjTWF4RWFjaFBvc3RCeXRlcyI6'
          'ICI4MDAwMDAiLCAieFBhZGRpbmdCeXRlcyI6ICIxMDAtMTAwMCIsICJ4bXV4IjogeyJo'
          'S2VlcEFsaXZlUGVyaW9kIjogNDUsICJtYXhDb25jdXJyZW5jeSI6ICI4LTE2In19LCAi'
          'aG9zdCI6ICJleGFtcGxlLTEuY29tIiwgImlkIjogIjExMTExMTExLTExMTEtMTExMS0x'
          'MTExLTExMTExMTExMTExMSIsICJuZXQiOiAieGh0dHAiLCAicGF0aCI6ICIveGh0dHAi'
          'LCAicG9ydCI6ICI0NDMiLCAicHMiOiAidm1lc3MtZXh0cmEteG11eCIsICJzY3kiOiAi'
          'YXV0byIsICJzbmkiOiAiZXhhbXBsZS0xLmNvbSIsICJ0bHMiOiAidGxzIiwgInR5cGUi'
          'OiAic3RyZWFtLW9uZSIsICJ2IjogIjIifQ==';
      final node = parseUri(uri);
      expect(node, isNotNull);
      final tr = node!.emit(const TemplateVars()).map['transport']
          as Map<String, dynamic>;
      expect(tr['x_padding_bytes'], '100-1000');
      expect(tr['sc_max_each_post_bytes'], '800000');
      expect(tr['xmux'], isA<Map<String, dynamic>>());
      expect((tr['xmux'] as Map)['max_concurrency'], '8-16');
    });

    test('ключ-НОСИТЕЛЬ слоя неизвестным не зовётся', () {


      const uri = 'vmess://eyJhZGQiOiAiZXhhbXBsZS0xLmNvbSIsICJhaWQiOiAiMCIsICJl'
          'eHRyYSI6IHsibm9HUlBDSGVhZGVyIjogdHJ1ZX0sICJpZCI6ICIxMTExMTExMS0xMTEx'
          'LTExMTEtMTExMS0xMTExMTExMTExMTEiLCAibmV0IjogInhodHRwIiwgInBvcnQiOiAi'
          'NDQzIiwgInBzIjogInQiLCAic2N5IjogImF1dG8iLCAidGxzIjogIiIsICJ2IjogIjIi'
          'fQ==';
      final node = parseUri(uri);
      final codes = _codes(node!.warnings);
      expect(codes, isNot(contains('uri_param_unknown')));
      expect(codes, isNot(contains('unknown_key')));
    });
  });


  group('3g — hysteria2 `up`/`down` через `bandwidth_mbps`', () {
    test('написание официального клиента + суффикс единицы', () {


      final node =
          parseUri('hysteria2://pw@example-1.com:443?up=100mbps&down=500#h2');
      final body = node!.emit(const TemplateVars()).map;
      expect(body['up_mbps'], 100);
      expect(body['down_mbps'], 500);
      expect(_codes(node.warnings), isNot(contains('uri_param_unknown')));
    });
  });


  group('3h — нестроковый элемент списка снимается ЭЛЕМЕНТОМ', () {






    String singboxOutbounds(List<Map<String, dynamic>> list) => _json(list);

    test('код ставится НА ЭЛЕМЕНТ, а поле остаётся', () {



      final nodes = parseAll(decode(singboxOutbounds([
        {
          'type': 'vless',
          'tag': 'alpn-mixed',
          'server': 'example-1.com',
          'server_port': 443,
          'uuid': _uuid,
          'tls': {
            'enabled': true,
            'server_name': 'example-1.com',
            'alpn': [443, 'h2'],
          },
        },
      ])));
      expect(nodes, hasLength(1), reason: 'узел остаётся — снят ЭЛЕМЕНТ');
      final codes = nodes.single.warnings.whereType<RegistryWarning>().toList();
      expect(codes.map((w) => w.code), contains('tls_alpn_item_invalid'));
      expect(codes.firstWhere((w) => w.code == 'tls_alpn_item_invalid').path,
          'tls.alpn[0]',
          reason: 'адрес кода — ЭЛЕМЕНТ по индексу, а не поле');
      expect(codes.map((w) => w.code), isNot(contains('type_invalid')),
          reason: 'норма 1.1.49, снимавшая поле целиком, ОТМЕНЕНА');
    });

    test('все элементы негодны — пустой остаток, и это НЕ `type_invalid`', () {


      final nodes = parseAll(decode(singboxOutbounds([
        {
          'type': 'vless',
          'tag': 'alpn-all-bad',
          'server': 'example-2.com',
          'server_port': 443,
          'uuid': _uuid,
          'tls': {
            'enabled': true,
            'server_name': 'example-2.com',
            'alpn': [443],
          },
        },
      ])));
      expect(nodes, hasLength(1));
      final codes = nodes.single.warnings
          .whereType<RegistryWarning>()
          .map((w) => w.code)
          .toList();
      expect(codes, contains('tls_alpn_item_invalid'));
      expect(codes, isNot(contains('type_invalid')));
    });
  });

  group('3i — `emit.userinfo.keep_empty_tail` ИСПОЛНЯЕТСЯ', () {

    test('socks4: разделитель пишется и при пустом пароле', () {
      final node = parseUri('socks4://userid1@example-1.com:1080#s4');
      expect(node!.toUri(), 'socks4://userid1:@example-1.com:1080#s4',
          reason: 'отсутствие `:` часть клиентов читает как «имени нет»');
    });

    test('круг: ссылка с `:@` возвращает тело БЕЗ пароля', () {
      final node = parseUri('socks4://userid1:@example-1.com:1080#s4');
      final body = node!.emit(const TemplateVars()).map;
      expect(body['username'], 'userid1');
      expect(body['password'], isNull);
      expect(node.toUri(), 'socks4://userid1:@example-1.com:1080#s4');
    });

    test('socks5 с паролем флагом не затронут', () {
      final node = parseUri('socks5://u:p@example-1.com:1080#s5');
      expect(node!.toUri(), 'socks5://u:p@example-1.com:1080#s5');
    });
  });


  group('3k — `default` группы selector (§565: род исполняется)', () {


    test('импорт selector: род selector, кода нет, `default` СОХРАНЁН', () {
      final nodes = parseAll(decode(_json({
        'outbounds': [
          {
            'type': 'vless',
            'tag': 'n1',
            'server': 'a.example',
            'server_port': 443,
            'uuid': _uuid,
          },
          {
            'type': 'vless',
            'tag': 'n2',
            'server': 'b.example',
            'server_port': 443,
            'uuid': _uuid,
          },
          {
            'type': 'selector',
            'tag': 'my-group',
            'outbounds': ['n1', 'n2'],
            'default': 'n2',
          },
        ],
      })));

      final group = nodes.whereType<AutoSelectSpec>().single;
      expect(_codes(group.warnings), isNot(contains('selector_as_auto')),
          reason: 'род selector исполняется — сводить нечего');
      expect(group.genus, 'selector');
      expect(group.manualDefault, 'n2',
          reason: 'ИМЯ ЧЛЕНА, выбранного вручную, обязано дожить в модели');
    });

    test('тело selector несёт `default` и состав', () {


      final nodes = parseAll(decode(_json({
        'outbounds': [
          {
            'type': 'vless',
            'tag': 'n1',
            'server': 'a.example',
            'server_port': 443,
            'uuid': _uuid,
          },
          {
            'type': 'selector',
            'tag': 'g',
            'outbounds': ['n1'],
            'default': 'n1',
          },
        ],
      })));
      final group = nodes.whereType<AutoSelectSpec>().single;
      final body = group.emitRaw(const TemplateVars()).map;
      expect(body['type'], 'selector');
      expect(body['default'], 'n1');
      expect(body['outbounds'], ['n1']);
      expect(body.containsKey('url'), isFalse,
          reason: 'параметров замера у ручного рода нет');
    });

    test('группа БЕЗ `default` несёт пустую строку, а не мусор', () {
      final nodes = parseAll(decode(_json({
        'outbounds': [
          {
            'type': 'vless',
            'tag': 'n1',
            'server': 'a.example',
            'server_port': 443,
            'uuid': _uuid,
          },
          {
            'type': 'urltest',
            'tag': 'g',
            'outbounds': ['n1'],
          },
        ],
      })));
      expect(nodes.whereType<AutoSelectSpec>().single.manualDefault, '');
    });
  });


  group('3l — `tlsSettings.alpn` → `tls.alpn` (D133-C9 отменена)', () {


    test('массивом — доезжает с ОБЩЕГО блока', () {
      final nodes = parseAll(decode(_xrayBody({
        ..._vlessSettings(),
        'streamSettings': {
          'network': 'tcp',
          'security': 'tls',
          'tlsSettings': {
            'serverName': 'a.example',
            'alpn': ['h2'],
          },
        },
      })));
      final tls =
          nodes.single.emit(const TemplateVars()).map['tls'] as Map<String, dynamic>;
      expect(tls['alpn'], ['h2']);
    });

    test('строкой через запятую — в массив', () {
      final nodes = parseAll(decode(_xrayBody({
        ..._vlessSettings(),
        'streamSettings': {
          'network': 'tcp',
          'security': 'tls',
          'tlsSettings': {'serverName': 'a.example', 'alpn': 'h2,http/1.1'},
        },
      })));
      final tls =
          nodes.single.emit(const TemplateVars()).map['tls'] as Map<String, dynamic>;
      expect(tls['alpn'], ['h2', 'http/1.1']);
    });
  });


  group('3m — новые `mappers.xray`: поля доезжают', () {


    test('`protocol: wireguard` — узел, а не «протокол не поддержан»', () {
      final dropped = <NodeWarning>[];
      final nodes = parseAll(
        decode(_xrayBody({
          'protocol': 'wireguard',
          'settings': {
            'secretKey': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
            'address': ['10.0.0.2/32'],
            'peers': [
              {
                'endpoint': 'wg.example:51820',
                'publicKey': 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=',
                'allowedIPs': ['0.0.0.0/0'],
              },
            ],
          },
        })),
        dropped: dropped,
      );
      expect(nodes, hasLength(1),
          reason: 'все целевые поля у ядра есть — узел терялся зря');
      final body = nodes.single.emit(const TemplateVars()).map;
      expect(body['type'], 'wireguard');
    });

    test('`protocol: http` — пара user/pass и карта заголовков', () {
      final nodes = parseAll(decode(_xrayBody({
        'protocol': 'http',
        'settings': {
          'servers': [
            {
              'address': '192.0.2.20',
              'port': 8080,
              'users': [
                {'user': 'testuser', 'pass': 'testpass123'},
              ],
            },
          ],
        },
      })));
      final body = nodes.single.emit(const TemplateVars()).map;
      expect(body['username'], 'testuser');
      expect(body['password'], 'testpass123');
    });

    test('`mux` элемента читается СЕКЦИЕЙ: узел цел, ключ не «неизвестный»', () {






      final nodes = parseAll(decode(_xrayBody({
        ..._vlessSettings(),
        'streamSettings': {'network': 'tcp', 'security': 'none'},
        'mux': {
          'enabled': true,
          'concurrency': 8,
          'xudpConcurrency': 16,
          'xudpProxyUDP443': 'reject',
        },
      })));
      expect(nodes, hasLength(1));
      final paths = nodes.single.warnings
          .whereType<RegistryWarning>()
          .where((w) => w.code == 'json_field_unknown')
          .map((w) => w.path)
          .toList();
      expect(paths.where((p) => p?.startsWith('mux') ?? false), isEmpty,
          reason: 'все четыре листа `mux` объявлены блоком multiplex#xray — '
              'до 1.1.50 секции у них не было и они молчали потерей');
    });

    test('`concurrency: -1` НЕ даёт `type_invalid`', () {




      final nodes = parseAll(decode(_xrayBody({
        ..._vlessSettings(),
        'streamSettings': {'network': 'tcp', 'security': 'none'},
        'mux': {'enabled': true, 'concurrency': -1},
      })));
      expect(nodes, hasLength(1));
      expect(_codes(nodes.single.warnings), isNot(contains('type_invalid')),
          reason: 'это не «число вне границ», а «блока нет вовсе»');
    });
  });


  group('3n — предел длины ссылки', () {
    test('канон 65536: длинная валидная ссылка принимается', () {

      final pad = 'a' * 9000;
      final node = parseUri(
          'vless://$_uuid@example-1.com:443?encryption=none&security=none#$pad');
      expect(node, isNotNull);
    });

    test('за пределом — `uri_too_long`, а не молчание', () {
      final dropped = XrayDropVerdict();
      final node = parseUri(
        'vless://$_uuid@example-1.com:443?encryption=none#${'a' * 70000}',
        dropped: dropped,
      );
      expect(node, isNull);
      expect(_codeOf(dropped.reason!), 'uri_too_long');
    });
  });
}
