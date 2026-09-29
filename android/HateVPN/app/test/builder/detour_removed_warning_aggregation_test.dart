import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/config/consts.dart';
import 'package:lxbox/models/node_link.dart';
import 'package:lxbox/models/parser_config.dart';
import 'package:lxbox/models/server_list.dart';
import 'package:lxbox/services/builder/build_config.dart';
import 'package:lxbox/services/parser/uri_parsers.dart';

import '../parser/engine_test_setup.dart';










void main() {


  setUpAll(loadEngineSections);

  final template = WizardTemplate(
    parserConfig: ParserConfigBlock(),
    groupTemplates: GroupTemplates(
      direction: DirectionTemplate(include: const ['direct', 'auto']),
      auto: AutoTemplate(
        options: const {'url': 'https://x', 'interval': '30s'},
      ),
      defaultDirections: [
        DefaultDirection(tag: 'vpn-1', label: 'vpn-1', defaultEnabled: true),
      ],
    ),
    vars: const [],
    varSections: const [],
    config: {
      'outbounds': [
        {'tag': 'direct-out', 'type': 'direct'},
      ],
      'route': {'rules': []},
    },
    selectableRules: const [],
    dnsOptions: const {},
    pingOptions: const {},
    speedTestOptions: const {},
  );


  UserServer ghostConsumers(String target, int count, {String id = 'ghosts'}) =>
      UserServer(
        id: id,
        name: 'Ghosts',
        enabled: true,
        tagPrefix: '',
        detourPolicy: DetourPolicy(overrideDetour: NodeLink(tag: target)),
        origin: UserSource.paste,
        nodes: [
          for (var i = 1; i <= count; i++)
            parseUri('vless://u$i@h$i.com:443?type=ws&security=tls#Node-$i')!,
        ],
      );

  Future<({List<String> lines, Set<String> tags})> build(
      List<ServerList> lists) async {
    final result = await buildConfig(
      lists: lists,
      template: template,
      settings: const BuildSettings(
        userVars: {'clash_api': '127.0.0.1:9090'},
        enabledGroups: {'vpn-1', kAutoOutboundTag},
      ),
    );
    return (
      lines: result.emitWarnings
          .where((w) => w.contains('did not resolve'))
          .toList(),
      tags: {
        for (final o in result.config['outbounds'] as List)
          (o as Map)['tag'] as String,
      },
    );
  }

  group('§377 — агрегация висячего detour', () {
    test('138 нод на один отсутствующий target → одна строка', () async {
      final r = await build([ghostConsumers('warp gen', 138)]);

      expect(r.lines, hasLength(1), reason: 'одна строка на target, не 138');
      final line = r.lines.single;
      expect(line, startsWith('138 nodes ('));
      expect(line, contains('"warp gen"'));

      expect(line, contains('"Node-1"'));
      expect(line, contains('"Node-5"'));
      expect(line, isNot(contains('"Node-6"')));
      expect(line, contains('and 133 more'));
      expect(line, contains('never goes direct'));

      expect(r.tags.where((t) => t.startsWith('Node-')), isEmpty);
    });

    test('ровно 5 нод → все имена, без «and N more»', () async {
      final r = await build([ghostConsumers('warp gen', 5)]);

      expect(r.lines, hasLength(1));
      expect(r.lines.single, contains('"Node-5"'));
      expect(r.lines.single, isNot(contains('more')));
    });

    test('одна нода → имя без счётчика, единственное число', () async {
      final r = await build([ghostConsumers('warp gen', 1)]);

      expect(r.lines, hasLength(1));
      final line = r.lines.single;
      expect(line, startsWith('Node "Node-1" was skipped: its detour'));
      expect(line, isNot(contains('1 nodes')));
    });

    test('два разных отсутствующих target → две строки', () async {
      final r = await build([
        ghostConsumers('warp gen', 3, id: 'g1'),
        ghostConsumers('warp gen 2', 2, id: 'g2'),
      ]);

      expect(r.lines, hasLength(2));
      expect(r.lines.where((l) => l.contains('"warp gen"')), hasLength(1));
      expect(r.lines.where((l) => l.contains('"warp gen 2"')), hasLength(1));
    });
  });
}
