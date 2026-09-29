import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';















void main() {
  Map<String, dynamic> template() => jsonDecode(
        File('assets/wizard_template.json').readAsStringSync(),
      ) as Map<String, dynamic>;


  Map<String, Map<String, dynamic>> baseServersByTag(Map<String, dynamic> tpl) {
    final out = <String, Map<String, dynamic>>{};
    for (final e in (tpl['dns_options'] as Map)['servers'] as List) {
      final s = (e as Map)['server'];
      if (s is Map && s['tag'] is String) {
        out[s['tag'] as String] = s.cast<String, dynamic>();
      }
    }
    return out;
  }









  Map<String, Map<String, dynamic>> allServersByTag(Map<String, dynamic> tpl) {
    final out = baseServersByTag(tpl);
    for (final r in (tpl['selectable_rules'] as List? ?? const [])) {
      for (final s in ((r as Map)['dns_servers'] as List? ?? const [])) {
        if (s is Map && s['tag'] is String) {
          out.putIfAbsent(s['tag'] as String, () => s.cast<String, dynamic>());
        }
      }
    }
    return out;
  }


  const encrypted = {'https', 'tls', 'quic', 'h3'};

  test('в группе fastest пресета dns_shield нет открытых udp-серверов', () {
    final tpl = template();
    final byTag = allServersByTag(tpl);
    final shield = baseServersByTag(tpl)['dns_shield'];
    expect(shield, isNotNull, reason: 'группа dns_shield исчезла из шаблона');
    expect(shield!['mode'], 'fastest',
        reason: 'тест написан под гонку fastest; смена режима — пересмотреть');

    final members = (shield['servers'] as List).cast<String>();
    expect(members, isNotEmpty);

    final plain = <String>[];
    for (final tag in members) {
      final s = byTag[tag];
      expect(s, isNotNull, reason: 'член группы $tag не объявлен в шаблоне');
      if (!encrypted.contains(s!['type'])) plain.add('$tag (${s['type']})');
    }
    expect(plain, isEmpty,
        reason: 'открытый резолв в «щите»: при mode=fastest эти члены '
            'выигрывают гонку у DoH/DoT — $plain');
  });

  test('dns_shield покрывает четыре провайдера шифрованно', () {
    final members = ((baseServersByTag(template())['dns_shield']!)['servers']
            as List)
        .cast<String>()
        .toSet();


    for (final tag in [
      'google_doh',
      'google_dot',
      'cloudflare_dot',
      'opendns_doh',
      'quad9_doh',
      'yandex_dot',
    ]) {
      expect(members, contains(tag));
    }
  });

  test('opendns_doh — корректная запись DoH по образцу соседей', () {
    final s = baseServersByTag(template())['opendns_doh'];
    expect(s, isNotNull, reason: 'замена opendns_udp в группе не объявлена');
    expect(s!['type'], 'https');
    expect(s['server_port'], 443);
    expect(s['server'], '208.67.222.222');
    expect(s['path'], '/dns-query');
    expect((s['tls'] as Map)['enabled'], true);
    expect((s['tls'] as Map)['server_name'], 'dns.opendns.com');
  });

  test('записи *_udp остались объявлены (на них ссылаются другие места)', () {
    final byTag = allServersByTag(template());
    for (final tag in [
      'google_udp',
      'cloudflare_udp',
      'opendns_udp',
      'yandex_udp',
    ]) {
      expect(byTag[tag], isNotNull, reason: '$tag удалён — сломает ссылки');
      expect(byTag[tag]!['type'], 'udp');
    }
  });

  test('§527 каждый член dns_shield объявлен в БАЗОВЫХ dns_options.servers',
      () {








    final base = baseServersByTag(template());
    final members = (base['dns_shield']!['servers'] as List).cast<String>();
    final undeclared = members.where((t) => !base.containsKey(t)).toList();
    expect(undeclared, isEmpty,
        reason: 'член группы объявлен только в пресете — при сборке его тег '
            'получит префикс preset_id и bare-ссылка выпадет (unknown): '
            '$undeclared');
  });

  test('§527 yandex_dot — прямой DoT без detour', () {
    final s = baseServersByTag(template())['yandex_dot'];
    expect(s, isNotNull, reason: 'базовая запись yandex_dot исчезла');
    expect(s!['type'], 'tls');
    expect(s['server'], '77.88.8.8');
    expect(s['server_port'], 853);
    expect((s['tls'] as Map)['enabled'], true);


    expect((s['tls'] as Map)['server_name'], 'common.dot.dns.yandex.net');


    expect(s.containsKey('detour'), isFalse,
        reason: 'detour у члена «щита» вернёт зависимость от туннеля');
  });

  test('quad9_doh сохраняет detour vpn-1 (§517: намеренно не трогаем)', () {




    expect(baseServersByTag(template())['quad9_doh']!['detour'], 'vpn-1');
  });
}
