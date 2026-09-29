import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../contract_paths.dart';
import 'package:lxbox/models/node_spec.dart';
import 'package:lxbox/models/node_warning.dart';
import 'package:lxbox/models/template_vars.dart';
import 'package:lxbox/models/transport_spec.dart';
import 'package:lxbox/services/parser/engine/section_loader.dart';
import 'package:lxbox/services/parser/mappers/draft_sections.dart';
import 'package:lxbox/services/parser/uri_parsers.dart';

























const Map<String, String> _knownGaps = {




  'sni_heuristic_falls_back_to_server@trojan':
      'не реализовано в LxBox ни на одном входе trojan; включение меняет тела '
          'и identity — отдельное решение (спека 472, шаг 2)',
  'sni_heuristic_falls_back_to_server@vless':
      'не реализовано в LxBox ни на одном входе vless; включение меняет тела '
          'и identity — отдельное решение (спека 472, шаг 3)',
  'sni_heuristic_falls_back_to_server@vmess':
      'не реализовано в LxBox ни на одном входе vmess; включение меняет тела '
          'и identity — отдельное решение (спека 472, шаг 4)',





  'sni_heuristic_falls_back_to_server@tuic':
      'реализован только откат пустого sni на адрес сервера; проверки '
          'написания нет — включение меняет тела и identity (спека 472, шаг 5)',
















  'sni_heuristic_falls_back_to_server@masque':
      'у masque пустой sni означает дефолт ПРОФИЛЯ ядра, а не отсутствие '
          'имени: откат на адрес сервера дал бы SNI = IP и сломал бы узлы '
          'WARP; не реализовано ни на одном входе masque (спека 472, шаг 7)',
};


const Map<String, String> _covered = {
  'security_none_no_tls': 'security=none — блока tls нет вовсе',
  'utls_xray_hello_names': 'fp в написании uTLS → имя семейства',
  'alpn_comma_list': 'alpn одной строкой → список тела',
  'ech_param_dropped_with_code': 'ech= не переносится, узел получает код',
  'ws_early_data_path_suffix': '?ed=N хвостом пути → два поля тела',
  'transport_name_dialect': 'headerType=http поверх tcp → транспорт http',

  'plaintext_port_no_tls': 'vless без security на открытом порту — блока нет',
  'pbk_makes_reality_block': 'pbk= создаёт блок REALITY, годность судит реестр',
  'fp_empty_defaults_to_random': 'vless без fp= → random',
  'vision_udp443_is_a_compound_name':
      'flow=xtls-rprx-vision-udp443 → vision + packet_encoding=xudp',
  'packet_encoding_none_means_absent': 'packetEncoding=none — ключа нет вовсе',

  'legacy_cleartext_fallback':
      'не-JSON payload читается как method:uuid@host:port',

  'sni_heuristic_falls_back_to_server@hysteria2':
      'sni без точки/двоеточия и 🔒 уступают адресу сервера',
  'mport_range_spec': 'mport=1000-2000,3000 → server_ports [low:high]',
  'heartbeat_bare_number': 'heartbeat=10 → "10s"',

  'sni_heuristic_falls_back_to_server@anytls':
      'anytls: sni без точки/двоеточия и 🔒 уступают адресу сервера',



  'tls_block_kept_minimal': 'naive: в блоке TLS только enabled + server_name',
  'broken_header_pair_skipped':
      'naive: битая пара extra-headers пропускается, остальные живут',




  'security_none_no_tls@http':
      'http: security=none гасит TLS даже на https-схеме',
  'utls_xray_hello_names@http': 'http: fp в написании uTLS → имя семейства',



  'vhttp_empty_defaults_to_h3': 'masque: без vhttp= → явный h3, а не auto ядра',
  'singbox_flat_fields_stripped':
      'masque: плоские network/sni/skip_cert_verify не переносятся',


  'bare_ip_gets_prefix':
      'wireguard: bare IP в address/allowed_ips получает /32 или /128',


  'socks_scheme_is_version': 'socks: схема ссылки → version тела',
};


List<String> _mapperRuleIds(String scheme) {
  final dir = Directory('$kRegistryRoot/registry');
  final files = <File>[
    ...dir.listSync().whereType<File>(),
    ...Directory('$kRegistryRoot/registry/protocols')
        .listSync()
        .whereType<File>(),
  ];
  final out = <String>[];
  for (final f in files) {
    if (!f.path.endsWith('.json')) continue;
    final Object? raw;
    try {
      raw = jsonDecode(f.readAsStringSync());
    } catch (_) {
      continue;
    }
    if (raw is! Map) continue;
    final mapper = raw['mapper'];
    if (mapper is! List) continue;
    for (final rule in mapper) {
      if (rule is! Map) continue;
      final applies = rule['applies_to'];
      if (applies is! List || !applies.contains(scheme)) continue;
      final id = rule['id'];
      if (id is String) out.add(id);
    }
  }
  return out..sort();
}



List<String> _codes(NodeSpec n) =>
    [for (final w in n.warnings.whereType<RegistryWarning>()) w.code];




const _kLegacySchemes = <String>{
  'trojan', 'vless', 'vmess', 'ss', 'hysteria2', 'hy2', 'tuic', 'anytls',
  'naive+https', 'naive+quic', 'proxy-http', 'proxy-https', 'proxy+http',
  'proxy+https', 'socks', 'socks5', 'socks4', 'socks4a', 'ssh', 'masque',
  'wireguard', 'wg', 'awg',
};

void main() {

  setUpAll(() async {
    await loadTestRegistry();
    await MapperSections.I
        .loadDrafts(dir: 'assets/contract_draft', files: kDraftFiles);
  });

  group('§472 — секция mapper реестра покрыта для переехавших схем', () {
    test('у каждой переехавшей схемы каждое mapper-правило названо', () {
      for (final scheme in _kLegacySchemes) {
        for (final id in _mapperRuleIds(scheme)) {


          final qualified = '$id@$scheme';
          final known = _covered.containsKey(qualified) ||
              _knownGaps.containsKey(qualified) ||
              _covered.containsKey(id) ||
              _knownGaps.containsKey(id);
          expect(
            known,
            isTrue,
            reason: 'схема $scheme переехала на конвейер, а mapper-правило '
                '`$id` из реестра не покрыто тестом и не названо в '
                '_knownGaps. Либо реализуйте его в mappers/, либо запишите '
                'расхождение с причиной.',
          );
        }
      }
    });

    test('у каждого известного расхождения есть причина', () {
      for (final e in _knownGaps.entries) {
        expect(e.value.trim(), isNotEmpty,
            reason: 'расхождение ${e.key} без причины');
      }
    });
  });

  group('§472 — правила mapper на живых ссылках (trojan)', () {
    test('security=none — блока tls нет вовсе', () {

      final spec = parseUri('trojan://p@h.example:8080?security=none#n')!;
      expect(spec.emit(TemplateVars.empty).map.containsKey('tls'), isFalse);
    });

    test('fp в написании uTLS → имя семейства', () {
      final spec = parseUri(
          'trojan://p@h.example:443?security=tls&fp=hellofirefox_auto#n')!;
      final tls = spec.emit(TemplateVars.empty).map['tls'] as Map;
      expect((tls['utls'] as Map)['fingerprint'], 'firefox');

      expect(
        spec.warnings.whereType<RegistryWarning>().map((w) => w.code),
        isNot(contains('utls_fp_unknown')),
      );
    });

    test('alpn одной строкой → список тела', () {
      final spec = parseUri(
          'trojan://p@h.example:443?security=tls&alpn=h2,http/1.1#n')!;
      final tls = spec.emit(TemplateVars.empty).map['tls'] as Map;
      expect(tls['alpn'], ['h2', 'http/1.1']);
    });

    test('ech= не переносится, узел получает код', () {
      final spec = parseUri(
          'trojan://p@h.example:443?security=tls&ech=ip.gs+1.1.1.1#n')!;
      final tls = spec.emit(TemplateVars.empty).map['tls'] as Map;
      expect(tls.containsKey('ech'), isFalse);
      expect(_codes(spec), contains('ech_ignored'));
    });

    test('?ed=N хвостом пути → два поля тела', () {
      final spec = parseUri('trojan://p@h.example:443?security=tls&type=ws'
          '&path=%2Fx%3Fed%3D2560#n')!;
      final tr = spec.emit(TemplateVars.empty).map['transport'] as Map;
      expect(tr['path'], '/x');
      expect(tr['max_early_data'], 2560);
      expect(tr['early_data_header_name'], 'Sec-WebSocket-Protocol');

      expect(spec.toUri(), isNot(contains('eh=')));
      expect(
        ((spec as TrojanSpec).transport as WsTransport).earlyDataHeaderImplicit,
        isTrue,
      );
    });

    test('headerType=http поверх tcp → УЗЕЛ ОТБРАКОВАН', () {








      final dropped = XrayDropVerdict();
      final spec = parseUri(
        'trojan://p@h.example:443?security=tls&type=tcp'
        '&headerType=http&path=%2Fc&host=cdn.example#n',
        dropped: dropped,
      );
      expect(spec, isNull);
      expect(dropped.reason?.code, 'transport_header_unsupported');
    });

    test('headerType=none поверх tcp — камуфляжа нет, узел цел', () {


      final spec = parseUri('trojan://p@h.example:443?security=tls&type=tcp'
          '&headerType=none#n')!;
      expect(spec.emit(TemplateVars.empty).map['transport'], isNull);
    });
  });

  group('§472 — правила mapper на живых ссылках (vless)', () {
    test('vless без security на открытом порту — блока нет', () {

      final plain = parseUri('vless://u@h.example:8080#n')!;
      expect(plain.emit(TemplateVars.empty).map.containsKey('tls'), isFalse);
      final tls = parseUri('vless://u@h.example:8443#n')!;
      expect(tls.emit(TemplateVars.empty).map.containsKey('tls'), isTrue);
    });

    test('pbk= создаёт блок REALITY, годность судит реестр', () {
      const pbk = 'AwoRGB8mLTQ7QklQV15lbHN6gYiPlp2kq7K5wMfO1dw';

      final ok = parseUri('vless://u@h.example:443?security=tls&pbk=$pbk#n')!;
      final tls = ok.emit(TemplateVars.empty).map['tls'] as Map;
      expect((tls['reality'] as Map)['public_key'], pbk);


      final junk =
          parseUri('vless://u@h.example:443?security=reality&pbk=enabled#n')!;
      final junkTls = junk.emit(TemplateVars.empty).map['tls'] as Map;
      expect(junkTls.containsKey('reality'), isFalse);
      expect(
        junk.warnings.whereType<RegistryWarning>().map((w) => w.code),
        contains('reality_pbk_invalid'),
      );
    });

    test('vless без fp= → random', () {


      final spec = parseUri('vless://u@h.example:443?security=tls#n')!;
      final tls = spec.emit(TemplateVars.empty).map['tls'] as Map;
      expect((tls['utls'] as Map)['fingerprint'], 'random');

      final tr = parseUri('trojan://p@h.example:443?security=tls#n')!;
      expect((tr.emit(TemplateVars.empty).map['tls'] as Map).containsKey('utls'),
          isFalse);
    });

    test('flow=xtls-rprx-vision-udp443 → vision + packet_encoding=xudp', () {
      final spec =
          parseUri('vless://u@h.example:443?security=tls&sni=x.com'
              '&flow=xtls-rprx-vision-udp443#n')!;
      final body = spec.emit(TemplateVars.empty).map;
      expect(body['flow'], 'xtls-rprx-vision');
      expect(body['packet_encoding'], 'xudp');

      expect(body['server_port'], 443);
    });

    test('packetEncoding=none — ключа нет вовсе', () {



      final spec = parseUri('vless://u@h.example:443?security=tls&sni=x.com'
          '&packetEncoding=none#n')!;
      expect(spec.emit(TemplateVars.empty).map.containsKey('packet_encoding'),
          isFalse);
      expect(
        spec.warnings.whereType<RegistryWarning>().map((w) => w.code),
        isNot(contains('packet_encoding_unknown')),
      );
    });
  });

  group('§472 — правила mapper на живых ссылках (hysteria2)', () {
    test('sni без точки/двоеточия и 🔒 уступают адресу сервера', () {


      for (final bad in ['localhost', '🔒']) {
        final spec = parseUri(
            'hysteria2://p@h.example:443?sni=${Uri.encodeComponent(bad)}#n')!;
        expect((spec.emit(TemplateVars.empty).map['tls'] as Map)['server_name'],
            'h.example',
            reason: 'sni=$bad');
      }
      final ok = parseUri('hysteria2://p@h.example:443?sni=a.b#n')!;
      expect((ok.emit(TemplateVars.empty).map['tls'] as Map)['server_name'],
          'a.b');
    });

    test('mport=1000-2000,3000 → server_ports [low:high]', () {


      final spec =
          parseUri('hysteria2://p@h.example:443?mport=1000-2000,3000#n')!;
      expect(spec.emit(TemplateVars.empty).map['server_ports'],
          ['1000:2000', '3000:3000']);


      final auth = parseUri('hysteria2://p@h.example:20000-30000/#n')!;
      expect(auth.emit(TemplateVars.empty).map['server_ports'],
          ['20000:30000']);
      expect(auth.emit(TemplateVars.empty).map['server_port'], 20000);
    });

    test('fp в написании uTLS → имя семейства (и снимается как QUIC-блок)', () {



      final spec = parseUri(
          'hysteria2://p@h.example:443?sni=x.com&fp=hellofirefox_auto#n')!;
      final w = spec.warnings
          .whereType<RegistryWarning>()
          .firstWhere((w) => w.code == 'tls_not_applicable_quic');
      expect(w.value, 'map[enabled:true fingerprint:firefox]');
    });

    test('alpn одной строкой → список тела', () {
      final spec =
          parseUri('hysteria2://p@h.example:443?sni=x.com&alpn=h3,h3-29#n')!;
      final tls = spec.emit(TemplateVars.empty).map['tls'] as Map;
      expect(tls['alpn'], ['h3', 'h3-29']);
    });
  });

  group('§472 — правила mapper на живых ссылках (tuic)', () {
    const uuid = '11111111-1111-1111-1111-111111111111';

    test('heartbeat=10 → "10s"', () {


      final spec = parseUri('tuic://$uuid:p@h.example:443?heartbeat=10#n')!;
      expect(spec.emit(TemplateVars.empty).map['heartbeat'], '10s');

      final explicit =
          parseUri('tuic://$uuid:p@h.example:443?heartbeat=30s#n')!;
      expect(explicit.emit(TemplateVars.empty).map['heartbeat'], '30s');
    });

    test('пустой sni уступает адресу сервера', () {
      final spec = parseUri('tuic://$uuid:p@h.example:443?alpn=h3#n')!;
      expect((spec.emit(TemplateVars.empty).map['tls'] as Map)['server_name'],
          'h.example');
    });

    test('alpn одной строкой → список тела', () {
      final spec =
          parseUri('tuic://$uuid:p@h.example:443?alpn=h3,h3-29#n')!;
      expect((spec.emit(TemplateVars.empty).map['tls'] as Map)['alpn'],
          ['h3', 'h3-29']);
    });
  });

  group('§472 — правила mapper на живых ссылках (anytls)', () {
    test('anytls: sni без точки/двоеточия и 🔒 уступают адресу сервера', () {


      for (final bad in ['localhost', '🔒']) {
        final spec = parseUri(
            'anytls://pw@h.example:443?sni=${Uri.encodeComponent(bad)}#n')!;
        expect((spec.emit(TemplateVars.empty).map['tls'] as Map)['server_name'],
            'h.example',
            reason: 'sni=$bad');
      }
    });

    test('anytls: pbk= создаёт блок REALITY, годность судит реестр', () {
      const pbk = 'AwoRGB8mLTQ7QklQV15lbHN6gYiPlp2kq7K5wMfO1dw';
      final ok = parseUri('anytls://pw@h.example:443?pbk=$pbk&sid=abcd#n')!;
      final tls = ok.emit(TemplateVars.empty).map['tls'] as Map;
      expect((tls['reality'] as Map)['public_key'], pbk);
    });

    test('anytls: без fp= → random, fp в написании uTLS → семейство', () {

      final bare = parseUri('anytls://pw@h.example:443?sni=a.b#n')!;
      expect(
          ((bare.emit(TemplateVars.empty).map['tls'] as Map)['utls']
              as Map)['fingerprint'],
          'random');
      final alias =
          parseUri('anytls://pw@h.example:443?sni=a.b&fp=hellofirefox_auto#n')!;
      expect(
          ((alias.emit(TemplateVars.empty).map['tls'] as Map)['utls']
              as Map)['fingerprint'],
          'firefox');
    });

    test('anytls: alpn одной строкой → список, ech= не переносится', () {

      final spec = parseUri('anytls://pw@h.example:443?sni=a.b'
          '&alpn=h2,http/1.1&ech=ip.gs+1.1.1.1#n')!;
      final tls = spec.emit(TemplateVars.empty).map['tls'] as Map;
      expect(tls['alpn'], ['h2', 'http/1.1']);
      expect(tls.containsKey('ech'), isFalse);
      expect(_codes(spec), contains('ech_ignored'));
    });
  });

  group('§475 — правила mapper на живых ссылках (socks)', () {
    test('socks: схема ссылки → version тела', () {


      for (final (uri, want) in const [
        ('socks://h.example:1080#n', '5'),
        ('socks5://h.example:1080#n', '5'),
        ('socks4://h.example:1080#n', '4'),
        ('socks4a://h.example:1080#n', '4a'),
      ]) {
        final spec = parseUri(uri)!;
        expect(spec.emit(TemplateVars.empty).map['version'], want,
            reason: uri);
      }
    });

    test('socks: та же таблица работает обратно — узел эмитит свою схему', () {


      for (final uri in const [
        'socks4://user@h.example:1080#n',
        'socks4a://h.example:1080#n',
        'socks5://user:pass@h.example:1080#n',
      ]) {
        final spec = parseUri(uri)!;
        final again = parseUri(spec.toUri())!;
        expect(again.emit(TemplateVars.empty).map['version'],
            spec.emit(TemplateVars.empty).map['version'],
            reason: uri);
        expect(spec.toUri(), startsWith(uri.split('://').first),
            reason: '$uri: схема ссылки обязана называть версию узла');
      }
    });

    test('socks4: пароль из ссылки переносится КАК ЕСТЬ', () {


      final spec = parseUri('socks4://user:pass@h.example:1080#n')!;
      final body = spec.emit(TemplateVars.empty).map;
      expect(body['version'], '4');
      expect(body['username'], 'user');
      expect(body['password'], 'pass');
    });
  });

  group('§472 — правила mapper на живых ссылках (naive)', () {
    test('naive: в блоке TLS только enabled + server_name', () {



      final spec = parseUri('naive+https://u:p@h.example:443#n')!;
      expect(spec.emit(TemplateVars.empty).map['tls'],
          {'enabled': true, 'server_name': 'h.example'});
    });

    test('naive: битая пара extra-headers пропускается, остальные живут', () {


      final spec = parseUri('naive+https://u:p@h.example'
          '?extra-headers=X%20User%3Abad%0D%0AX-Good%3Aok#n')!;
      expect(spec.emit(TemplateVars.empty).map['extra_headers'],
          {'X-Good': 'ok'});
    });
  });

  group('§472 — правила mapper на живых ссылках (http)', () {
    test('http: security=none гасит TLS даже на https-схеме', () {
      final off = parseUri('proxy-https://u@h.example:443?security=none#n')!;
      expect(off.emit(TemplateVars.empty).map.containsKey('tls'), isFalse);

      final on = parseUri('proxy-https://u@h.example:443#n')!;
      expect((on.emit(TemplateVars.empty).map['tls'] as Map)['enabled'],
          isTrue);
    });

    test('http: fp в написании uTLS → имя семейства', () {
      final spec = parseUri(
          'proxy-https://u@h.example:443?sni=a.b&fp=hellofirefox_auto#n')!;
      final tls = spec.emit(TemplateVars.empty).map['tls'] as Map;
      expect((tls['utls'] as Map)['fingerprint'], 'firefox');

      expect(
        spec.warnings.whereType<RegistryWarning>().map((w) => w.code),
        isNot(contains('utls_fp_unknown')),
      );
    });
  });

  group('§472 — правила mapper на живых ссылках (masque)', () {

    const bare = 'masque://PRIVDER%3D%3D@192.0.2.44:443'
        '?publickey=PUBDER%3D%3D&address=172.16.0.2%2F32#n';

    test('masque: без vhttp= → явный h3, а не auto ядра', () {




      final spec = parseUri(bare)!;
      expect(spec.emit(TemplateVars.empty).map['vhttp'], 'h3');


      final auto = parseUri(bare.replaceAll('#n', '&vhttp=auto#n'))!;
      expect(auto.emit(TemplateVars.empty).map['vhttp'], 'auto');
      expect(auto.warnings, isEmpty);
    });

    test('masque: плоские network/sni/skip_cert_verify не переносятся', () {



      final spec = parseUri(bare.replaceAll(
          '#n', '&network=h2&server_name=legacy.example&skip_cert_verify=1#n'))!;
      final body = spec.emit(TemplateVars.empty).map;
      expect(body['vhttp'], 'h3', reason: 'legacy network= не влияет ни на что');
      expect(body.containsKey('network'), isFalse);
      expect(body.containsKey('sni'), isFalse);
      expect(body.containsKey('skip_cert_verify'), isFalse);
      expect(body.containsKey('tls'), isFalse,
          reason: 'legacy server_name= не создаёт блок tls');
    });

    test('masque: address списком → пара ip/ipv6, bare IP получает префикс', () {
      final spec = parseUri(bare.replaceAll(
          'address=172.16.0.2%2F32', 'address=172.16.0.2%2C2001%3Adb8%3A%3A2'))!;
      final body = spec.emit(TemplateVars.empty).map;
      expect(body['ip'], '172.16.0.2/32');
      expect(body['ipv6'], '2001:db8::2/128');
    });

    test('masque: sni и disable_sni уезжают во вложенный tls{}', () {
      final spec = parseUri(
          bare.replaceAll('#n', '&sni=a.example&disable_sni=1#n'))!;
      expect(spec.emit(TemplateVars.empty).map['tls'],
          {'server_name': 'a.example', 'disable_sni': true});
    });
  });

  group('§472 — правила mapper на живых ссылках (wireguard)', () {
    const priv = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaA=';
    const pub = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbA=';

    test('wireguard: bare IP в address/allowed_ips получает /32 или /128', () {


      final spec = parseUri('wireguard://$priv@h.example:51820'
          '?publickey=$pub&address=10.0.0.2,fd00::2'
          '&allowedips=192.168.1.1,2001:db8::1#n')!;
      final body = spec.emit(TemplateVars.empty).map;
      expect(body['address'], ['10.0.0.2/32', 'fd00::2/128']);
      expect((body['peers'] as List).first['allowed_ips'],
          ['192.168.1.1/32', '2001:db8::1/128']);

      final kept = parseUri('wireguard://$priv@h.example:51820'
          '?publickey=$pub&address=10.0.0.0/8#n')!;
      expect(kept.emit(TemplateVars.empty).map['address'], ['10.0.0.0/8']);
    });
  });

  group('§472 — правила mapper на живых ссылках (vmess)', () {

    String jsonLink(Map<String, dynamic> cfg) =>
        'vmess://${base64.encode(utf8.encode(jsonEncode(cfg)))}';

    const base = <String, dynamic>{
      'v': '2',
      'ps': 'n',
      'add': 'h.example',
      'port': '443',
      'id': '11111111-1111-1111-1111-111111111111',
    };

    test('не-JSON payload читается как method:uuid@host:port', () {


      final spec = parseUri('vmess://${base64.encode(utf8.encode(
        'aes-128-gcm:11111111-1111-1111-1111-111111111111@203.0.113.7:8443'
        '?type=ws&path=%2Fws&tls=1',
      ))}#Legacy');
      expect(spec, isNotNull);
      final body = spec!.emit(TemplateVars.empty).map;
      expect(body['security'], 'aes-128-gcm');
      expect(body['server_port'], 8443);
      expect((body['transport'] as Map)['type'], 'ws');
      expect((body['tls'] as Map)['enabled'], isTrue);

      expect(spec.label, 'Legacy');
    });

    test('JSON-форма фрагмент ссылки не читает', () {


      final spec = parseUri('${jsonLink({...base, 'ps': 'изPS'})}#изФрагмента');
      expect(spec!.label, 'изPS');
    });

    test('net=h2 включает TLS и даёт транспорт http', () {


      final spec = parseUri(jsonLink({...base, 'net': 'h2'}))!;
      final body = spec.emit(TemplateVars.empty).map;
      expect((body['transport'] as Map)['type'], 'http');
      expect((body['tls'] as Map)['enabled'], isTrue);

      expect((body['transport'] as Map)['host'], ['h.example']);
    });

    test('без tls=tls блока TLS нет вовсе', () {


      final spec = parseUri(jsonLink({...base, 'net': 'tcp'}))!;
      expect(spec.emit(TemplateVars.empty).map.containsKey('tls'), isFalse);
    });

    test('SNI контейнера: sni → host → сервер', () {


      final byHost = parseUri(jsonLink(
          {...base, 'net': 'tcp', 'tls': 'tls', 'host': 'cdn.example'}))!;
      expect((byHost.emit(TemplateVars.empty).map['tls'] as Map)['server_name'],
          'cdn.example');

      final bySni = parseUri(jsonLink({
        ...base,
        'net': 'tcp',
        'tls': 'tls',
        'host': 'cdn.example',
        'sni': 'sni.example',
      }))!;
      expect((bySni.emit(TemplateVars.empty).map['tls'] as Map)['server_name'],
          'sni.example');

      final byServer =
          parseUri(jsonLink({...base, 'net': 'tcp', 'tls': 'tls'}))!;
      expect(
          (byServer.emit(TemplateVars.empty).map['tls'] as Map)['server_name'],
          'h.example');
    });

    test('fp в написании uTLS → имя семейства, alpn одной строкой → список',
        () {


      final spec = parseUri(jsonLink({
        ...base,
        'net': 'tcp',
        'tls': 'tls',
        'fp': 'hellofirefox_auto',
        'alpn': 'h2,http/1.1',
      }))!;
      final tls = spec.emit(TemplateVars.empty).map['tls'] as Map;
      expect((tls['utls'] as Map)['fingerprint'], 'firefox');
      expect(tls['alpn'], ['h2', 'http/1.1']);
    });

    test('?ed=N хвостом пути → два поля тела', () {

      final spec = parseUri(
          jsonLink({...base, 'net': 'ws', 'path': '/x?ed=2560'}))!;
      final tr = spec.emit(TemplateVars.empty).map['transport'] as Map;
      expect(tr['path'], '/x');
      expect(tr['max_early_data'], 2560);
      expect(tr['early_data_header_name'], 'Sec-WebSocket-Protocol');
    });

    test('ech= не переносится, узел получает код', () {
      final spec = parseUri(jsonLink({
        ...base,
        'net': 'tcp',
        'tls': 'tls',
        'ech': 'ip.gs+1.1.1.1',
      }))!;
      final tls = spec.emit(TemplateVars.empty).map['tls'] as Map;
      expect(tls.containsKey('ech'), isFalse);
      expect(_codes(spec), contains('ech_ignored'));
    });
  });
}
