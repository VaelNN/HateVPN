








import 'package:flutter_test/flutter_test.dart';
import '../contract_paths.dart';
import 'package:lxbox/models/node_warning.dart';
import 'package:lxbox/models/singbox_entry.dart';
import 'package:lxbox/services/builder/registry_gate.dart';

import '../storage_migration/golden_harness.dart';



const _core = kGoldenCoreVersion;

void main() {

  setUpAll(loadTestRegistry);


  group('гард реестра на сборке', () {
    test('naive из JSON-источника: foo и tls.insecure сняты, certificate цел',
        () {

      final entry = Outbound(<String, dynamic>{
        'type': 'naive',
        'tag': 'naive-json',
        'server': '1.2.3.4',
        'server_port': 443,
        'username': 'u',
        'password': 'p',
        'foo': 1,
        'tls': {
          'enabled': true,
          'server_name': 's.example.com',
          'insecure': true,
          'certificate': '-----BEGIN CERTIFICATE-----',
        },
      });

      final report = applyRegistryGate([entry], coreVersion: _core);

      expect(report.dropped, isEmpty, reason: 'узел остаётся в конфиге');
      expect(entry.map.containsKey('foo'), isFalse);
      final tls = entry.map['tls'] as Map;
      expect(tls.containsKey('insecure'), isFalse,
          reason: 'naive не читает insecure — у ядра это фатал старта');
      expect(tls['certificate'], '-----BEGIN CERTIFICATE-----',
          reason: 'certificate naive читает — поле обязано уцелеть');
      expect(tls['server_name'], 's.example.com');


      expect(report.warnings.length, 2, reason: report.warnings.join('\n'));
      final joined = report.warnings.join('\n');
      expect(joined, contains('naive-json: '));








      expect(joined, contains('[foo=1]'));
      expect(joined, contains('[tls.insecure=true]'));

      expect(joined, isNot(contains('unknown_key')));
      expect(joined, isNot(contains('tls_field_unsupported_naive')));
      expect(joined, contains('unknown key'));
      expect(joined, contains('naive: TLS field tls.insecure removed'));
    });

    test('запись без обязательного поля снимается целиком', () {
      final entry = Outbound(<String, dynamic>{
        'type': 'vless',
        'tag': 'no-uuid',
        'server': 'example.com',
        'server_port': 443,
      });
      final report = applyRegistryGate([entry], coreVersion: _core);
      expect(report.dropped, [entry]);
      expect(report.warnings.single, contains('no-uuid: '));
    });










    test('§477 — узел с негодным encryption не едет в ядро', () {
      final entry = Outbound(<String, dynamic>{
        'type': 'vless',
        'tag': 'verbatim-enc-broken',
        'server': 'example.com',
        'server_port': 443,
        'uuid': '11111111-1111-1111-1111-111111111111',

        'encryption': 'mlkem768x25519plus.native.0rtt',
      });
      final report = applyRegistryGate([entry], coreVersion: _core);
      expect(report.dropped, [entry],
          reason: 'запись обязана быть снята целиком, а не лишена поля');

      final line = report.warnings.single;
      expect(line, contains('verbatim-enc-broken: '));
      expect(line, contains('[encryption=mlkem768x25519plus.native.0rtt]'));
      expect(line, isNot(contains('vless_encryption_invalid')),
          reason: 'человеку — текст реестра, а не голый код');
    });

    test('§477 — дословный JSON-узел с годным encryption проходит нетронутым',
        () {
      const enc = 'mlkem768x25519plus.native.0rtt.'
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      final body = <String, dynamic>{
        'type': 'vless',
        'tag': 'verbatim-enc-ok',
        'server': 'example.com',
        'server_port': 443,
        'uuid': '11111111-1111-1111-1111-111111111111',
        'encryption': enc,
      };
      final entry = Outbound(Map<String, dynamic>.from(body));
      entry.authored = true;
      final report = applyRegistryGate([entry], coreVersion: _core);
      expect(report.dropped, isEmpty);
      expect(report.warnings, isEmpty);
      expect(entry.map, body, reason: '§455 — тело едет дословно');
    });

    test('валидное тело гард не трогает и молчит', () {
      final body = <String, dynamic>{
        'type': 'vless',
        'tag': 'ok',
        'server': 'example.com',
        'server_port': 443,
        'uuid': '11111111-1111-1111-1111-111111111111',
        'tls': {'enabled': true, 'server_name': 'example.com'},
      };
      final entry = Outbound(Map<String, dynamic>.from(body));
      final report = applyRegistryGate([entry], coreVersion: _core);
      expect(report.warnings, isEmpty);
      expect(report.dropped, isEmpty);
      expect(entry.map, body);
    });





    Endpoint awgEndpoint(int? mtu, {String tag = 'awg-ep'}) =>
        Endpoint(<String, dynamic>{
          'type': 'wireguard',
          'tag': tag,
          'mtu': ?mtu,
          'address': ['10.0.0.2/32'],
          'private_key': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaA=',
          'jc': 10,
          'peers': [
            {
              'address': 'example-3.com',
              'port': 51820,
              'public_key': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbA=',
              'allowed_ips': ['0.0.0.0/0'],
            },
          ],
        });

    test('§455 — дословному JSON-телу гард MTU НЕ подменяет, только info', () {
      final entry = awgEndpoint(1420);
      entry.authored = true;
      final report = applyRegistryGate([entry], coreVersion: _core);



      expect(entry.map['mtu'], 1420);
      expect(report.dropped, isEmpty);


      expect(report.warnings.single, contains('awg-ep: '));
      expect(report.warnings.single, contains('[mtu=1420]'));
      expect(report.warnings.single, contains('MTU above 1280'));
    });

    test('то же тело БЕЗ метки дословности: MTU заменён потолком', () {



      final entry = awgEndpoint(1420);
      final report = applyRegistryGate([entry], coreVersion: _core);

      expect(entry.map['mtu'], 1280);
      expect(report.warnings.single, contains('[mtu=1420]'),
          reason: 'в коде — ИСХОДНОЕ значение, а не то, чем его заменили');
      expect(report.warnings.single, contains('MTU lowered to 1280'));
    });

    test('обычный WireGuard: потолка нет ни на каком входе', () {


      final entry = Endpoint(<String, dynamic>{
        'type': 'wireguard',
        'tag': 'plain-wg',
        'mtu': 1420,
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
      });
      final report = applyRegistryGate([entry], coreVersion: _core);
      expect(entry.map['mtu'], 1420);
      expect(report.warnings, isEmpty);
    });

    test('jc: 0 — законный AWG-узел, потолок с него не снимается', () {




      final entry = awgEndpoint(1420, tag: 'awg-jc0');
      entry.map['jc'] = 0;
      final report = applyRegistryGate([entry], coreVersion: _core);
      expect(entry.map['mtu'], 1280);
      expect(report.warnings.single, contains('awg-jc0: '));
    });





    test('MTU не задан — дефолт 1280 у обычного тела, авторское как есть', () {
      final plain = awgEndpoint(null);
      expect(applyRegistryGate([plain], coreVersion: _core).warnings, isEmpty);
      expect(plain.map['mtu'], 1280);

      final entry = awgEndpoint(null);
      entry.authored = true;
      final report = applyRegistryGate([entry], coreVersion: _core);
      expect(entry.map.containsKey('mtu'), isFalse);
      expect(report.warnings, isEmpty);
    });

    group('§577 — авторское тело: реестр сообщает, не правит', () {
      Outbound trojan() => Outbound(<String, dynamic>{
            'type': 'trojan',
            'tag': 'own-trojan',
            'server': 'example-1.com',
            'server_port': 443,
            'password': 'p',
            'foo': 'bar',
            'tls': {'enabled': true, 'server_name': 'example-1.com', 'bar': 1},
          });

      test('мягкое нарушение: тело без изменений, код с applied: false', () {
        final entry = trojan()..authored = true;
        final before = Map<String, dynamic>.from(entry.map)
          ..['tls'] = Map<String, dynamic>.from(entry.map['tls'] as Map);
        final report = applyRegistryGate([entry], coreVersion: _core);
        expect(entry.map, before);
        expect(report.dropped, isEmpty);
        final ws = report.warningsByEmittedTag['own-trojan']!
            .cast<RegistryWarning>();
        expect(ws.map((w) => (w.code, w.path, w.applied)).toSet(), {
          ('unknown_key', 'tls.bar', false),
          ('unknown_key', 'foo', false),
        });
        expect(report.warnings, everyElement(endsWith('(not applied)')));
      });

      test('то же тело обычным: ключи сняты, applied: true', () {
        final entry = trojan();
        final report = applyRegistryGate([entry], coreVersion: _core);
        expect(entry.map.containsKey('foo'), isFalse);
        expect((entry.map['tls'] as Map).containsKey('bar'), isFalse);
        final ws = report.warningsByEmittedTag['own-trojan']!;
        expect(ws.every((w) => w.applied), isTrue);
        expect(report.warnings, everyElement(isNot(contains('not applied'))));
      });

      test('жёсткое нарушение правится: flow вне набора ядра снят', () {
        final entry = Outbound(<String, dynamic>{
          'type': 'vless',
          'tag': 'own-vless',
          'server': 'example-5.com',
          'server_port': 443,
          'uuid': '00000000-0000-4000-8000-000000000582',
          'flow': 'xtls-rprx-direct',
          'foo': 1,
        })
          ..authored = true;
        final report = applyRegistryGate([entry], coreVersion: _core);
        expect(entry.map.containsKey('flow'), isFalse);
        expect(entry.map['foo'], 1, reason: 'мягкое рядом не применяется');
        final ws = report.warningsByEmittedTag['own-vless']!
            .cast<RegistryWarning>();
        expect(ws.firstWhere((w) => w.code == 'flow_deprecated').applied,
            isTrue);
        expect(ws.firstWhere((w) => w.code == 'unknown_key').applied, isFalse);
      });

      test('жёсткое снятие узла: негодный порт снимает запись', () {
        final entry = Outbound(<String, dynamic>{
          'type': 'trojan',
          'tag': 'own-bad-port',
          'server': 'example.com',
          'server_port': 70000,
          'password': 'p',
        })
          ..authored = true;
        final report = applyRegistryGate([entry], coreVersion: _core);
        expect(report.dropped, [entry]);
      });




      test('негодный encryption снимает и авторский узел (core_rejects)', () {
        final entry = Outbound(<String, dynamic>{
          'type': 'vless',
          'tag': 'own-enc',
          'server': 'example.com',
          'server_port': 443,
          'uuid': '11111111-1111-1111-1111-111111111111',
          'encryption': 'mlkem768x25519plus.native.0rtt',
        })
          ..authored = true;
        final report = applyRegistryGate([entry], coreVersion: _core);
        expect(report.dropped, [entry]);
        expect(report.warnings.single, isNot(endsWith('(not applied)')));
      });

      test('запись без type снимается и у авторского тела', () {
        final entry = Outbound(<String, dynamic>{'tag': 'no-type'})
          ..authored = true;
        final report = applyRegistryGate([entry], coreVersion: _core);
        expect(report.dropped, [entry]);
      });
    });

    test('реестр не загружен — гард no-op', () {



      final entry = Outbound(<String, dynamic>{
        'type': 'shadowtls',
        'tag': 'foreign',
        'server': 'example.com',
        'whatever': 1,
      });
      final report = applyRegistryGate([entry], coreVersion: _core);
      expect(report.warnings, isEmpty);
      expect(entry.map['whatever'], 1);
    });
  });



  group('страховка: запись без type в конфиг не уходит', () {
    test('тело чужого диалекта снимается с предупреждением на узле', () {

      final bad = Outbound(<String, dynamic>{
        'tag': 'xray-body',
        'protocol': 'vless',
        'settings': {'vnext': []},
        'streamSettings': {'network': 'tcp'},
      });
      final good = Outbound(<String, dynamic>{
        'type': 'trojan',
        'tag': 'ok',
        'server': 'example.com',
        'server_port': 443,
        'password': 'p',
      });

      final report = applyRegistryGate([bad, good], coreVersion: _core);

      expect(report.dropped, contains(bad));
      expect(report.dropped, isNot(contains(good)));
      expect(report.warnings.where((w) => w.startsWith('xray-body: ')),
          hasLength(1));
    });

    test('пустой и нестроковый type — тоже снимается', () {
      final empty = Outbound(<String, dynamic>{'type': '', 'tag': 'e'});
      final num0 = Outbound(<String, dynamic>{'type': 7, 'tag': 'n'});
      final report =
          applyRegistryGate([empty, num0], coreVersion: _core);
      expect(report.dropped, hasLength(2));
    });
  });

  group('эталоны при загруженном реестре', () {
    for (final name in kStorageFixtures) {
      test('$name: config.json не изменился', () async {
        final box = await StorageSandbox.create();
        addTearDown(box.dispose);
        await box.seed(name);

        final built = await buildGoldenConfig(box);


        expectGolden('$name.config.json', built.configJson);
        expectGolden('$name.config_warnings.json', prettyJson(built.warnings));
      });
    }
  });
}
