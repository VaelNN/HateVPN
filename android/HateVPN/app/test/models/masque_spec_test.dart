import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/node_spec.dart';
import 'package:lxbox/models/node_warning.dart';
import 'package:lxbox/models/singbox_entry.dart';
import 'package:lxbox/models/template_vars.dart';
import 'package:lxbox/services/parser/uri_parsers.dart';

import '../parser/engine_test_setup.dart';
import '../parser/parse_link_as.dart';









void main() {
  setUpAll(loadEngineSections);

  MasqueSpec spec() => MasqueSpec(
        id: 'id1',
        tag: '🔥🎭 WARP (MASQUE)',
        label: '🔥🎭 WARP (MASQUE)',
        server: '162.159.198.1',
        port: 443,
        rawSource: '',
        privateKeyDer: 'PRIVDER==',
        publicKeyDer: 'PUBDER==',
        localAddresses: ['172.16.0.2/32', '2606:4700:110::2/128'],
        vhttp: 'h3',
        mtu: 1280,
        idleTimeout: '10m',
        keepAlive: '45s',
      );

  test('emitMasque даёт Outbound со схемой ядра lx.25-rc.4 (§393)', () {
    final entry = spec().emit(TemplateVars.empty);
    expect(entry, isA<Outbound>());
    final m = entry.map;
    expect(m['type'], 'masque');
    expect(m['server'], '162.159.198.1');
    expect(m['server_port'], 443);
    expect(m['profile'], 'cloudflare');
    expect(m['vhttp'], 'h3');


    expect(m.containsKey('network'), isFalse);
    expect(m.containsKey('sni'), isFalse);
    expect(m['private_key'], 'PRIVDER==');
    expect(m['public_key'], 'PUBDER==');
    expect(m['ip'], '172.16.0.2/32');
    expect(m['ipv6'], '2606:4700:110::2/128');
    expect(m['mtu'], 1280);
    expect(m['idle_timeout'], '10m');
    expect(m['keep_alive_period'], '45s');

    expect(m.containsKey('peers'), isFalse);
    expect(m.containsKey('address'), isFalse);
    expect(m.containsKey('certificate'), isFalse);
  });

  test('URI round-trip: spec.toUri() → parseMasqueUri ≈ spec', () {
    final s = spec();
    final uri = s.toUri();
    expect(uri, startsWith('masque://'));
    final parsed = parseLinkAs<MasqueSpec>(uri);
    expect(parsed, isNotNull);
    expect(parsed!.privateKeyDer, s.privateKeyDer);
    expect(parsed.publicKeyDer, s.publicKeyDer);
    expect(parsed.server, s.server);
    expect(parsed.port, s.port);
    expect(parsed.vhttp, s.vhttp);
    expect(parsed.localAddresses, containsAll(s.localAddresses));
    expect(parsed.idleTimeout, '10m');
    expect(parsed.keepAlive, '45s');
  });

  test('parseUri диспетчеризует masque://', () {
    final parsed = parseUri(spec().toUri());
    expect(parsed, isA<MasqueSpec>());
  });

  test('§393 — SNI и disable_sni уезжают во вложенный tls{}', () {
    final s = MasqueSpec(
      id: 'id1',
      tag: 't',
      label: 't',
      server: '162.159.198.1',
      port: 443,
      rawSource: '',
      privateKeyDer: 'PRIVDER==',
      publicKeyDer: 'PUBDER==',
      localAddresses: ['172.16.0.2/32'],
      vhttp: 'h2',
      sni: 'www.cloudflare.com',
      disableSni: true,
    );
    final m = s.emit(TemplateVars.empty).map;
    expect(m['vhttp'], 'h2');
    expect(m['tls'], {'server_name': 'www.cloudflare.com', 'disable_sni': true});
    expect(m.containsKey('sni'), isFalse);
  });

  test('§393 — пустой SNI не создаёт пустой tls{}', () {
    final m = spec().emit(TemplateVars.empty).map;
    expect(m.containsKey('tls'), isFalse);
  });

  test('§393/0.8.0 (D-078) — URI пишет vhttp=, legacy network= НЕ принимает', () {
    final uri = spec().toUri();
    expect(uri, contains('vhttp=h3'));
    expect(uri, isNot(contains('network=')));




    final legacy = uri.replaceAll('vhttp=h3', 'network=h2');
    expect(parseLinkAs<MasqueSpec>(legacy)!.vhttp, 'h3');


    final both = '$uri&network=h2';
    expect(parseLinkAs<MasqueSpec>(both)!.vhttp, 'h3');
  });

  test('§393 — disable_sni в URI round-trip', () {
    final s = MasqueSpec(
      id: 'id1',
      tag: 't',
      label: 't',
      server: '1.2.3.4',
      port: 443,
      rawSource: '',
      privateKeyDer: 'P==',
      publicKeyDer: 'K==',
      localAddresses: ['172.16.0.2/32'],
      disableSni: true,
    );
    expect(parseLinkAs<MasqueSpec>(s.toUri())!.disableSni, isTrue);





    final stripped = s.toUri().replaceAll(RegExp(r'[?&]disable_sni=[^&#]*'), '');
    expect(stripped, isNot(contains('disable_sni')));
    expect(parseLinkAs<MasqueSpec>(stripped)!.disableSni, isFalse);
  });



  group('§402 vhttp=auto', () {
    test('auto принимается и доезжает до эмиссии', () {
      final parsed = parseLinkAs<MasqueSpec>(
          spec().toUri().replaceAll('vhttp=h3', 'vhttp=auto'))!;
      expect(parsed.vhttp, 'auto');
      expect(parsed.warnings, isEmpty,
          reason: 'значение из тройки контракта — не деградация');
      expect(parsed.emit(TemplateVars.empty).map['vhttp'], 'auto');
    });

    test('без параметра дефолт остаётся ЯВНЫЙ h3, а не auto', () {


      final noParam = spec().toUri().replaceAll('&vhttp=h3', '');
      expect(parseLinkAs<MasqueSpec>(noParam)!.vhttp, 'h3');
    });

    test('мусорное значение → форс h3 + код реестра (SPEC 103 п.5)', () {




      final parsed = parseLinkAs<MasqueSpec>(
          spec().toUri().replaceAll('vhttp=h3', 'vhttp=h9'))!;
      expect(parsed.vhttp, 'h3', reason: 'форсится дефолт, а не едет как есть');
      final w = parsed.warnings
          .whereType<RegistryWarning>()
          .firstWhere((w) => w.code == 'masque_vhttp_invalid',
              orElse: () => fail('нет кода: ${parsed.warnings}'));
      expect(w.path, 'vhttp');
      expect(w.value, 'h9',
          reason: 'форс обязан быть виден пользователю, а не только в логе');
    });

    test('h2 остаётся валидным (тройка контракта целиком)', () {
      expect(
          parseLinkAs<MasqueSpec>(spec().toUri().replaceAll('vhttp=h3', 'vhttp=h2'))!
              .vhttp,
          'h2');
    });
  });
}
