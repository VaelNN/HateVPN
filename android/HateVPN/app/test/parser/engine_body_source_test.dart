import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/services/contract/body_sanitizer.dart';
import 'package:lxbox/services/parser/engine/engine_mapper.dart';
import 'package:lxbox/services/parser/engine/section_loader.dart';

import 'engine_test_setup.dart';









void main() {
  setUpAll(loadEngineSections);

  test('секция объявляет body_source, и он доезжает до маппинга', () {
    final section = MapperSections.I.sectionFor('uri', 'trojan');
    expect(section, isNotNull);
    expect(section!.bodySource, 'uri',
        reason: 'секция обязана называть свой вид источника');

    final mapping =
        mapViaEngine('trojan://pw@example.com:443?security=tls#n', 'trojan')!;
    expect(mapping.bodySource, BodySource.uri,
        reason: 'вход из секции обязан доехать до конвейера — именно его '
            'конвейер передаёт санитайзеру');
  });

  group('BodySource.byRegistryName — словарь sources реестра', () {
    const cases = <String, BodySource>{
      'uri': BodySource.uri,
      'singbox': BodySource.singbox,
      'xray': BodySource.xray,
      'wgconf': BodySource.wgconf,
      'amnezia': BodySource.amnezia,
    };
    cases.forEach((name, want) {
      test('«$name» → $want', () {
        expect(BodySource.byRegistryName(name), want);
      });
    });



    test('незнакомое имя — other, без падения', () {
      expect(BodySource.byRegistryName('clash'), BodySource.other);
      expect(BodySource.byRegistryName(''), BodySource.other);
      expect(BodySource.byRegistryName(null), BodySource.other);
    });
  });

  test('расширение набора не трогает правило except_sources', () {


    const except = ['singbox'];
    expect(except.contains(BodySource.uri.registryName), isFalse);
    expect(except.contains(BodySource.wgconf.registryName), isFalse);
    expect(except.contains(BodySource.other.registryName), isFalse);
    expect(except.contains(BodySource.singbox.registryName), isTrue);
  });
}
