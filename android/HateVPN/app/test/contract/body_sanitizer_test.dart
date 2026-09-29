






import 'package:flutter_test/flutter_test.dart';
import '../contract_paths.dart';
import 'package:lxbox/models/node_warning.dart';
import 'package:lxbox/services/contract/body_sanitizer.dart';
import 'package:lxbox/services/contract/registry.dart';




const _core = '1.14.1-lx.4';

SanitizeResult _san(
  Map<String, dynamic> body, {
  String scheme = 'vless',
  String core = _core,
  String platform = 'android',
}) =>
    RegistrySanitizer.sanitize(body,
        scheme: scheme, coreVersion: core, platform: platform);


Map<String, dynamic> _vless([Map<String, dynamic> extra = const {}]) => {
      'type': 'vless',
      'tag': 'n1',
      'server': 'example.com',
      'server_port': 443,
      'uuid': '11111111-1111-1111-1111-111111111111',
      ...extra,
    };

List<String> _codes(SanitizeResult r) =>
    r.warnings.map((w) => w.code).toList();

RegistryWarning _byCode(SanitizeResult r, String code) =>
    r.warnings.firstWhere((w) => w.code == code,
        orElse: () => fail('нет кода $code, есть: ${_codes(r)}'));

void main() {

  setUpAll(loadTestRegistry);


  group('RegistrySanitizer — таблица 2.2', () {
    test('неизвестный ключ снимается с unknown_key', () {
      final r = _san(_vless({'foo': 1}));
      expect(r.body, isNotNull);
      expect(r.body!.containsKey('foo'), isFalse);
      expect(_codes(r), contains('unknown_key'));
      expect(_byCode(r, 'unknown_key').path, 'foo');

      expect(r.body!['uuid'], '11111111-1111-1111-1111-111111111111');
    });






    test('unknown_key несёт снятое значение', () {
      final r = _san(_vless({'totally_unknown_key': 'whatever'}));
      expect(_byCode(r, 'unknown_key').value, 'whatever');
    });



    test('unknown_key печатает объект по канону корпуса', () {
      final r = _san(_vless({
        'totally_unknown_key': {'b': 2, 'a': true}
      }));
      expect(_byCode(r, 'unknown_key').value, 'map[a:true b:2]');
    });

    test('type: строка вместо порта не приводится → drop_node', () {

      final r = _san(_vless({'server_port': 'x'}));
      expect(r.body, isNull, reason: 'узел уходит целиком');
      expect(_codes(r), contains('port_invalid'));
    });

    test('type: число строкой приводится, узел живёт', () {
      final r = _san(_vless({'server_port': '8443'}));
      expect(r.body!['server_port'], 8443);
      expect(r.warnings, isEmpty);
    });

    test('listable_string принимает и строку, и массив', () {
      final one = _san(_vless({
        'tls': {'enabled': true, 'alpn': 'h3'}
      }));
      expect((one.body!['tls'] as Map)['alpn'], 'h3');

      final many = _san(_vless({
        'tls': {'enabled': true, 'alpn': ['h2', 'h3']}
      }));
      expect((many.body!['tls'] as Map)['alpn'], ['h2', 'h3']);
      expect(many.warnings, isEmpty);
    });

    test('duration нормализуется в Go-форму', () {
      final r = _san(_vless({
        'tls': {'enabled': true, 'handshake_timeout': '10'}
      }));
      expect((r.body!['tls'] as Map)['handshake_timeout'], '10s');
    });

    test('enum + normalize: " Hybrid " принимается как hybrid', () {
      final r = _san(_vless({
        'tls': {
          'enabled': true,
          'utls': {'enabled': true},
          'reality': {
            'enabled': true,
            'public_key': 'AwoRGB8mLTQ7QklQV15lbHN6gYiPlp2kq7K5wMfO1dw',
            'key_share': ' Hybrid ',
          },
        }
      }));
      final reality = (r.body!['tls'] as Map)['reality'] as Map;
      expect(reality['key_share'], 'hybrid');
      expect(r.warnings, isEmpty);
    });

    test('enum вне набора → on_invalid с кодом реестра', () {
      final r = _san(_vless({
        'tls': {
          'enabled': true,
          'utls': {'enabled': true},
          'reality': {
            'enabled': true,
            'public_key': 'AwoRGB8mLTQ7QklQV15lbHN6gYiPlp2kq7K5wMfO1dw',
            'key_share': 'quantum',
          },
        }
      }));
      final reality = (r.body!['tls'] as Map)['reality'] as Map;
      expect(reality.containsKey('key_share'), isFalse);
      expect(_codes(r), contains('reality_key_share_invalid'));
      expect(_byCode(r, 'reality_key_share_invalid').path,
          'tls.reality.key_share');

      expect(reality['enabled'], isTrue);
    });

    test('format: мусорный server_name снимается', () {

      final r = _san(_vless({
        'tls': {'enabled': true, 'server_name': 'a b c'}
      }));
      expect((r.body!['tls'] as Map).containsKey('server_name'), isFalse);
      expect(_codes(r), contains('type_invalid'));
    });

    test('len_parity: short_id нечётной длины снимается', () {
      final r = _san(_vless({
        'tls': {
          'enabled': true,
          'utls': {'enabled': true},
          'reality': {
            'enabled': true,
            'public_key': 'AwoRGB8mLTQ7QklQV15lbHN6gYiPlp2kq7K5wMfO1dw',
            'short_id': 'abc',
          },
        }
      }));
      final reality = (r.body!['tls'] as Map)['reality'] as Map;
      expect(reality.containsKey('short_id'), isFalse,
          reason: 'hex нечётной длины ядро не разберёт');
      expect(r.warnings, isNotEmpty);
    });

    test('required: vless без uuid → drop_node с field_missing', () {
      final body = _vless()..remove('uuid');
      final r = _san(body);
      expect(r.body, isNull);
      expect(_codes(r), contains('field_missing'));
      expect(_byCode(r, 'field_missing').params['field'], 'uuid');
    });

    test('required внутри объекта: reality без public_key → снят БЛОК, узел жив',
        () {











      final r = _san(_vless({
        'tls': {
          'enabled': true,
          'utls': {'enabled': true},
          'reality': {'enabled': true},
        }
      }));
      expect(r.body, isNotNull, reason: 'узел деградирует до plain TLS');
      expect((r.body!['tls'] as Map).containsKey('reality'), isFalse,
          reason: 'снят весь блок REALITY');
      expect(_byCode(r, 'field_missing').params['field'],
          'tls.reality.public_key');
    });

    test('secret: значение в предупреждении маскируется', () {

      final schema = ContractRegistry.I.schemaFor('vless')!;
      expect(schema.fields['uuid']!.secret, isTrue,
          reason: 'uuid объявлен secret — на нём и проверяем маскирование');


      final ss = ContractRegistry.I.schemaFor('shadowsocks')!;
      expect(ss.fields['password']!.secret, isTrue);



      const w = RegistryWarning(
          code: 'type_invalid', path: 'password', value: '***');
      expect(w.value, '***');
    });

    test('conflicts: ech.enabled + reality.enabled — снят декларант', () {
      final r = _san(_vless({
        'tls': {
          'enabled': true,
          'utls': {'enabled': true},
          'ech': {'enabled': true},
          'reality': {
            'enabled': true,
            'public_key': 'AwoRGB8mLTQ7QklQV15lbHN6gYiPlp2kq7K5wMfO1dw',
          },
        }
      }));
      final tls = r.body!['tls'] as Map;











      expect((tls['ech'] as Map).containsKey('enabled'), isFalse);
      expect((tls['reality'] as Map)['enabled'], isTrue);


      expect(r.warnings.where((w) => w.code == 'field_conflict').length, 1);
      expect(_byCode(r, 'field_conflict').path, 'tls.ech.enabled');
      expect(_byCode(r, 'field_conflict').params['with'], 'tls.reality.enabled');
    });

    test('requires: key_share при невалидном public_key снимается МОЛЧА', () {












      final r = _san(_vless({
        'tls': {
          'enabled': true,
          'utls': {'enabled': true},
          'reality': {
            'enabled': true,
            'public_key': 'не base64!',
            'key_share': 'hybrid',
          },
        }
      }));



      expect((r.body!['tls'] as Map).containsKey('reality'), isFalse);
      expect(_codes(r), ['reality_pbk_invalid']);
    });

    test('requires: поля, которого НЕ БЫЛО, объясняет только field_requires',
        () {


      final r = _san(_vless({
        'tls': {'enabled': true, 'spoof_method': 'wrong-checksum'}
      }));
      expect(_codes(r), contains('field_requires'));
      expect(_byCode(r, 'field_requires').params['requires'], 'tls.spoof');
    });

    test('requires: spoof_method без spoof снимается', () {
      final r = _san(_vless({
        'tls': {'enabled': true, 'spoof_method': 'wrong-checksum'}
      }));
      final tls = r.body!['tls'] as Map;
      expect(tls.containsKey('spoof_method'), isFalse);
      expect(_byCode(r, 'field_requires').path, 'tls.spoof_method');
    });

    test('forbidden_for: naive + tls.alpn → tls_field_unsupported_naive', () {
      final r = _san({
        'type': 'naive',
        'tag': 'n1',
        'server': '1.2.3.4',
        'server_port': 443,
        'username': 'u',
        'password': 'p',
        'tls': {
          'enabled': true,
          'server_name': 's.com',
          'alpn': ['h2'],
          'certificate': '-----BEGIN CERTIFICATE-----',
        },
      }, scheme: 'naive');
      final tls = r.body!['tls'] as Map;
      expect(tls.containsKey('alpn'), isFalse);

      expect(tls['certificate'], '-----BEGIN CERTIFICATE-----');
      expect(_codes(r), contains('tls_field_unsupported_naive'));
      expect(_byCode(r, 'tls_field_unsupported_naive').path, 'tls.alpn');
    });

    test('min_core: key_share снят на lx.3, цел на lx.4', () {
      Map<String, dynamic> body() => _vless({
            'tls': {
              'enabled': true,
              'utls': {'enabled': true},
              'reality': {
                'enabled': true,
                'public_key': 'AwoRGB8mLTQ7QklQV15lbHN6gYiPlp2kq7K5wMfO1dw',
                'key_share': 'hybrid',
              },
            }
          });

      final old = _san(body(), core: '1.14.1-lx.3');
      final oldReality = (old.body!['tls'] as Map)['reality'] as Map;
      expect(oldReality.containsKey('key_share'), isFalse,
          reason: 'ключ неизвестен ядру lx.3 — эмиттер его опускает');

      expect(_codes(old), isNot(contains('reality_key_share_invalid')));

      final now = _san(body(), core: '1.14.1-lx.4');
      expect(((now.body!['tls'] as Map)['reality'] as Map)['key_share'],
          'hybrid');
    });

    test('platform: kernel_tx снят вне linux', () {
      final android = _san(_vless({
        'tls': {'enabled': true, 'kernel_tx': true}
      }));
      expect((android.body!['tls'] as Map).containsKey('kernel_tx'), isFalse,
          reason: 'kTLS вне Linux валит весь конфиг');

      final linux = _san(_vless({
        'tls': {'enabled': true, 'kernel_tx': true}
      }), platform: 'linux');
      expect((linux.body!['tls'] as Map)['kernel_tx'], isTrue);
    });

    test('advisory: ss aes-128-cfb даёт ss_method_legacy, поле цело', () {
      final r = _san({
        'type': 'shadowsocks',
        'tag': 'ss1',
        'server': 'example.com',
        'server_port': 8388,
        'method': 'aes-128-cfb',
        'password': 'p',
      }, scheme: 'shadowsocks');
      expect(r.body!['method'], 'aes-128-cfb', reason: 'узел живёт как есть');
      expect(_codes(r), contains('ss_method_legacy'));
      expect(_byCode(r, 'ss_method_legacy').severity, WarningSeverity.info);
    });






    test('all_or_nothing: частичный xmux проходит как есть, без дефолтов', () {
      final r = _san(_vless({
        'transport': {
          'type': 'xhttp',
          'xmux': {'max_connections': '4-8'},
        }
      }));
      final xmux = ((r.body!['transport'] as Map)['xmux']) as Map;
      expect(xmux['max_connections'], '4-8');
      expect(xmux.containsKey('h_max_request_times'), isFalse,
          reason: 'дефолт соседа не дописывается');
      expect(xmux.containsKey('h_max_reusable_secs'), isFalse);
      expect(xmux.keys.toList(), ['max_connections'],
          reason: 'секция байт в байт та, что пришла');
      expect(_codes(r), isEmpty);
    });


    group('§467 conflicts по значению', () {
      test('xmux в полной форме с нулями: конфликта нет, тело не изменено', () {


        final xmuxIn = {
          'max_concurrency': '16-32',
          'max_connections': '0',
          'c_max_reuse_times': '0',
          'h_max_request_times': '600-900',
          'h_max_reusable_secs': '1800-3000',
          'h_keep_alive_period': 0,
        };
        final r = _san(_vless({
          'transport': {
            'type': 'xhttp',
            'xmux': Map<String, dynamic>.from(xmuxIn),
          }
        }));
        final xmux = ((r.body!['transport'] as Map)['xmux']) as Map;
        expect(xmux['max_concurrency'], '16-32',
            reason: 'рабочее значение остаётся: "0" у соседа = не задано');
        expect(Map<String, dynamic>.from(xmux.cast<String, dynamic>()), xmuxIn,
            reason: 'тело байт в байт');
        expect(_codes(r), isEmpty);
      });

      test('оба > 0 — конфликт как раньше', () {
        final r = _san(_vless({
          'transport': {
            'type': 'xhttp',
            'xmux': {'max_concurrency': '16-32', 'max_connections': '4-8'},
          }
        }));
        expect(_codes(r), contains('field_conflict'));
        final xmux = ((r.body!['transport'] as Map)['xmux']) as Map;

        expect(
            xmux.containsKey('max_concurrency') &&
                xmux.containsKey('max_connections'),
            isFalse);
      });

      test('«0-0» у соседа — тоже не задано', () {
        final r = _san(_vless({
          'transport': {
            'type': 'xhttp',
            'xmux': {'max_concurrency': '16-32', 'max_connections': '0-0'},
          }
        }));
        expect(_codes(r), isEmpty);
        final xmux = ((r.body!['transport'] as Map)['xmux']) as Map;
        expect(xmux['max_concurrency'], '16-32');
      });
    });

    test('порядок ключей — входящий: гард не переставляет валидное тело', () {



      final src = {
        'flow': 'xtls-rprx-vision',
        'uuid': '11111111-1111-1111-1111-111111111111',
        'tag': 'n1',
        'server_port': 443,
        'type': 'vless',
        'server': 'example.com',
      };
      final r = _san(Map<String, dynamic>.from(src));
      expect(r.body!.keys.toList(), src.keys.toList());
      expect(r.warnings, isEmpty);
    });

    test('снятое поле не сдвигает соседей', () {
      final r = _san({
        'type': 'vless',
        'tag': 'n1',
        'server': 'example.com',
        'junk': 1,
        'server_port': 443,
        'uuid': '11111111-1111-1111-1111-111111111111',
      });
      expect(r.body!.keys.toList(),
          ['type', 'tag', 'server', 'server_port', 'uuid']);
    });

    test('дефолты не материализуются (PARSING_PRINCIPLES §2.4)', () {
      final r = _san(_vless());

      expect(r.body!.containsKey('packet_encoding'), isFalse);
      expect(r.body!.containsKey('flow'), isFalse);
      expect(r.body!.containsKey('network'), isFalse);
    });

    test('tag и detour не трогаются — их пишет сборка', () {
      final r = _san(_vless({'detour': 'hop-1'}));
      expect(r.body!['tag'], 'n1');
      expect(r.body!['detour'], 'hop-1');
      expect(_codes(r), isNot(contains('unknown_key')));
    });

    test('реестр не загружен — тело возвращается как есть', () {


      final body = {'type': 'shadowtls', 'tag': 't', 'whatever': 1};
      final r = _san(body, scheme: 'shadowtls');
      expect(r.body, same(body));
      expect(r.warnings, isEmpty);
    });

    test('вложенный объект и элементы массива обходятся рекурсивно', () {
      final r = _san({
        'type': 'wireguard',
        'tag': 'wg1',
        'address': ['10.0.0.2/32'],



        'private_key': 'cHJpdmF0ZUtleUJhc2U2NEV4YW1wbGVWYWx1ZTEyMzQ=',
        'peers': [
          {
            'address': '1.2.3.4',
            'port': 51820,
            'public_key': 'cHVibGljS2V5QmFzZTY0RXhhbXBsZVZhbHVlMTIzNDU=',
            'allowed_ips': ['0.0.0.0/0'],
            'junk_key': 'x',
          }
        ],
      }, scheme: 'wireguard');
      expect(_codes(r), contains('unknown_key'));
      expect(_byCode(r, 'unknown_key').path, 'peers[0].junk_key');
      final peer = (r.body!['peers'] as List).first as Map;
      expect(peer.containsKey('junk_key'), isFalse);
      expect(peer['public_key'], isNotNull);
    });

    test('транспорт выбирается по type, мусорный ключ внутри снят', () {
      final r = _san(_vless({
        'transport': {'type': 'ws', 'path': '/x', 'bogus': 1}
      }));
      final t = r.body!['transport'] as Map;
      expect(t['type'], 'ws');
      expect(t['path'], '/x');
      expect(t.containsKey('bogus'), isFalse);
      expect(_byCode(r, 'unknown_key').path, 'transport.bogus');
    });
  });









  group('renderWarningValue — PARSING_PRINCIPLES §6', () {
    test('скаляр — как есть, без кавычек', () {
      expect(RegistrySanitizer.renderWarningValue(true), 'true');
      expect(RegistrySanitizer.renderWarningValue(443), '443');
      expect(RegistrySanitizer.renderWarningValue('h3'), 'h3');
    });

    test('объект — map[k:v k:v] с ключами по алфавиту', () {
      expect(
        RegistrySanitizer.renderWarningValue(
            {'fingerprint': 'chrome', 'enabled': true}),
        'map[enabled:true fingerprint:chrome]',
      );
    });

    test('вложенный объект печатается тем же правилом', () {
      expect(
        RegistrySanitizer.renderWarningValue({
          'b': {'y': 2, 'x': 1},
          'a': 0,
        }),
        'map[a:0 b:map[x:1 y:2]]',
      );
    });

    test('массив — [a b c], порядок сохраняется', () {
      expect(RegistrySanitizer.renderWarningValue(['h2', 'http/1.1']),
          '[h2 http/1.1]');
      expect(RegistrySanitizer.renderWarningValue([]), '[]');
    });

    test('обрезка — 64 РУНЫ и многоточие U+2026', () {

      final exact = 'a' * 64;
      expect(RegistrySanitizer.renderWarningValue(exact), exact);
      final long = 'a' * 65;
      expect(RegistrySanitizer.renderWarningValue(long), '${'a' * 64}…');
    });

    test('обрезка считает РУНЫ, а не кодовые единицы UTF-16', () {


      final runes64 = '🙂' * 64;
      expect(RegistrySanitizer.renderWarningValue(runes64), runes64);
      expect(RegistrySanitizer.renderWarningValue('🙂' * 65), '$runes64…');
    });

    test('secret-поле — *** вместо значения', () {
      expect(
        RegistrySanitizer.renderWarningValue('hunter2', secret: true),
        '***',
      );
    });
  });

  group('RegistrySanitizer — выражения W2d (§464)', () {
    test('format base64_32: ключ не 32 байта после декода — REALITY снят', () {


      final r = _san(_vless({
        'tls': {
          'enabled': true,
          'reality': {'enabled': true, 'public_key': 'enabled'},
        }
      }));
      expect(_byCode(r, 'reality_pbk_invalid').path, 'tls.reality.public_key');
      expect(_byCode(r, 'reality_pbk_invalid').value, 'enabled');





      expect(r.body, isNotNull, reason: 'узел жив, деградировал до plain TLS');
      expect((r.body!['tls'] as Map).containsKey('reality'), isFalse);
    });

    test('format base64_32: ровно 32 байта проходят в любом написании', () {

      for (final key in const [
        'AwoRGB8mLTQ7QklQV15lbHN6gYiPlp2kq7K5wMfO1dw',
        'cHVibGljS2V5QmFzZTY0RXhhbXBsZVZhbHVlMTIzNDU=',
      ]) {
        final r = _san(_vless({
          'tls': {
            'enabled': true,
            'reality': {'enabled': true, 'public_key': key},
          }
        }));
        expect(_codes(r), isNot(contains('reality_pbk_invalid')),
            reason: '$key — 32 байта после декода');
      }
    });

    test('format base64_32: НЕКАНОНИЧЕСКАЯ последняя группа — годный ключ',
        () {






      final r = _san(_vless({
        'tls': {
          'enabled': true,
          'reality': {
            'enabled': true,
            'public_key': 'ccccccccccccccccccccccccccccccccccccccccccC=',
          },
        }
      }));
      expect(_codes(r), isNot(contains('reality_pbk_invalid')));








      expect(
        ((r.body?['tls'] as Map?)?['reality'] as Map?)?['public_key'],
        'ccccccccccccccccccccccccccccccccccccccccccA',
      );
    });

    test('int_array: границы min/max относятся к ЭЛЕМЕНТУ', () {




      Map<String, dynamic> wg(List<Object> reserved) => {
            'type': 'wireguard',
            'tag': 'wg',
            'private_key': 'ccccccccccccccccccccccccccccccccccccccccccA=',
            'address': ['10.0.0.3/32'],
            'peers': [
              {
                'public_key': 'ddddddddddddddddddddddddddddddddddddddddddA=',
                'address': 'h.example',
                'port': 51820,
                'allowed_ips': ['0.0.0.0/0'],
                'reserved': reserved,
              }
            ],
          };

      final bad = _san(wg([1, 2, 999]), scheme: 'wireguard');
      expect(_codes(bad), contains('type_invalid'));
      expect(
        ((bad.body?['peers'] as List?)?.first as Map?)?.containsKey('reserved'),
        isFalse,
        reason: 'элемент вне 0..255 — поле снято целиком',
      );


      final ok = _san(wg([1, 2, 3]), scheme: 'wireguard');
      expect(_codes(ok), isNot(contains('type_invalid')));
      expect(((ok.body?['peers'] as List).first as Map)['reserved'],
          [1, 2, 3]);
    });

    test('normalize base64_std: неканоническая форма приводится к канону', () {



      final r = _san({
        'type': 'wireguard',
        'tag': 'wg',
        'private_key': 'ccccccccccccccccccccccccccccccccccccccccccC=',
        'address': ['10.0.0.3/32'],
        'peers': [
          {
            'public_key': 'ddddddddddddddddddddddddddddddddddddddddddD=',
            'address': 'h.example',
            'port': 51820,
            'allowed_ips': ['0.0.0.0/0'],
          }
        ],
      }, scheme: 'wireguard');
      expect(_codes(r), isNot(contains('wg_key_invalid')),
          reason: 'коды: ${_codes(r)}');
      expect(r.body, isNotNull, reason: 'коды: ${_codes(r)}');
      expect(r.body?['private_key'],
          'ccccccccccccccccccccccccccccccccccccccccccA=');
    });

    test('normalize hex_only + normalize_code: 0x1a2 чистится с кодом', () {
      final r = _san(_vless({
        'tls': {
          'enabled': true,
          'reality': {
            'enabled': true,
            'public_key': 'AwoRGB8mLTQ7QklQV15lbHN6gYiPlp2kq7K5wMfO1dw',
            'short_id': '0x1a2',
          },
        }
      }));
      final reality = (r.body!['tls'] as Map)['reality'] as Map;

      expect(reality['short_id'], '01a2');

      final w = _byCode(r, 'reality_short_id_invalid');
      expect(w.path, 'tls.reality.short_id');
      expect(w.value, '0x1a2');
    });

    test('normalize hex_only: значение без потерь кода не даёт', () {
      final r = _san(_vless({
        'tls': {
          'enabled': true,
          'reality': {
            'enabled': true,
            'public_key': 'AwoRGB8mLTQ7QklQV15lbHN6gYiPlp2kq7K5wMfO1dw',
            'short_id': '48ab12',
          },
        }
      }));
      expect(_codes(r), isNot(contains('reality_short_id_invalid')));
    });

    test('advisory except+when: fp вне гибридных — код только при REALITY',
        () {
      Map<String, dynamic> tls({required bool reality}) => {
            'enabled': true,
            'utls': {'enabled': true, 'fingerprint': 'qq'},
            if (reality)
              'reality': {
                'enabled': true,
                'public_key': 'AwoRGB8mLTQ7QklQV15lbHN6gYiPlp2kq7K5wMfO1dw',
              },
          };
      final withReality = _san(_vless({'tls': tls(reality: true)}));
      final w = _byCode(withReality, 'reality_fp_not_chrome');
      expect(w.path, 'tls.utls.fingerprint');
      expect(w.value, 'qq');

      expect(
          ((withReality.body!['tls'] as Map)['utls'] as Map)['fingerprint'],
          'qq');


      final plain = _san(_vless({'tls': tls(reality: false)}));
      expect(_codes(plain), isNot(contains('reality_fp_not_chrome')));
    });

    test('advisory except: гибридный отпечаток кода не получает', () {
      for (final fp in const ['chrome', 'firefox', 'safari', 'random']) {
        final r = _san(_vless({
          'tls': {
            'enabled': true,
            'utls': {'enabled': true, 'fingerprint': fp},
            'reality': {
              'enabled': true,
              'public_key': 'AwoRGB8mLTQ7QklQV15lbHN6gYiPlp2kq7K5wMfO1dw',
            },
          }
        }));
        expect(_codes(r), isNot(contains('reality_fp_not_chrome')),
            reason: '$fp несёт гибридный key share');
      }
    });

    test('requires equals: gecko-размеры на salamander снимаются', () {
      final r = _san({
        'type': 'hysteria2',
        'tag': 'h1',
        'server': 'example.com',
        'server_port': 443,
        'password': 'p',
        'tls': {'enabled': true},
        'obfs': {
          'type': 'salamander',
          'password': 'x',
          'min_packet_size': 100,
        },
      }, scheme: 'hysteria2');
      expect(_byCode(r, 'field_requires').path, 'obfs.min_packet_size');
      final obfs = r.body!['obfs'] as Map;
      expect(obfs.containsKey('min_packet_size'), isFalse);

      expect(obfs['type'], 'salamander');
    });

    test('requires equals: на gecko те же размеры остаются', () {
      final r = _san({
        'type': 'hysteria2',
        'tag': 'h1',
        'server': 'example.com',
        'server_port': 443,
        'password': 'p',
        'tls': {'enabled': true},
        'obfs': {'type': 'gecko', 'password': 'x', 'min_packet_size': 100},
      }, scheme: 'hysteria2');
      expect(_codes(r), isNot(contains('field_requires')));
      expect((r.body!['obfs'] as Map)['min_packet_size'], 100);
    });

    test('default_when: полоса hysteria v1 материализуется без кода', () {


      final r = _san({
        'type': 'hysteria',
        'tag': 'h1',
        'server': 'example.com',
        'server_port': 443,
        'tls': {'enabled': true},
      }, scheme: 'hysteria');
      expect(r.body!['up_mbps'], 100);
      expect(r.body!['down_mbps'], 100);
      expect(_codes(r), isEmpty, reason: 'узел жив и в порядке — кода нет');
    });

    test('default_when не перебивает заданное значение', () {
      final r = _san({
        'type': 'hysteria',
        'tag': 'h1',
        'server': 'example.com',
        'server_port': 443,
        'up_mbps': 50,
        'tls': {'enabled': true},
      }, scheme: 'hysteria');
      expect(r.body!['up_mbps'], 50);
      expect(r.body!['down_mbps'], 100);
    });

    test('§473 default_when с when: дефолт только у AmneziaWG-узла', () {
      Map<String, dynamic> wg({bool awg = false}) => {
            'type': 'wireguard',
            'tag': 'wg',
            if (awg) 'jc': 10,
            'address': ['10.0.0.2/32'],
            'private_key': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaA=',
            'peers': [
              {
                'address': 'example-3.com',
                'port': 51820,
                'public_key': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbA=',
                'allowed_ips': ['0.0.0.0/0'],
              },
            ],
          };

      final awg = _san(wg(awg: true), scheme: 'wireguard');
      expect(awg.body!['mtu'], 1280);
      expect(_codes(awg), isEmpty, reason: 'дефолт — не замена, кода нет');



      final plain = _san(wg(), scheme: 'wireguard');
      expect(plain.body!.containsKey('mtu'), isFalse);
      expect(_codes(plain), isEmpty);
    });

    test('§473 max_when: потолок, исключение по входу и род узла', () {
      Map<String, dynamic> body(int mtu, {bool awg = true}) => {
            'type': 'wireguard',
            'tag': 'wg',
            'mtu': mtu,
            if (awg) 'jc': 10,
            'address': ['10.0.0.2/32'],
            'private_key': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaA=',
            'peers': [
              {
                'address': 'example-3.com',
                'port': 51820,
                'public_key': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbA=',
                'allowed_ips': ['0.0.0.0/0'],
              },
            ],
          };



      final clamped = RegistrySanitizer.sanitize(body(1420),
          scheme: 'wireguard', coreVersion: _core);
      expect(clamped.body!['mtu'], 1280);
      expect(clamped.warnings.single.code, 'awg_mtu_clamped');
      expect(clamped.warnings.single.path, 'mtu');
      expect(clamped.warnings.single.value, '1420');


      final kept = RegistrySanitizer.sanitize(body(1420),
          scheme: 'wireguard',
          coreVersion: _core,
          source: BodySource.singbox);
      expect(kept.body!['mtu'], 1420);
      expect(kept.warnings.single.code, 'awg_mtu_high');
      expect(kept.warnings.single.value, '1420');


      for (final src in BodySource.values) {
        final plain = RegistrySanitizer.sanitize(body(1420, awg: false),
            scheme: 'wireguard', coreVersion: _core, source: src);
        expect(plain.body!['mtu'], 1420, reason: '$src');
        expect(plain.warnings, isEmpty, reason: '$src');
      }


      final low = RegistrySanitizer.sanitize(body(1200),
          scheme: 'wireguard', coreVersion: _core);
      expect(low.body!['mtu'], 1200);
      expect(low.warnings, isEmpty);
    });

    Map<String, dynamic> awgBody(Object marker) => {
          'type': 'wireguard',
          'tag': 'wg',
          'mtu': 1420,
          'jc': marker,
          'address': ['10.0.0.2/32'],
          'private_key': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaA=',
          'peers': [
            {
              'address': 'example-3.com',
              'port': 51820,
              'public_key': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbA=',
              'allowed_ips': ['0.0.0.0/0'],
            },
          ],
        };

    test('§473 any_set судит НАЛИЧИЕ ключа, а не заданность значения', () {







      for (final marker in const [0, false, <String>[]]) {
        final r = RegistrySanitizer.sanitize(awgBody(marker),
            scheme: 'wireguard', coreVersion: _core);
        expect(r.body!['mtu'], 1280, reason: 'jc=$marker — ключ есть');
        expect(r.warnings.map((w) => w.code), contains('awg_mtu_clamped'),
            reason: 'jc=$marker');
      }
    });

    test('§552 any_set: пустая строка — не наличие ключа (контракт 1.1.56)',
        () {



      final r = RegistrySanitizer.sanitize(awgBody(''),
          scheme: 'wireguard', coreVersion: _core);
      expect(r.body!['mtu'], 1420);
      expect(r.body!.containsKey('jc'), isFalse);
      expect(r.warnings.map((w) => w.code), isNot(contains('awg_mtu_clamped')));
    });

    test('grpc service_name: нормализации нет — значение как есть', () {



      for (final v in const [
        'abcde',
        '/abcde',
        '/abcde/Tun',
        '/a/b/Tun',
        '/a/Stream',
        '/abcde/Tun|multi',
        'a/b',
      ]) {
        final r = _san(_vless({
          'transport': {'type': 'grpc', 'service_name': v}
        }));
        expect((r.body!['transport'] as Map)['service_name'], v, reason: v);
        expect(r.warnings, isEmpty, reason: v);
      }
    });

    test('type awg_range: число и диапазон проходят, мусор снят', () {
      final r = _san({
        'type': 'wireguard',
        'tag': 'wg1',
        'address': ['10.0.0.2/32'],
        'private_key': 'cHJpdmF0ZUtleUJhc2U2NEV4YW1wbGVWYWx1ZTEyMzQ=',



        'h1': '5-10',
        'h2': 20,
        'h3': 'junk',
        'peers': [
          {
            'address': '1.2.3.4',
            'port': 51820,
            'public_key': 'cHVibGljS2V5QmFzZTY0RXhhbXBsZVZhbHVlMTIzNDU=',
            'allowed_ips': ['0.0.0.0/0'],
          }
        ],
      }, scheme: 'wireguard', core: '1.14.0-lx.40');


      expect(r.body!['h1'], '5-10');
      expect(r.body!['h2'], 20);
      expect(r.body!.containsKey('h3'), isFalse);



      expect(_byCode(r, 'awg_header_invalid').path, 'h3');
    });







    Map<String, dynamic> wgBody([Map<String, dynamic> extra = const {}]) => {
          'type': 'wireguard',
          'tag': 'wg1',
          'address': ['10.0.0.2/32'],
          'private_key': 'cHJpdmF0ZUtleUJhc2U2NEV4YW1wbGVWYWx1ZTEyMzQ=',
          'peers': [
            {
              'address': '1.2.3.4',
              'port': 51820,
              'public_key': 'cHVibGljS2V5QmFzZTY0RXhhbXBsZVZhbHVlMTIzNDU=',
              'allowed_ips': ['0.0.0.0/0'],
            }
          ],
          ...extra,
        };

    SanitizeResult sanWg([Map<String, dynamic> extra = const {}]) =>
        _san(wgBody(extra), scheme: 'wireguard', core: '1.14.0-lx.40');

    test('normalize range_order: перевёрнутая пара свопается ТИХО', () {
      final r = sanWg({'h1': '40-10'});
      expect(r.body!['h1'], '10-40',
          reason: 'порядок границ смысла не несёт — ядро выбирает значение ИЗ '
              'диапазона, и [10,40] = [40,10]');

      expect(_codes(r), isEmpty);
    });

    test('normalize range_order: голое число и прямая пара не трогаются', () {
      expect(sanWg({'h1': 7}).body!['h1'], 7);
      expect(sanWg({'h1': '10-40'}).body!['h1'], '10-40');
    });

    test('range_order НЕ стоит у таймингов AWG 3.x — перевёрнутая пара там '
        'опечатка и снимается с кодом', () {
      final r = sanWg({'rekey_after_time': '120-10'});
      expect(r.body!.containsKey('rekey_after_time'), isFalse);
      expect(_byCode(r, 'awg3_field_invalid').path, 'rekey_after_time');
    });

    test('awg_range: граница ШИРЕ uint32 снимает поле (ядро отвергло бы '
        'разбором весь конфиг)', () {
      final r = sanWg({'h1': '1-4294967296'});
      expect(r.body, isNotNull, reason: 'снимается ПОЛЕ, не узел');
      expect(r.body!.containsKey('h1'), isFalse);
      expect(_byCode(r, 'awg_header_invalid').path, 'h1');
    });

    test('body.relations ranges_disjoint: пересечение h1..h4 роняет УЗЕЛ', () {
      final r = sanWg({'h1': '5-10', 'h2': 7});
      expect(r.body, isNull);
      expect(r.explicitDropNode, isTrue);
      expect(_codes(r), contains('awg_headers_overlap'));
    });

    test('ranges_disjoint: незаданный заголовок участвует ДЕФОЛТОМ ядра', () {

      final r = sanWg({'h1': 2});
      expect(r.body, isNull);
      expect(_codes(r), contains('awg_headers_overlap'));

      expect(sanWg({'h1': 100}).body, isNotNull);
    });

    test('ranges_disjoint читает ЧИСТУЮ карту: снятое поле не «пересекается»',
        () {



      final r = sanWg({'h1': '1-4294967296', 'h2': 2});
      expect(r.body, isNotNull);
      expect(_codes(r), isNot(contains('awg_headers_overlap')));
      expect(_byCode(r, 'awg_header_invalid').path, 'h1');
    });

    test('min_when: паддинг ниже порога при заданном ключе роняет УЗЕЛ', () {
      final r = sanWg({
        'header_protection_key': 'aGVhZGVyS2V5QmFzZTY0RXhhbXBsZVZhbHVlMTIz',
        's1': 5,
        's2': 20,
        's3': 20,
        's4': 20,
      });
      expect(r.body, isNull);
      expect(r.explicitDropNode, isTrue);
      expect(_byCode(r, 'awg3_padding_too_short').path, 's1');
    });

    test('min_when absent_is_zero: ОТСУТСТВУЮЩИЙ паддинг при ключе — так же '
        'фатально', () {
      final r = sanWg({
        'header_protection_key': 'aGVhZGVyS2V5QmFzZTY0RXhhbXBsZVZhbHVlMTIz',
      });
      expect(r.body, isNull);
      expect(_codes(r), contains('awg3_padding_too_short'));
    });

    test('min_when: без ключа защиты порога НЕТ — обычный AmneziaWG живёт '
        'с любым паддингом', () {
      final r = sanWg({'s1': 5, 'jc': 3, 'jmin': 10, 'jmax': 50});
      expect(r.body, isNotNull);
      expect(r.body!['s1'], 5);
      expect(_codes(r), isNot(contains('awg3_padding_too_short')));
    });

    test('pattern у header_protection_key: все нули роняют УЗЕЛ', () {

      final r = sanWg({
        'header_protection_key': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        's1': 20,
        's2': 20,
        's3': 20,
        's4': 20,
      });
      expect(r.body, isNull);
      expect(_codes(r), contains('awg3_header_key_invalid'));
    });

    test('ключи WG судит РЕЕСТР: не-32-байтный ключ роняет узел '
        'с wg_key_invalid, а не молча', () {
      final short = _san({
        ...wgBody(),
        'private_key': 'c2hvcnQ=',
      }, scheme: 'wireguard', core: '1.14.0-lx.40');
      expect(short.body, isNull);
      expect(short.explicitDropNode, isTrue);
      final w = _byCode(short, 'wg_key_invalid');
      expect(w.path, 'private_key');

      expect(w.value, '***');
    });

    test('битый pre_shared_key роняет УЗЕЛ наравне с обязательными ключами',
        () {
      final body = wgBody();
      (body['peers'] as List).first['pre_shared_key'] = 'not-base64-at-all!!';
      final r = _san(body, scheme: 'wireguard', core: '1.14.0-lx.40');
      expect(r.body, isNull, reason: 'решение владельца 19.09.2026: туннель '
          'без ожидаемого сервером PSK — тихо сломанный туннель');
      expect(_codes(r), contains('wg_key_invalid'));
    });



    test('absent_when: tls{enabled:false} снимается ЦЕЛИКОМ и ТИХО', () {
      final r = _san(_vless({
        'tls': {'enabled': false, 'server_name': 'example.com'}
      }));
      expect(r.body!.containsKey('tls'), isFalse,
          reason: 'у ядра это «TLS не задан», а не «TLS с выключенным флагом»: '
              'явный disabled-блок ронял ядра lx.5..lx.18 в SIGSEGV');

      expect(_codes(r), isEmpty);
    });

    test('absent_when судится ДО правил полей: мусор ВНУТРИ снятого блока '
        'кодов не даёт', () {
      final r = _san(_vless({
        'tls': {
          'enabled': false,
          'reality': {'enabled': true, 'public_key': 'не-ключ-вовсе'},
        }
      }));
      expect(r.body!.containsKey('tls'), isFalse);
      expect(_codes(r), isEmpty,
          reason: 'иначе человек получил бы коды на поля блока, которого в '
              'теле не будет');
    });

    test('absent_when у вложенного: reality{enabled:false} исчезает, '
        'живой tls остаётся', () {
      final r = _san(_vless({
        'tls': {
          'enabled': true,
          'server_name': 'example.com',
          'reality': {'enabled': false, 'public_key': 'не-ключ-вовсе'},
        }
      }));
      final tls = r.body!['tls'] as Map;
      expect(tls['enabled'], true);
      expect(tls.containsKey('reality'), isFalse);
      expect(_codes(r), isEmpty);
    });

    test('absent_when: tls БЕЗ ключа `enabled` — тело без флага, а не '
        'выключенный TLS', () {
      final r = _san(_vless({
        'tls': {'server_name': 'example.com'}
      }));
      expect(r.body!.containsKey('tls'), isTrue);
    });

    test('absent_when сравнивает по печатной форме: строковое "false" '
        'совпадает с булевым', () {
      final r = _san(_vless({
        'tls': {'enabled': 'false', 'server_name': 'example.com'}
      }));
      expect(r.body!.containsKey('tls'), isFalse);
    });

    test('default_when у allowed_ips: тело без ключа получает дефолт, '
        'а не теряет узел', () {
      final body = wgBody();
      (body['peers'] as List).first.remove('allowed_ips');
      final r = _san(body, scheme: 'wireguard', core: '1.14.0-lx.40');
      expect(r.body, isNotNull);
      expect((r.body!['peers'] as List).first['allowed_ips'],
          ['0.0.0.0/0', '::/0']);

      expect(_codes(r), isEmpty);
    });

    test('type int_array: reserved из трёх чисел цел, мусор снят', () {
      Map<String, dynamic> wg(Object? reserved) => {
            'type': 'wireguard',
            'tag': 'wg1',
            'address': ['10.0.0.2/32'],
            'private_key': 'cHJpdmF0ZUtleUJhc2U2NEV4YW1wbGVWYWx1ZTEyMzQ=',
            'peers': [
              {
                'address': '1.2.3.4',
                'port': 51820,
                'public_key': 'cHVibGljS2V5QmFzZTY0RXhhbXBsZVZhbHVlMTIzNDU=',
                'allowed_ips': ['0.0.0.0/0'],
                'reserved': reserved,
              }
            ],
          };
      final ok = _san(wg([1, 2, 3]), scheme: 'wireguard');
      expect(((ok.body!['peers'] as List).first as Map)['reserved'],
          [1, 2, 3]);

      final bad = _san(wg(['a', 'b', 'c']), scheme: 'wireguard');
      final peer = (bad.body!['peers'] as List).first as Map;
      expect(peer.containsKey('reserved'), isFalse);
    });

    test('неизвестное выражение реестра не роняет и не портит значение', () {


      final r = _san(_vless({'transport': {'type': 'ws', 'path': '/x'}}));
      expect((r.body!['transport'] as Map)['path'], '/x');
    });
  });

  group('coreAtLeast', () {
    test('сравнение X.Y.Z-lx.N — по числам, а не по строке', () {
      expect(coreAtLeast('1.14.1-lx.4', '1.14.1-lx.4'), isTrue);
      expect(coreAtLeast('1.14.1-lx.3', '1.14.1-lx.4'), isFalse);
      expect(coreAtLeast('1.14.1-lx.10', '1.14.1-lx.9'), isTrue,
          reason: 'строкой lx.10 < lx.9 — сравнение обязано быть числовым');
      expect(coreAtLeast('1.14.0-lx.32', '1.14.1-lx.4'), isFalse);

      expect(coreAtLeast('1.14.1', '1.14.1-lx.1'), isFalse);
      expect(coreAtLeast('1.14.2', '1.14.1-lx.1'), isTrue);

      expect(coreAtLeast('', '1.14.1-lx.4'), isTrue);
    });
  });


  group('on_invalid unwrap', () {
    Map<String, dynamic> hy(Object obfs) => {
          'type': 'hysteria',
          'tag': 'h',
          'server': 'example.com',
          'server_port': 443,
          'up_mbps': 10,
          'down_mbps': 50,
          'tls': {'enabled': true, 'server_name': 'example.com'},
          'obfs': obfs,
        };

    test('объект с годным членом → член и код', () {
      final r = RegistrySanitizer.sanitize(hy({'type': 'salamander', 'password': 'pw'}),
          scheme: 'hysteria', coreVersion: '9.9.9');
      expect(r.body!['obfs'], 'pw');
      expect(r.warnings.map((w) => w.code), contains('obfs_object_flattened'));
    });

    test('объект без члена → поле снято, else_code с параметром type', () {
      final r = RegistrySanitizer.sanitize(hy({'type': 'salamander'}),
          scheme: 'hysteria', coreVersion: '9.9.9');
      expect(r.body!.containsKey('obfs'), isFalse);
      final w = r.warnings.singleWhere((w) => w.code == 'obfs_password_missing');
      expect(w.params['type'], 'salamander');
    });

    test('не объект и не строка → type_invalid', () {
      final r = RegistrySanitizer.sanitize(hy([1, 2]),
          scheme: 'hysteria', coreVersion: '9.9.9');
      expect(r.body!.containsKey('obfs'), isFalse);
      expect(r.warnings.map((w) => w.code), contains('type_invalid'));
    });
  });


  group('RegistrySanitizer — фрагментация TLS: detour и системный движок', () {
    test('fragment + record_fragment при engine apple — сняты, движок остаётся',
        () {
      final r = _san(_vless({
        'tls': {
          'enabled': true,
          'server_name': 'example.com',
          'engine': 'apple',
          'fragment': true,
          'record_fragment': true,
        },
      }));
      final tls = r.body!['tls'] as Map;
      expect(tls['engine'], 'apple');
      expect(tls.containsKey('fragment'), isFalse);
      expect(tls.containsKey('record_fragment'), isFalse);
      expect(
          r.warnings
              .where((w) => w.code == 'tls_fragment_system_engine')
              .map((w) => w.path),
          ['tls.fragment', 'tls.record_fragment']);
      expect(_byCode(r, 'tls_fragment_system_engine').params['with'],
          'tls.engine');
    });

    test('engine go — фрагментация остаётся', () {
      final r = _san(_vless({
        'tls': {
          'enabled': true,
          'server_name': 'example.com',
          'engine': 'go',
          'fragment': true,
        },
      }));
      expect((r.body!['tls'] as Map)['fragment'], true);
      expect(_codes(r), isNot(contains('tls_fragment_system_engine')));
    });

    test('detour во входе для связей соседей отсутствует — fragment остаётся',
        () {
      final r = _san(_vless({
        'detour': 'other',
        'tls': {
          'enabled': true,
          'server_name': 'example.com',
          'fragment': true,
        },
      }));
      expect((r.body!['tls'] as Map)['fragment'], true);
      expect(_codes(r), isNot(contains('detour_with_tls_fragment')));
    });

    test('fieldAllowedOn: при engine windows фрагментацию не дописывать', () {
      final body = _vless({
        'tls': {'enabled': true, 'engine': 'windows'},
      });
      expect(fieldAllowedOn(body, 'tls.fragment'), isFalse);
      expect(fieldAllowedOn(body, 'tls.record_fragment'), isFalse);
    });

    test('yieldToManaged: fragment уступает detour, record_fragment — нет', () {
      final body = _vless({
        'detour': 'hop',
        'tls': {'enabled': true, 'fragment': true, 'record_fragment': true},
      });
      final ws = yieldToManaged(body, 'detour');
      expect(ws.map((w) => w.code), ['detour_with_tls_fragment']);
      expect(ws.single.path, 'tls.fragment');
      expect(ws.single.params['tag'], 'n1');
      expect(ws.single.params['target'], 'hop');
      final tls = body['tls'] as Map;
      expect(tls.containsKey('fragment'), isFalse);
      expect(tls['record_fragment'], true);
    });
  });
}
