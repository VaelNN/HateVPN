import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/node_spec.dart';
import 'package:lxbox/models/template_vars.dart';
import 'package:lxbox/models/tls_spec.dart';
import 'package:lxbox/services/parser/json_parsers.dart';
import 'package:lxbox/services/parser/singbox_config.dart';

import 'engine_test_setup.dart';
import 'parse_link_as.dart';


const _validPbk = 'AwoRGB8mLTQ7QklQV15lbHN6gYiPlp2kq7K5wMfO1dw';

Map<String, dynamic> _vlessEntry(Map<String, dynamic> reality) => {
      'type': 'vless',
      'tag': 't',
      'server': 'h',
      'server_port': 443,
      'uuid': '0aa41f0a-6d92-4f74-8b13-4d0d5b6cbb6c',
      'tls': {
        'enabled': true,
        'server_name': 'x.com',


        'utls': {'enabled': true, 'fingerprint': 'chrome'},
        'reality': {'enabled': true, 'public_key': _validPbk, ...reality},
      },
    };

Map<String, dynamic> _emittedReality(NodeSpec n) =>
    ((n.emitRaw(const TemplateVars()).map['tls'] as Map)['reality']
        as Map)
        .cast<String, dynamic>();




NodeSpec _viaSingboxJson(Map<String, dynamic> entry) => parseSingboxConfigs([
      {
        'outbounds': [entry],
      },
    ]).single;




void main() {


  setUpAll(loadEngineSections);

  group('§457 sing-box JSON', () {
    test('key_share: hybrid — в модели и в эмите', () {
      final spec = parseSingboxEntry(_vlessEntry({'key_share': 'hybrid'}))!
          as VlessSpec;
      expect(spec.tls.reality!.keyShare, 'hybrid');
      expect(_emittedReality(spec)['key_share'], 'hybrid');
    });

    test('key_share: classical — в модели и в эмите', () {
      final spec = parseSingboxEntry(_vlessEntry({'key_share': 'classical'}))!
          as VlessSpec;
      expect(spec.tls.reality!.keyShare, 'classical');
      expect(_emittedReality(spec)['key_share'], 'classical');
    });

    test('порядок ключей эмита: enabled, public_key, short_id, key_share', () {
      final spec = parseSingboxEntry(
          _vlessEntry({'short_id': 'abcd', 'key_share': 'hybrid'}))! as VlessSpec;
      expect(_emittedReality(spec).keys.toList(),
          ['enabled', 'public_key', 'short_id', 'key_share']);
    });




    test('§459 регистр нормализуется — Hybrid/HYBRID/пробелы дают hybrid', () {
      for (final good in <String>['Hybrid', 'HYBRID', ' hybrid ', ' Classical']) {
        final spec = _viaSingboxJson(_vlessEntry({'key_share': good}))
            as VlessSpec;
        final want = good.trim().toLowerCase();
        expect(spec.tls.reality!.keyShare, want, reason: 'good=$good');
        expect(_emittedReality(spec)['key_share'], want, reason: 'good=$good');
      }
    });

    test('вне enum — поле отброшено молча, узел жив', () {
      for (final bad in <dynamic>['x', 1, '', '  ', true]) {
        final spec = _viaSingboxJson(_vlessEntry({'key_share': bad}))
            as VlessSpec;
        expect(spec.tls.reality, isNotNull, reason: 'bad=$bad: REALITY цел');
        expect(spec.tls.reality!.keyShare, isNull, reason: 'bad=$bad');
        expect(_emittedReality(spec).containsKey('key_share'), isFalse,
            reason: 'bad=$bad: ядро отвергло бы весь конфиг');
      }
    });

    test('без поля — эмит без key_share; пустой short_id не пишется', () {



      final spec = parseSingboxEntry(_vlessEntry(const {}))! as VlessSpec;
      expect(spec.tls.reality!.keyShare, isNull);
      expect(_emittedReality(spec).keys.toList(), ['enabled', 'public_key']);
    });

    test('hysteria2 с reality — reality срезан, как и раньше (§282)', () {
      final spec = _viaSingboxJson({
        'type': 'hysteria2',
        'tag': 'h2',
        'server': 'h',
        'server_port': 443,
        'password': 'p',
        'tls': {
          'enabled': true,
          'server_name': 'x.com',
          'reality': {
            'enabled': true,
            'public_key': _validPbk,
            'key_share': 'hybrid',
          },
        },
      });



      expect((spec as Hysteria2Spec).tls.reality, isNull);
      expect(
          (spec.emitRaw(const TemplateVars()).map['tls'] as Map)
              .containsKey('reality'),
          isFalse);
    });
  });

  group('§457 share-URI', () {
    test('key_share=classical при валидном pbk → модель и обратно в toUri()',
        () {
      final spec = parseLinkAs<VlessSpec>(
          'vless://u@h:443?type=tcp&security=reality&pbk=$_validPbk'
          '&sid=abcd&key_share=classical#L')!;
      expect(spec.tls.reality!.keyShare, 'classical');
      expect(spec.toUri(), contains('key_share=classical'));
      expect(parseLinkAs<VlessSpec>(spec.toUri())!.tls.reality!.keyShare, 'classical');
    });

    test('key_share=hybrid — то же', () {
      final spec = parseLinkAs<VlessSpec>(
          'vless://u@h:443?type=tcp&security=reality&pbk=$_validPbk'
          '&key_share=hybrid#L')!;
      expect(spec.tls.reality!.keyShare, 'hybrid');
      expect(spec.toUri(), contains('key_share=hybrid'));
    });

    test('key_share без валидного pbk — игнорируется', () {
      final spec = parseLinkAs<VlessSpec>(
          'vless://u@h:443?type=tcp&security=reality&pbk=enabled'
          '&key_share=classical#L')!;
      expect(spec.tls.reality, isNull);
      expect(spec.toUri(), isNot(contains('key_share')));
    });

    test('§459 регистр нормализуется — Classical/HYBRID из ссылки принимаются',
        () {
      for (final good in <String>['Classical', 'HYBRID', '%20hybrid%20']) {
        final spec = parseLinkAs<VlessSpec>(
            'vless://u@h:443?type=tcp&security=reality&pbk=$_validPbk'
            '&key_share=$good#L')!;
        final want = Uri.decodeComponent(good).trim().toLowerCase();
        expect(spec.tls.reality!.keyShare, want, reason: 'good=$good');
        expect(spec.toUri(), contains('key_share=$want'), reason: 'good=$good');
      }
    });

    test('вне enum — поля нет, узел жив', () {
      for (final bad in ['x', '1', '']) {
        final spec = parseLinkAs<VlessSpec>(
            'vless://u@h:443?type=tcp&security=reality&pbk=$_validPbk'
            '&key_share=$bad#L')!;
        expect(spec.tls.reality, isNotNull, reason: 'bad=$bad');
        expect(spec.tls.reality!.keyShare, isNull, reason: 'bad=$bad');
        expect(spec.toUri(), isNot(contains('key_share')), reason: 'bad=$bad');
      }
    });

    test('узел без поля — URI прежний', () {
      final spec = parseLinkAs<VlessSpec>(
          'vless://u@h:443?type=tcp&security=reality&pbk=$_validPbk&sid=abcd#L')!;
      expect(spec.tls.reality!.keyShare, isNull);
      expect(spec.toUri(), isNot(contains('key_share')));
    });

    test('anytls несёт key_share тем же путём, что и vless', () {
      final spec = parseLinkAs<AnyTlsSpec>(
          'anytls://p@h:443?security=reality&pbk=$_validPbk'
          '&key_share=hybrid#L')!;
      expect(spec.tls.reality!.keyShare, 'hybrid');
      expect(spec.toUri(), contains('key_share=hybrid'));
    });
  });

  group('§457 модель', () {
    test('key_share входит в равенство', () {
      const a = RealitySpec(publicKey: _validPbk, shortId: '');
      const b = RealitySpec(
          publicKey: _validPbk, shortId: '', keyShare: 'hybrid');
      expect(a == b, isFalse);
      expect(a.hashCode == b.hashCode, isFalse);
      expect(
          b ==
              const RealitySpec(
                  publicKey: _validPbk, shortId: '', keyShare: 'hybrid'),
          isTrue);
    });

    test('пустая строка не эмитится (omitempty ядра)', () {
      const r =
          RealitySpec(publicKey: _validPbk, shortId: '', keyShare: '');
      expect(r.toSingbox().containsKey('key_share'), isFalse);
    });
  });
}
