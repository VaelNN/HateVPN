import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/services/parser/uri_utils.dart';

import 'engine_test_setup.dart';
import 'parse_link_as.dart';
import 'package:lxbox/models/node_spec.dart';


const _validPbk = 'AwoRGB8mLTQ7QklQV15lbHN6gYiPlp2kq7K5wMfO1dw';





void main() {


  setUpAll(loadEngineSections);

  group('§343 normalizeRealityShortId', () {
    test('валидные чётные проходят как есть (lower-case)', () {
      expect(normalizeRealityShortId('abcd1234'), 'abcd1234');
      expect(normalizeRealityShortId('ABCD1234'), 'abcd1234');
      expect(normalizeRealityShortId('0123456789abcdef'), '0123456789abcdef');
      expect(normalizeRealityShortId('00'), '00');
      expect(normalizeRealityShortId(''), '');
      expect(normalizeRealityShortId('  abcd  '), 'abcd');
    });

    test('БОЕВОЙ КЕЙС: нечётная длина → отброс целиком', () {

      expect(normalizeRealityShortId('abc'), '');
      expect(normalizeRealityShortId('12345'), '');
      expect(normalizeRealityShortId('0'), '');
    });

    test('нечётность ПОСЛЕ чистки non-hex мусора → отброс', () {

      expect(normalizeRealityShortId('ab-cd-e'), '');

      expect(normalizeRealityShortId('g1g2g3'), '');
    });

    test('длиннее 16 hex-символов → отброс (раньше — тихая обрезка)', () {


      expect(normalizeRealityShortId('0123456789abcdef0'), '');
      expect(normalizeRealityShortId('0123456789abcdef01'), '');
    });

    test('чистка non-hex при чётном остатке сохраняется (старое поведение)', () {
      expect(normalizeRealityShortId('0x1a2'), '01a2');
    });

    test('парсер: vless URI с нечётным sid → REALITY жив, sid пуст', () {
      final spec = parseLinkAs<VlessSpec>(
        'vless://u@h:443?type=tcp&security=reality&pbk=$_validPbk&sid=abc&sni=w.example.com#L',
      );
      expect(spec, isNotNull);
      expect(spec!.tls.reality, isNotNull);
      expect(spec.tls.reality!.shortId, '',
          reason: 'битый sid отброшен, нода не роняет конфиг');
    });
  });
}
