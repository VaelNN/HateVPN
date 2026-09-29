import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/dependency_graph.dart';


void main() {



  String config({List<String> vpn2Members = const ['RU', 'DE']}) =>
      jsonEncode({
        'outbounds': [
          {'type': 'vless', 'tag': 'RU', 'server': '1.2.3.4'},
          {'type': 'vless', 'tag': 'DE', 'server': '5.6.7.8'},
          {'type': 'vless', 'tag': 'chained', 'detour': 'RU'},
          {'type': 'selector', 'tag': 'vpn-2', 'outbounds': vpn2Members},
          {
            'type': 'selector',
            'tag': 'vpn-9',
            'outbounds': ['chained', 'DE'],
          },
          {
            'type': 'urltest',
            'tag': 'auto-1',
            'outbounds': ['RU', 'DE'],
          },
        ],
        'endpoints': [
          {'type': 'wireguard', 'tag': 'wg-ep', 'detour': 'vpn-2'},
        ],
        'dns': {
          'servers': [
            {'type': 'udp', 'tag': 'yandex_udp', 'detour': 'vpn-2'},
            {'type': 'https', 'tag': 'doh2', 'detour': 'vpn-9'},
            {'type': 'udp', 'tag': 'plain', 'server': '8.8.8.8'},
          ],
        },
      });

  Map<String, Map<String, int>> delays(Map<String, int> flat) =>
      {'vpn-1': flat};

  test('репро инцидента: dead-нода, выбранная Направлением, заражает dns и ноды',
      () {
    final g = DependencyGraph.fromConfig(config());
    final sick = g.computeSick(
      selections: {'vpn-2': 'RU'},
      delays: delays({'RU': -1}),
    );
    expect(sick.keys, ['RU']);
    final tags = {for (final d in sick['RU']!) d.tag: d};

    expect(tags['chained']!.via, isNull);
    expect(tags['chained']!.kind, 'node');

    expect(tags['yandex_udp']!.via, 'vpn-2');
    expect(tags['yandex_udp']!.isDns, isTrue);
    expect(tags['wg-ep']!.via, 'vpn-2');


    expect(tags.containsKey('doh2'), isFalse);
  });

  test('двухступенчатая цепочка: нода → Направление → нода → Направление → dns', () {
    final g = DependencyGraph.fromConfig(config());
    final sick = g.computeSick(
      selections: {'vpn-2': 'RU', 'vpn-9': 'chained'},
      delays: delays({'RU': -1}),
    );
    final tags = {for (final d in sick['RU']!) d.tag: d};
    expect(tags['doh2']!.via, 'vpn-9');
  });

  test('живой замер в любом Направлении снимает dead (консервативное правило)', () {
    final g = DependencyGraph.fromConfig(config());
    final sick = g.computeSick(
      selections: {'vpn-2': 'RU'},
      delays: {
        'vpn-1': {'RU': -1},
        'vpn-4': {'RU': 150},
      },
    );
    expect(sick, isEmpty);
  });

  test('нода без замеров — unknown, не тревожим', () {
    final g = DependencyGraph.fromConfig(config());
    final sick = g.computeSick(
      selections: {'vpn-2': 'RU'},
      delays: delays({'DE': 100}),
    );
    expect(sick, isEmpty);
  });

  test('dead-нода без зависимых — не корень', () {
    final g = DependencyGraph.fromConfig(config());


    final sick = g.computeSick(
      selections: {'vpn-2': 'RU'},
      delays: delays({'DE': -1}),
    );
    expect(sick, isEmpty);
  });

  test('urltest-Направление не болеет по выбору (самолечение §308)', () {
    final g = DependencyGraph.fromConfig(jsonEncode({
      'outbounds': [
        {'type': 'vless', 'tag': 'RU'},
        {'type': 'vless', 'tag': 'DE'},
        {
          'type': 'urltest',
          'tag': 'auto-x',
          'outbounds': ['RU', 'DE'],
        },
        {'type': 'vless', 'tag': 'onAuto', 'detour': 'auto-x'},
      ],
      'dns': {'servers': []},
    }));


    final sick = g.computeSick(
      selections: {'auto-x': 'RU'},
      delays: delays({'RU': -1}),
    );
    expect(sick, isEmpty);
  });

  test('urltest болен только при полностью мёртвом составе', () {
    final g = DependencyGraph.fromConfig(jsonEncode({
      'outbounds': [
        {'type': 'vless', 'tag': 'RU'},
        {'type': 'vless', 'tag': 'DE'},
        {
          'type': 'urltest',
          'tag': 'auto-x',
          'outbounds': ['RU', 'DE'],
        },
        {'type': 'vless', 'tag': 'onAuto', 'detour': 'auto-x'},
      ],
      'dns': {'servers': []},
    }));
    final sick = g.computeSick(
      selections: const {},
      delays: delays({'RU': -1, 'DE': -3}),
    );

    expect(sick.keys, containsAll(['RU', 'DE']));
    expect(sick['RU']!.single.tag, 'onAuto');
    expect(sick['RU']!.single.via, 'auto-x');
  });

  test('смена выбора Направления на живую ноду снимает болезнь', () {
    final g = DependencyGraph.fromConfig(config());
    final sick = g.computeSick(
      selections: {'vpn-2': 'DE'},
      delays: delays({'RU': -1, 'DE': 120}),
    );


    expect(sick.keys, ['RU']);
    expect(sick['RU']!.map((d) => d.tag), ['chained']);
  });

  test('malformed JSON → пустой граф', () {
    final g = DependencyGraph.fromConfig('{broken');
    expect(g.isEmpty, isTrue);
    expect(g.computeSick(selections: const {}, delays: const {}), isEmpty);
  });

  test('directDependents отдаёт прямых зависимых без динамики', () {
    final g = DependencyGraph.fromConfig(config());
    expect(
      g.directDependents('vpn-2').map((d) => d.tag).toSet(),
      {'yandex_udp', 'wg-ep'},
    );
    expect(g.directDependents('RU').single.tag, 'chained');
  });
}
