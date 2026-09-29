import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

















void main() {
  Map<String, dynamic> load(String path) =>
      (jsonDecode(File(path).readAsStringSync()) as Map).cast<String, dynamic>();

  Map<String, dynamic> section(String path, String kind) {
    final mappers = (load(path)['mappers'] as Map).cast<String, dynamic>();
    return (mappers[kind] as Map).cast<String, dynamic>();
  }








  const uriSections = <String, String>{
    'hysteria2': 'assets/contract/registry/protocols/hysteria2.json',
    'tuic': 'assets/contract/registry/protocols/tuic.json',
    'masque': 'assets/contract/registry/protocols/masque.json',



    'wireguard': 'assets/contract/registry/protocols/wireguard.json',
  };

  group('§480 W4 — форма секций uri', () {
    test('файлы читаются и несут секцию mappers.uri', () {
      for (final e in uriSections.entries) {
        final mappers = (load(e.value)['mappers'] as Map).cast<String, dynamic>();


        expect(mappers.keys, contains('uri'), reason: e.key);
      }
    });

    test('обязательные атрибуты секции на месте', () {
      for (final e in uriSections.entries) {
        final s = section(e.value, 'uri');
        expect(s['body_source'], 'uri', reason: e.key);
        expect(s['detect'], isA<Map>(), reason: e.key);
        expect(s['forms'], isA<List>(), reason: e.key);
        expect(s['params'], isA<Map>(), reason: e.key);
        expect(s['unknown_key'], isA<Map>(), reason: e.key);
        expect(s['label'], isA<Map>(), reason: e.key);
      }
    });

    test('ровно одна форма по умолчанию на секцию', () {
      for (final e in uriSections.entries) {
        final forms = (section(e.value, 'uri')['forms'] as List).cast<Map>();
        final defaults = forms.where(
          (f) => ((f['detect'] as Map?)?['default'] as bool?) ?? false,
        );
        expect(defaults.length, 1, reason: e.key);
      }
    });

    test('у каждой записи таблицы есть source — единственный способ получить '
        'значение (PRIMITIVES §1.1)', () {
      for (final e in uriSections.entries) {
        final params = (section(e.value, 'uri')['params'] as Map).cast<String, dynamic>();
        for (final p in params.entries) {
          expect((p.value as Map)['source'], isNotNull,
              reason: '${e.key}.${p.key}');
        }
      }
    });

    test(r'служебная запись ($-префикс) не имеет maps_to (PRIMITIVES §0.7)',
        () {
      for (final e in uriSections.entries) {
        final params = (section(e.value, 'uri')['params'] as Map).cast<String, dynamic>();
        for (final p in params.entries) {
          if (!p.key.startsWith(r'$')) continue;
          expect((p.value as Map)['maps_to'], isNull, reason: '${e.key}.${p.key}');
        }
      }
    });

    test('фолбэк тега — по ТИПУ ТЕЛА (DELTAS D133-6), и это уже наше '
        'поведение: awg:// даёт wireguard-…', () {
      for (final e in uriSections.entries) {
        final fb = ((section(e.value, 'uri')['label'] as Map)['fallback'] as Map);
        expect(fb['scheme_source'], 'singbox_type', reason: e.key);
        expect(fb['template'], '{scheme}-{server}-{server_port}', reason: e.key);
      }
    });

    test('эмит: param_order — ПРАВИЛО (алфавит), а не перечень', () {
      for (final e in uriSections.entries) {


        final emit = section(e.value, 'uri')['emit'];
        if (emit == null) continue;
        expect((emit as Map)['param_order'], 'alphabetical', reason: e.key);
      }
    });

    test('эмит wireguard — param_order из реестра, form_from в оверлее', () {
      final emit = section(uriSections['wireguard']!, 'uri')['emit'] as Map;
      expect(emit['param_order'], 'alphabetical');
      final draftEmit =
          (section('assets/contract_draft/uri/wireguard.json', 'uri')['emit']
              as Map);


      expect(((draftEmit['form_from'] as Map)['any_set'] as Map)['*'],
          'wireguard');
    });

    test('общие блоки берутся у лаунчера через include, своих копий нет', () {




      for (final k in const ['hysteria2', 'tuic']) {
        final s = section(uriSections[k]!, 'uri');
        expect((s['include'] as List), contains('tls#uri'), reason: k);
      }
















      const allowed = {'hysteria2.security'};
      for (final e in uriSections.entries) {
        final params = (section(e.value, 'uri')['params'] as Map).cast<String, dynamic>();
        for (final dup in const ['security', 'alpn', 'pbk', 'sid']) {
          if (allowed.contains('${e.key}.$dup')) continue;
          expect(params.containsKey(dup), isFalse, reason: '${e.key}.$dup');
        }
      }
    });










    test('черновик при исполняемой секции реестра — только _overlay', () {
      final registry = Directory('assets/contract/registry/protocols');
      final executable = <String, Set<String>>{};
      for (final f in registry.listSync().whereType<File>()) {
        if (!f.path.endsWith('.json')) continue;
        final name = f.uri.pathSegments.last.replaceAll('.json', '');
        final mappers = (load(f.path)['mappers'] as Map?)?.cast<String, dynamic>();
        if (mappers == null) continue;
        executable[name] = mappers.keys.toSet();
      }

      for (final sub in const ['uri', 'xray', 'singbox', 'conf']) {
        final dir = Directory('assets/contract_draft/$sub');
        if (!dir.existsSync()) continue;
        for (final f in dir.listSync().whereType<File>()) {
          if (!f.path.endsWith('.json')) continue;
          final name = f.uri.pathSegments.last.replaceAll('.json', '');
          final file = load(f.path);
          final kinds = (file['mappers'] as Map?)?.keys.cast<String>() ?? const [];
          for (final kind in kinds) {
            if (!(executable[name]?.contains(kind) ?? false)) continue;
            expect(file['_overlay'], isTrue,
                reason: 'assets/contract_draft/$sub/$name.json: секция '
                    'mappers.$kind есть в реестре и исполняема, значит '
                    'черновик обязан быть оверлеем (_overlay: true) и нести '
                    'только отличия. Полную копию загрузчик игнорирует.');
          }
        }
      }
    });

    test('base64-поля читают «+» буквально (DELTAS D133-7)', () {
      const base64Fields = <String, List<String>>{
        'masque': ['private_key', 'publickey'],
        'wireguard': [
          'privatekey',
          'publickey',
          'presharedkey',
          'headerprotectionkey',
        ],
      };
      for (final e in base64Fields.entries) {
        final params = (section(uriSections[e.key]!, 'uri')['params'] as Map)
            .cast<String, dynamic>();
        for (final f in e.value) {
          final p = params[f] as Map;




          final de = (p['decode_extra'] as Map?)?['plus_literal'] == true;
          final byFormat = '${p['format']}'.startsWith('base64');
          expect(de || byFormat, isTrue,
              reason: '${e.key}.$f: ни decode_extra.plus_literal, ни '
                  'format base64*');
        }
      }
    });

    test('tuic disable_sni СНИМАЕТ tls.server_name (G2: null в sets)', () {
      final p = (section(uriSections['tuic']!, 'uri')['params'] as Map)
          .cast<String, dynamic>();
      final sets = ((p['disable_sni'] as Map)['sets'] as Map)['true'] as Map;
      expect(sets.containsKey('tls.server_name'), isTrue);
      expect(sets['tls.server_name'], isNull);
    });

    test('masque материализует дефолты profile/vhttp/mtu: default реестра в '
        'тело не едет (PARSING_PRINCIPLES §2.4), а identity живых узлов на них стоит', () {
      final p = (section(uriSections['masque']!, 'uri')['params'] as Map)
          .cast<String, dynamic>();
      for (final f in const ['profile', 'vhttp', 'mtu']) {
        expect((p[f] as Map)['materialize_default'], isTrue, reason: f);
      }
      expect(((p['vhttp'] as Map)['default_when'] as Map)['value'], 'h3');
      expect(((p['mtu'] as Map)['default_when'] as Map)['value'], 1280);
      expect(((p['profile'] as Map)['default_when'] as Map)['value'], 'cloudflare');
    });

    test('hysteria2: multi-port читается из сырого порта, а не из port', () {
      final p = (section(uriSections['hysteria2']!, 'uri')['params'] as Map)
          .cast<String, dynamic>();
      final mp = p[r'$multiport'] as Map;
      expect(mp['source'], 'port_raw');
      expect(mp['selector'], isTrue);

      expect((p['mport'] as Map)['merge'], 'append');
      expect((p['mport'] as Map)['normalize'], 'port_range_spec');
    });

    test('wireguard: mtu переносится как есть — потолок и дефолт AWG судит '
        'реестр (§473)', () {
      final mtu = ((section(uriSections['wireguard']!, 'uri')['params'] as Map)
          .cast<String, dynamic>()['mtu'] as Map);
      expect(mtu['default_when'], isNull);
      expect(mtu.containsKey('materialize_default'), isFalse);
    });
  });

  group('§480 W4 — форма секции conf (INI)', () {



    const path = 'assets/contract/registry/protocols/wireguard.json';

    test('секция объявляет источник тела wgconf и опознаётся по [Interface]', () {
      final s = section(path, 'conf');
      expect(s['body_source'], 'wgconf');
      expect(((s['detect'] as Map)['ini'] as Map)['sections'], ['Interface']);
      expect(s['emit'], isNull, reason: 'обратного хода у .conf нет');
    });

    test('все записи адресуют ini.<Section>.<Key> (одно пространство на '
        'awg://<base64 .conf> и на файл)', () {
      final params = (section(path, 'conf')['params'] as Map).cast<String, dynamic>();
      for (final p in params.entries) {
        final src = (p.value as Map)['source'];


        final all = src is List ? src : [src];
        for (final s in all) {
          expect(s, isA<String>(), reason: p.key);



          final str = s as String;
          expect(str.startsWith('ini.') || str.startsWith('context.'), isTrue,
              reason: p.key);
        }
      }
    });

    test('имя узла — из комментария под [Peer] (G7)', () {
      final label = section(path, 'conf')['label'] as Map;
      expect((label['source'] as List), contains(r'ini.$comment.Peer'));
    });

    test('Endpoint: голый IPv6 берётся адресом целиком, порт по умолчанию '
        '(§219 — отличить порт от адреса нечем)', () {
      final ep = ((section(path, 'conf')['params'] as Map)['endpoint'] as Map);
      final noMatch = ep['on_no_match'] as Map;
      expect(noMatch['action'], 'take_all');
      expect(noMatch['into'], 'peers[].address');
      expect((noMatch['defaults'] as Map)['peers[].port'], 51820);
    });

    test('читается только ПЕРВАЯ [Peer], и отброс повтора назван кодом', () {




      final dialect = section(path, 'conf')['ini_dialect'] as Map;
      final peer = (dialect['sections'] as Map)['Peer'] as Map;
      expect(peer['repeat'], 'first_only');
      expect((peer['on_extra'] as Map)['code'], 'wgconf_extra_peer_dropped');


      expect(dialect['key_case'], 'lower');
      expect(dialect['value_case'], 'preserve');
      expect(dialect['repeated_key'], 'last_wins');
      expect(dialect['inline_comments'], isFalse);
      expect(dialect['line_comment_prefixes'], ['#', ';']);
    });

    test('незнакомый ключ .conf назван кодом, не-узловые ключи молчат', () {


      final uk = section(path, 'conf')['unknown_key'] as Map;
      expect(uk['code'], 'wgconf_param_unknown');
      final ignore = (uk['ignore'] as List).cast<String>();



      expect(ignore, containsAll(['postup', 'table', 'saveconfig']));
    });






    test('Interface.DNS — лоссы by design, потеря названа кодом', () {
      final dns = ((section(path, 'conf')['params'] as Map)['dns'] as Map);
      expect(dns['maps_to'], isNull);
      final onPresent = dns['on_present'] as Map;
      expect(onPresent['code'], 'wgconf_dns_ignored');
    });

    test('delta480-4 — алиас preshared_key читается ССЫЛОЧНОЙ формой', () {




      final uriPsk = ((section(
          'assets/contract/registry/protocols/wireguard.json',
          'uri')['params'] as Map)['presharedkey'] as Map);
      final url = (uriPsk['source'] as Map)['url'];
      expect((url as List).map((e) => '$e'), contains('query.preshared_key'));

      final confPsk =
          ((section(path, 'conf')['params'] as Map)['presharedkey'] as Map);
      expect('${confPsk['source']}'.toLowerCase(), contains('presharedkey'));
    });
  });








  group('§480 W4 — вид xray у пары по версии', () {
    const h2Path = 'assets/contract/registry/protocols/hysteria2.json';
    const h1Path = 'assets/contract/registry/protocols/hysteria.json';

    test('обе секции исполняемы и читают вид xray', () {
      for (final p in [h2Path, h1Path]) {
        final s = section(p, 'xray');
        expect(s['body_source'], 'xray', reason: p);
        expect(s['detect'], isNotNull, reason: p);
        expect((s['params'] as Map), isNotEmpty, reason: p);
      }
    });

    test('detect у пары ВЗАИМОИСКЛЮЧАЮЩИЕ: версия 2 только у одной', () {





      final h2 = jsonEncode(section(h2Path, 'xray')['detect']);
      final h1 = jsonEncode(section(h1Path, 'xray')['detect']);
      expect(h2, contains('hysteria2'));
      expect(h1, isNot(contains('hysteria2')));
      expect(section(h1Path, 'xray')['detect'].toString(), contains('not'));
    });
  });
}
