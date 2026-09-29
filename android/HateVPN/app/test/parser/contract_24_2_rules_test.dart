import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../contract_paths.dart';
import 'package:lxbox/models/node_spec.dart';
import 'package:lxbox/models/node_warning.dart';
import 'package:lxbox/models/template_vars.dart';
import 'package:lxbox/models/transport_spec.dart';
import 'package:lxbox/services/node_hash.dart';
import 'package:lxbox/services/parser/json_parsers.dart';
import 'package:lxbox/services/parser/uri_parsers.dart';
import 'parse_link_as.dart';










List<String> _codes(NodeSpec spec) => [
      for (final w in spec.warnings)
        if (w is RegistryWarning) w.code else w.runtimeType.toString(),
    ];

void main() {










  setUpAll(loadTestRegistry);


  group('§24.2 п. 7.1 — hellorandom*/hellorandomized* разводятся данными', () {








    test('каждый префикс даёт СВОЙ канон', () {
      const cases = {
        'hellorandom': 'random',
        'hellorandom_120': 'random',
        'hellorandomized': 'randomized',
        'hellorandomizedalpn': 'randomized',
        'hellorandomizednoalpn': 'randomized',
      };
      for (final e in cases.entries) {
        final spec = parseLinkAs<VlessSpec>(
            'vless://11111111-1111-1111-1111-111111111111@e.example.com:443?security=tls&fp=${e.key}#n');
        expect(spec!.tls.fingerprint, e.value, reason: e.key);

        expect(_codes(spec), isNot(contains('UnknownFingerprintWarning')),
            reason: e.key);
      }
    });
  });

  group('§24.2 п. 7.5 — anytls мусорный SNI', () {
    test('имя без точки и двоеточия заменяется адресом сервера', () {
      final spec =
          parseLinkAs<AnyTlsSpec>('anytls://pass123@a.example.com:443?sni=%F0%9F%94%92#n');
      expect(spec!.tls.serverName, 'a.example.com');
    });

    test('нормальный SNI не трогается', () {
      final spec =
          parseLinkAs<AnyTlsSpec>('anytls://pass123@a.example.com:443?sni=cover.example#n');
      expect(spec!.tls.serverName, 'cover.example');
    });
  });

  group('§24.2 п. 7.7 — дефолты TUIC не пишутся', () {
    test('без congestion_control/alpn в ссылке поля не эмитятся', () {
      final spec = parseLinkAs<TuicSpec>(
          'tuic://11111111-2222-3333-4444-555555555555:pass123@t.example.com:443#n');
      final entry = spec!.emit(TemplateVars.empty).map;
      expect(entry.containsKey('congestion_control'), isFalse);
      expect((entry['tls'] as Map).containsKey('alpn'), isFalse);
    });
  });

  group('§24.2 п. 7.8 — TUIC udp_relay_mode', () {
    test('мусор снимается с кодом, а не подменяется на native', () {
      final spec = parseLinkAs<TuicSpec>(
          'tuic://11111111-2222-3333-4444-555555555555:pass123@t.example.com:443?udp_relay_mode=quiс#n');
      expect(spec!.udpRelayMode, isNull);
      expect(_codes(spec), contains('tuic_udp_relay_mode_invalid'));
      expect(spec.emit(TemplateVars.empty).map.containsKey('udp_relay_mode'),
          isFalse);
    });

    test('валидные значения проходят без кода', () {
      for (final v in const ['native', 'quic']) {
        final spec = parseLinkAs<TuicSpec>(
            'tuic://11111111-2222-3333-4444-555555555555:pass123@t.example.com:443?udp_relay_mode=$v#n');
        expect(spec!.udpRelayMode, v);
        expect(_codes(spec), isNot(contains('tuic_udp_relay_mode_invalid')));
      }
    });
  });

  group('§24.2 п. 7.9 — пустой пароль', () {
    test('anytls без пароля отбраковывается', () {
      expect(parseLinkAs<AnyTlsSpec>('anytls://@a.example.com:443#n'), isNull);
    });










    test('tuic без пароля остаётся узлом и получает код', () {
      final spec = parseLinkAs<TuicSpec>(
          'tuic://11111111-2222-3333-4444-555555555555:@t.example.com:443#n');
      expect(spec, isNotNull);
      expect(_codes(spec!), contains('password_empty'));
    });
  });

  group('§24.2 п. 7.10 — ss legacy stream-шифры', () {

    String ssUri(String method) =>
        'ss://${base64.encode(utf8.encode('$method:pass123'))}'
        '@s.example.com:8388#n';

    test('узел живёт и получает info-код ss_method_legacy', () {
      for (final m in const [
        'aes-128-ctr',
        'aes-192-ctr',
        'aes-256-ctr',
        'aes-128-cfb',
        'aes-192-cfb',
        'aes-256-cfb',
        'rc4-md5',
        'chacha20-ietf',
        'xchacha20',
      ]) {
        final spec = parseLinkAs<ShadowsocksSpec>(ssUri(m));
        expect(spec, isNotNull, reason: m);
        expect(spec!.method, m, reason: m);
        expect(_codes(spec), contains('ss_method_legacy'), reason: m);
      }
    });

    test('AEAD-методы кода не получают', () {
      final spec = parseLinkAs<ShadowsocksSpec>(ssUri('aes-256-gcm'));
      expect(_codes(spec!), isNot(contains('ss_method_legacy')));
    });

    test('метод вне 18 значений ядра по-прежнему роняет узел', () {
      expect(parseLinkAs<ShadowsocksSpec>(ssUri('made-up-cipher')), isNull);
    });
  });

  group('§24.2 п. 7.13 — splithttp = алиас xhttp', () {















    test('URI type=splithttp даёт транспорт xhttp', () {
      final spec = parseLinkAs<VlessSpec>(
          'vless://11111111-1111-1111-1111-111111111111@x.example.com:443?security=tls&type=splithttp&path=%2Fv1#n');
      expect(spec!.transport, isA<XhttpTransport>());
    });

    test('splithttp и xhttp дают одно тело и одну identity', () {
      const base =
          'vless://11111111-1111-1111-1111-111111111111@x.example.com:443?security=tls&path=%2Fx&host=h';
      final alias = parseLinkAs<VlessSpec>('$base&type=splithttp#n');
      final canon = parseLinkAs<VlessSpec>('$base&type=xhttp#n');
      expect(alias, isNotNull);
      expect(canon, isNotNull);
      final aliasBody = alias!.emit(TemplateVars.empty).map;
      expect((aliasBody['transport'] as Map?)?['type'], 'xhttp');
      expect(jsonEncode(aliasBody),
          jsonEncode(canon!.emit(TemplateVars.empty).map));

      expect(legacyNodeIdentityHash(alias), legacyNodeIdentityHash(canon));
    });

    test('sing-box JSON transport.type=splithttp', () {
      final spec = parseSingboxEntry({
        'type': 'vless',
        'tag': 'n',
        'server': 'x.example.com',
        'server_port': 443,
        'uuid': '11111111-1111-1111-1111-111111111111',
        'transport': {'type': 'splithttp', 'path': '/v1'},
      });
      expect((spec as VlessSpec).transport, isA<XhttpTransport>());
    });
  });

  group('§24.2 п. 7.15 — socks password-only', () {
    test('пароль без имени эмитится как :pass@', () {
      final spec = SocksSpec(
        id: 'i',
        tag: 't',
        label: 'l',
        server: 's.example.com',
        port: 1080,
        rawSource: '',
        username: '',
        password: 'pass123',
      );
      expect(spec.toUri(), contains(':pass123@'));

      final back = parseUri(spec.toUri()) as SocksSpec;
      expect(back.password, 'pass123');
    });
  });

  group('§24.6 — url_path', () {
    test('битый percent в пути снимается с type_invalid, узел живёт', () {
      final spec = parseLinkAs<TrojanSpec>(
          'trojan://pass123@t.example.com:443?type=ws&path=%2Fx%25zz&security=tls#n');
      expect(spec, isNotNull);
      expect((spec!.transport as WsTransport).path, '');
      expect(_codes(spec), contains('type_invalid'));
    });

    test('корректный percent-путь не трогается', () {
      final spec = parseLinkAs<TrojanSpec>(
          'trojan://pass123@t.example.com:443?type=ws&path=%2Fx%2Fy&security=tls#n');
      expect((spec!.transport as WsTransport).path, '/x/y');
      expect(_codes(spec), isNot(contains('type_invalid')));
    });
  });

  group('§24.6 — пустой reality.short_id не эмитится', () {
    test('ключа в теле нет', () {
      final spec = parseLinkAs<VlessSpec>(
          'vless://11111111-1111-1111-1111-111111111111@r.example.com:443?security=reality'
          '&pbk=AwoRGB8mLTQ7QklQV15lbHN6gYiPlp2kq7K5wMfO1dw&sni=cover.example#n');
      final tls = spec!.emit(TemplateVars.empty).map['tls'] as Map;
      expect((tls['reality'] as Map).containsKey('short_id'), isFalse);
    });
  });
}
