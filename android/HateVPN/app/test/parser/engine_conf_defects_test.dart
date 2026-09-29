import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/node_warning.dart';
import 'package:lxbox/services/parser/drop_verdict.dart';
import 'package:lxbox/services/parser/engine/interpreter.dart';
import 'package:lxbox/services/parser/engine/section_loader.dart';

import 'engine_test_setup.dart';









const _priv = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=';
const _pub = 'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=';



const _privPlus = '0GCSi+xv9uacc7rK5S8Wmw0GCSixv9uacc7rK5S8W=';

void main() {
  setUpAll(loadEngineSections);

  ({String label, Map<String, dynamic> body, List<NodeWarning> warnings})? run(
    String text, {
    String? nameHint,
    XrayDropVerdict? dropped,
  }) {
    final section = MapperSections.I.sectionFor('conf', 'wireguard');
    expect(section, isNotNull, reason: 'секция conf/wireguard не загрузилась');
    final res =
        runSectionOnIni(section!, text, nameHint: nameHint, dropped: dropped);
    if (res == null) return null;
    return (label: res.label, body: res.body, warnings: res.warnings);
  }

  List<String> codes(List<NodeWarning> ws) => [
        for (final w in ws)
          if (w is RegistryWarning) w.code else w.runtimeType.toString(),
      ];

  group('§29 дефект 1 — `required` у записи с `extract` (Q133-64)', () {



    test('[Peer] без Endpoint — не узел, а не «узел с пиром без адреса»', () {
      const text = '[Interface]\n'
          'PrivateKey = $_priv\n'
          'Address = 10.0.0.2/32\n'
          '\n'
          '[Peer]\n'
          'PublicKey = $_pub\n'
          'AllowedIPs = 0.0.0.0/0\n';
      expect(
        run(text),
        isNull,
        reason: 'узел без адреса и порта пира не соединится никуда',
      );
    });

    test('Endpoint на месте — узел собирается как прежде', () {
      const text = '[Interface]\n'
          'PrivateKey = $_priv\n'
          'Address = 10.0.0.2/32\n'
          '\n'
          '[Peer]\n'
          'PublicKey = $_pub\n'
          'Endpoint = example.com:51820\n';
      final r = run(text);
      expect(r, isNotNull);
      final peer = (r!.body['peers'] as List).first as Map;
      expect(peer['address'], 'example.com');
      expect(peer['port'], 51820);
    });

    test('голый IPv6 — ветка take_all тоже засчитывается заполненной', () {


      const text = '[Interface]\n'
          'PrivateKey = $_priv\n'
          'Address = 10.0.0.2/32\n'
          '\n'
          '[Peer]\n'
          'PublicKey = $_pub\n'
          'Endpoint = 2001:db8::1:51820\n';
      final r = run(text);
      expect(r, isNotNull);
      final peer = (r!.body['peers'] as List).first as Map;
      expect(peer['address'], '2001:db8::1:51820');
    });
  });

  group('§29 дефект 2 — «+» в ini-документе литерален (Q133-62)', () {



    test('ключ с «+» доезжает до тела посимвольно', () {
      const text = '[Interface]\n'
          'PrivateKey = $_privPlus\n'
          'Address = 10.0.0.2/32\n'
          '\n'
          '[Peer]\n'
          'PublicKey = $_pub\n'
          'Endpoint = example.com:51820\n';
      final r = run(text);
      expect(r, isNotNull);
      expect(r!.body['private_key'], _privPlus);
      expect(r.body['private_key'], contains('+'));
      expect(r.body['private_key'], isNot(contains(' ')));
    });

    test('«+» в ЗНАЧЕНИИ незнакомого ключа тоже не трогается', () {


      const text = '[Interface]\n'
          'PrivateKey = $_priv\n'
          'Address = 10.0.0.2/32\n'
          'Id = a+b.example.com\n'
          '\n'
          '[Peer]\n'
          'PublicKey = $_pub\n'
          'Endpoint = example.com:51820\n';
      final r = run(text);
      expect(r, isNotNull);
      expect(r!.body['id'], 'a+b.example.com');
    });
  });

  group('§29 дефект 3 — `hint` в цепочке метки исполняется (Q133-63)', () {



    const text = '[Interface]\n'
        'PrivateKey = $_priv\n'
        'Address = 10.0.0.2/32\n'
        '\n'
        '[Peer]\n'
        'PublicKey = $_pub\n'
        'Endpoint = 203.0.113.7:51820\n';

    test('без комментария имя даёт `hint`, а не хост', () {
      expect(run(text, nameHint: 'AWG Node')?.label, 'AWG Node');
    });

    test('комментарий секции сильнее `hint` — звено первое', () {
      const withComment = '[Interface]\n'
          'PrivateKey = $_priv\n'
          'Address = 10.0.0.2/32\n'
          '\n'
          '[Peer]\n'
          '# US-FREE#137\n'
          'PublicKey = $_pub\n'
          'Endpoint = 203.0.113.7:51820\n';
      expect(run(withComment, nameHint: 'AWG Node')?.label, 'US-FREE#137');
    });

    test('без `hint` и комментария метку даёт фолбэк секции', () {
      expect(run(text)?.label, 'WireGuard');
    });
  });

  group('1.1.30 — вторая [Peer] отброшена С КОДОМ', () {



    const text = '[Interface]\n'
        'PrivateKey = $_priv\n'
        'Address = 10.0.0.2/32\n'
        '\n'
        '[Peer]\n'
        'PublicKey = $_pub\n'
        'Endpoint = first.example.com:51820\n'
        '\n'
        '[Peer]\n'
        'PublicKey = AwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwM=\n'
        'Endpoint = second.example.com:51821\n';

    test('узлом становится первая, вторая не сливается с ней', () {
      final r = run(text);
      expect(r, isNotNull);
      final peers = r!.body['peers'] as List;
      expect(peers, hasLength(1));
      expect((peers.first as Map)['address'], 'first.example.com');
      expect((peers.first as Map)['port'], 51820);
    });

    test('отброс не молчит', () {
      expect(codes(run(text)!.warnings), contains('wgconf_extra_peer_dropped'));
    });

    test('одна [Peer] кода не даёт', () {
      const single = '[Interface]\n'
          'PrivateKey = $_priv\n'
          'Address = 10.0.0.2/32\n'
          '\n'
          '[Peer]\n'
          'PublicKey = $_pub\n'
          'Endpoint = first.example.com:51820\n';
      expect(
        codes(run(single)!.warnings),
        isNot(contains('wgconf_extra_peer_dropped')),
      );
    });
  });

  group('1.1.32 — незнакомый ключ `.conf` перестал теряться молча', () {



    const base = '[Interface]\n'
        'PrivateKey = $_priv\n'
        'Address = 10.0.0.2/32\n';
    const peer = '\n[Peer]\n'
        'PublicKey = $_pub\n'
        'Endpoint = example.com:51820\n';

    test('BogusKey назван кодом, и путь несёт секцию', () {
      final r = run('${base}BogusKey = whatever\n$peer');
      expect(r, isNotNull);
      final w = r!.warnings.whereType<RegistryWarning>().where(
            (w) => w.code == 'wgconf_param_unknown',
          );
      expect(w, hasLength(1));
      expect(w.first.path, 'interface.boguskey');
    });

    test('не-узловые ключи wg-quick молчат — конфиг исправен', () {



      final r = run(
        '${base}Table = off\n'
        'PostUp = iptables -A FORWARD -i %i -j ACCEPT\n'
        'PreDown = true\n'
        'SaveConfig = true\n'
        'FwMark = 0x1\n'
        'PrivateKeyFile = /etc/wg/key\n'
        '$peer',
      );
      expect(r, isNotNull);
      expect(codes(r!.warnings), isEmpty);
    });

    test('объявленность считается по ИСТОЧНИКУ, а не по имени записи', () {



      final r = run(
        base,

      );
      expect(r, isNull, reason: 'без [Peer] узла нет вовсе');

      final full = run(
        '$base\n[Peer]\n'
        'PublicKey = $_pub\n'
        'PersistentKeepalive = 25\n'
        'Endpoint = example.com:51820\n',
      );
      expect(full, isNotNull);
      expect(codes(full!.warnings), isEmpty);
      expect(
        (full.body['peers'] as List).first,
        containsPair('persistent_keepalive_interval', 25),
      );
    });

    test('секция в имени значима — MTU у [Peer] не объявлен', () {


      final r = run(
        '$base\n[Peer]\n'
        'PublicKey = $_pub\n'
        'MTU = 1280\n'
        'Endpoint = example.com:51820\n',
      );
      expect(r, isNotNull);
      final w = r!.warnings.whereType<RegistryWarning>().where(
            (w) => w.code == 'wgconf_param_unknown',
          );
      expect(w, hasLength(1));
      expect(w.first.path, 'peer.mtu');
    });

    test('комментарий секции — источник метки, а не незнакомый ключ', () {
      final r = run('$base\n[Peer]\n'
          '# CH-FREE#11\n'
          'PublicKey = $_pub\n'
          'Endpoint = example.com:51820\n');
      expect(r, isNotNull);
      expect(r!.label, 'CH-FREE#11');
      expect(codes(r.warnings), isEmpty);
    });
  });
}
