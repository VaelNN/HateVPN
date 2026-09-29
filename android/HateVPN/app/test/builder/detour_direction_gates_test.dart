import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/direction.dart';
import 'package:lxbox/models/custom_rule.dart';
import 'package:lxbox/models/node_link.dart';
import 'package:lxbox/models/parser_config.dart';
import 'package:lxbox/models/server_list.dart';
import 'package:lxbox/models/validation.dart';
import 'package:lxbox/services/builder/build_config.dart';
import 'package:lxbox/services/parser/uri_parsers.dart';

import '../parser/engine_test_setup.dart';













void main() {


  setUpAll(loadEngineSections);






  WizardTemplate template() => WizardTemplate(
        parserConfig: ParserConfigBlock(),
        groupTemplates: GroupTemplates(),
        vars: const [],
        varSections: const [],
        config: {
          'outbounds': [
            {'tag': 'direct-out', 'type': 'direct'},
            {'tag': 'block', 'type': 'block'},
          ],
          'route': {'rules': []},
        },
        selectableRules: const [],
        dnsOptions: const {},
        pingOptions: const {},
        speedTestOptions: const {},
      );


  UserServer vlessServer({
    required String id,
    required List<String> names,
    DetourPolicy policy = DetourPolicy.defaults,
  }) =>
      UserServer(
        id: id,
        name: id,
        enabled: true,
        tagPrefix: '',
        detourPolicy: policy,
        origin: UserSource.paste,
        nodes: [
          for (final n in names)
            parseUri('vless://u-$id@h-$id.com:443?type=ws&security=tls#$n')!,
        ],
      );

  Future<BuildResult> build(List<ServerList> lists, List<Direction> directions,
      {String routeFinal = ''}) async {
    final r = await buildConfig(
      lists: lists,
      template: template(),
      settings: BuildSettings(directions: directions, routeFinal: routeFinal),
    );
    expect(r.validation.isOk, true, reason: r.validation.issues.join('\n'));
    return r;
  }

  List<Map<String, dynamic>> outs(BuildResult r) =>
      (r.config['outbounds'] as List).cast<Map<String, dynamic>>();

  Map<String, dynamic> byTag(BuildResult r, String tag) =>
      outs(r).firstWhere((o) => o['tag'] == tag);

  group('§274 — block-опция и пустой fallback', () {
    test('block эмитится у detour-Направления при includeBlock=true', () async {


      final r = await build([
        vlessServer(id: 'u', names: ['A']),
      ], [
        const Direction(tag: 'vpn-1', label: 'Main'),
        const Direction(
            tag: 'vpn-2', label: 'Relay', isDetour: true, includeBlock: true),
      ]);
      expect(byTag(r, 'vpn-2')['outbounds'], contains('block'));

      expect(r.directionsWithoutNodes, isEmpty);
    });

    test('пустое detour-Направление → [block, direct-out] c default=block + warning',
        () async {



      final r = await build([
        vlessServer(id: 'u', names: ['A']),
      ], [
        const Direction(tag: 'vpn-1', label: 'Main'),
        const Direction(
            tag: 'vpn-2',
            label: 'Relay',
            isDetour: true,
            nodeFilter: 'no-such-node'),
      ]);
      final vpn2 = byTag(r, 'vpn-2');
      expect(vpn2['outbounds'], ['block', 'direct-out']);
      expect(vpn2['default'], 'block');

      expect(
          r.emitWarnings,
          contains(contains(
              'Direction "⚙ Relay" (vpn-2): node filter matched no nodes')));


      expect(r.directionsWithoutNodes, ['⚙ Relay']);
    });

    test('пустой ОБЫЧНЫЙ Направление — прежний §201 [block, direct-out]', () async {
      final r = await build([
        vlessServer(id: 'u', names: ['A']),
      ], [
        const Direction(tag: 'vpn-1', label: 'Main'),
        const Direction(tag: 'vpn-2', label: 'X', nodeFilter: 'no-such-node'),
      ]);
      final vpn2 = byTag(r, 'vpn-2');
      expect(vpn2['outbounds'], ['block', 'direct-out']);
      expect(vpn2['default'], 'block');

      expect(r.directionsWithoutNodes, ['X']);

      expect(r.emitWarnings,
          contains(contains('traffic is blocked (default)')));
    });

    test(
        'include_direct × 0 нод: первая опция direct-out, warning честен '
        '(«goes direct», НЕ «blocked»)', () async {



      final r = await build([
        vlessServer(id: 'u', names: ['A']),
      ], [
        const Direction(tag: 'vpn-1', label: 'Main'),
        const Direction(
            tag: 'vpn-2',
            label: 'X',
            includeDirect: true,
            nodeFilter: 'no-such-node'),
      ]);
      final vpn2 = byTag(r, 'vpn-2');
      expect(vpn2['outbounds'], ['direct-out']);
      expect(vpn2.containsKey('default'), isFalse);
      expect(r.emitWarnings,
          contains(contains('traffic goes direct (no VPN hop)')));
      expect(r.emitWarnings,
          isNot(contains(contains('traffic is blocked'))));
      expect(r.directionsWithoutNodes, ['X']);
    });

    test('негативные кейсы directionsWithoutNodes: не вина фильтра — не варним',
        () async {

      final withNodes = await build([
        vlessServer(id: 'u', names: ['A']),
      ], [
        const Direction(tag: 'vpn-1', label: 'Main'),
      ]);
      expect(withNodes.directionsWithoutNodes, isEmpty);


      final noSubs = await build(<ServerList>[], [
        const Direction(tag: 'vpn-1', label: 'Main', nodeFilter: 'anything'),
      ]);
      expect(noSubs.directionsWithoutNodes, isEmpty);

      final emptyAll = await build(<ServerList>[], [
        const Direction(tag: 'vpn-1', label: 'Main'),
      ]);
      expect(emptyAll.directionsWithoutNodes, isEmpty);
    });
  });

  group('§254/§393 A4 — detour-циклы: разрывает санитайзер, не валидатор', () {



















    Future<BuildResult> buildRaw(
            List<ServerList> lists, List<Direction> directions) =>
        buildConfig(
          lists: lists,
          template: template(),
          settings: BuildSettings(directions: directions),
        );

    List<DetourCycle> cyclesOf(BuildResult r) =>
        r.validation.fatal.whereType<DetourCycle>().toList();

    test('прямой цикл: member.detour=C → член вон из состава, detour цел',
        () async {



      final r = await buildRaw([
        vlessServer(
            id: 'u',
            names: ['Relay Berlin'],
            policy: const DetourPolicy(overrideDetour: NodeLink(tag: 'vpn-2'))),
      ], [
        const Direction(tag: 'vpn-1', label: 'Main'),
        const Direction(
            tag: 'vpn-2', label: 'Relay', isDetour: true, nodeFilter: 'Relay'),
      ]);
      expect(r.validation.isOk, isTrue, reason: r.validation.issues.join('\n'));
      expect(cyclesOf(r), isEmpty, reason: '§254-fatal больше не нужен');
      expect(byTag(r, 'Relay Berlin')['detour'], 'vpn-2',
          reason: 'fail-open: detour пользователя сохранён');
      expect(
          r.emitWarnings,
          contains(contains(
              'Outbound "Relay Berlin" detours through group "vpn-2" it '
              'belongs to')));

      expect(byTag(r, 'vpn-2')['outbounds'], ['block', 'direct-out']);
      expect(byTag(r, 'vpn-2')['default'], 'block');
    });

    test('цикл через auto-двойник (detour=<tag>-auto) — тот же разрыв',
        () async {



      final r = await buildRaw([
        vlessServer(
            id: 'u',
            names: ['Relay Berlin'],
            policy: const DetourPolicy(overrideDetour: NodeLink(tag: 'vpn-2-auto'))),
      ], [
        const Direction(tag: 'vpn-1', label: 'Main'),
        const Direction(
            tag: 'vpn-2',
            label: 'Relay',
            isDetour: true,
            nodeFilter: 'Relay',
            auto: DirectionAuto()),
      ]);
      expect(r.validation.isOk, isTrue, reason: r.validation.issues.join('\n'));
      expect(cyclesOf(r), isEmpty);
      expect(outs(r).any((o) => o['tag'] == 'vpn-2-auto'), isFalse,
          reason: 'опустевший двойник дропнут');
      expect(byTag(r, 'Relay Berlin').containsKey('detour'), isFalse,
          reason: 'detour на дропнутый двойник снят каскадом');
      expect(r.emitWarnings, contains(contains('Detour removed')));

      expect(byTag(r, 'vpn-2')['outbounds'], ['Relay Berlin']);
    });

    test('транзитивный цикл через промежуточный узел — рвётся ОДНО ребро',
        () async {




      final r = await buildRaw([
        vlessServer(
            id: 'c',
            names: ['Client'],
            policy: const DetourPolicy(overrideDetour: NodeLink(tag: 'Mid'))),
        vlessServer(
            id: 'm',
            names: ['Mid'],
            policy: const DetourPolicy(overrideDetour: NodeLink(tag: 'vpn-2'))),
      ], [
        const Direction(tag: 'vpn-1', label: 'Main'),
        const Direction(
            tag: 'vpn-2',
            label: 'Relay',
            isDetour: true,
            nodeFilter: 'Client'),
      ]);
      expect(r.validation.isOk, isTrue, reason: r.validation.issues.join('\n'));
      expect(cyclesOf(r), isEmpty);
      expect(
          r.emitWarnings,
          contains(contains(
              'Dependency cycle through detour "Client" → "Mid"')));
      expect(byTag(r, 'Client').containsKey('detour'), isFalse);

      expect(byTag(r, 'Mid')['detour'], 'vpn-2');
      expect(byTag(r, 'vpn-2')['outbounds'], ['Client']);
    });

    test('цикл между Направлениями: A∈C1→C2, B∈C2→C1 — одно разорванное ребро',
        () async {
      final r = await buildRaw([
        vlessServer(
            id: 'a',
            names: ['Node A'],
            policy: const DetourPolicy(overrideDetour: NodeLink(tag: 'vpn-3'))),
        vlessServer(
            id: 'b',
            names: ['Node B'],
            policy: const DetourPolicy(overrideDetour: NodeLink(tag: 'vpn-2'))),
      ], [
        const Direction(tag: 'vpn-1', label: 'Main'),
        const Direction(
            tag: 'vpn-2', label: 'C1', isDetour: true, nodeFilter: 'Node A'),
        const Direction(
            tag: 'vpn-3', label: 'C2', isDetour: true, nodeFilter: 'Node B'),
      ]);
      expect(r.validation.isOk, isTrue, reason: r.validation.issues.join('\n'));
      expect(cyclesOf(r), isEmpty);


      final broken = r.emitWarnings
          .where((w) => w.contains('Dependency cycle'))
          .toList();
      expect(broken, hasLength(1));
      expect(byTag(r, 'vpn-2')['outbounds'], ['Node A']);
      expect(byTag(r, 'vpn-3')['outbounds'], ['Node B']);
    });

    test('ссылка на ОБЫЧНОЕ Направление (Debug API-сценарий) — тот же разрыв',
        () async {
      final r = await buildRaw([
        vlessServer(
            id: 'u',
            names: ['Node X'],
            policy: const DetourPolicy(overrideDetour: NodeLink(tag: 'vpn-2'))),
      ], [
        const Direction(tag: 'vpn-1', label: 'Main'),
        const Direction(tag: 'vpn-2', label: 'Plain', nodeFilter: 'Node X'),
      ]);
      expect(r.validation.isOk, isTrue, reason: r.validation.issues.join('\n'));
      expect(cyclesOf(r), isEmpty);
      expect(
          r.emitWarnings,
          contains(contains(
              'Outbound "Node X" detours through group "vpn-2" it belongs '
              'to')));
      expect(byTag(r, 'Node X')['detour'], 'vpn-2');
    });

    test('флагман §248: relay в той же подписке под overrideDetour=C — '
        'вон из состава relay, клиенты невиновны', () async {



      final r = await buildRaw([
        vlessServer(
            id: 'u',
            names: ['Relay Berlin', 'Client A', 'Client B'],
            policy: const DetourPolicy(overrideDetour: NodeLink(tag: 'vpn-2'))),
      ], [
        const Direction(tag: 'vpn-1', label: 'Main'),
        const Direction(
            tag: 'vpn-2',
            label: 'Relay',
            isDetour: true,
            nodeFilter: 'Relay',
            auto: DirectionAuto()),
      ]);
      expect(r.validation.isOk, isTrue, reason: r.validation.issues.join('\n'));
      expect(cyclesOf(r), isEmpty);





      final cyclicLines = r.emitWarnings
          .where((w) => w.contains('it belongs to — excluded'))
          .toList();
      expect(cyclicLines, hasLength(1));
      expect(cyclicLines.single, contains('"Relay Berlin"'));
      expect(cyclicLines.single, contains('"vpn-2"'));
      expect(cyclicLines.single, contains('"vpn-2-auto"'));
      for (final tag in ['Relay Berlin', 'Client A', 'Client B']) {
        expect(byTag(r, tag)['detour'], 'vpn-2', reason: '$tag: detour цел');
      }
      expect(byTag(r, 'vpn-2')['outbounds'], ['block', 'direct-out'],
          reason: 'состав опустел → block-fallback (§201/§274)');
    });

    test('реальный кейс §254: флот∈C1→C2, одна нода∈C2→C1 — рвётся ребро '
        'ровно у неё, флот цел', () async {









      final r = await buildRaw([
        vlessServer(
            id: 'bl',
            names: ['BL Sofia', 'BL Zagreb', 'BL Varna'],
            policy: const DetourPolicy(overrideDetour: NodeLink(tag: 'vpn-3'))),
        vlessServer(id: 'in1', names: ['IN Masque A']),
        vlessServer(id: 'in2', names: ['IN Masque B']),
        vlessServer(
            id: 'awg',
            names: ['IN Awg'],
            policy: const DetourPolicy(overrideDetour: NodeLink(tag: 'vpn-2'))),
      ], [
        const Direction(tag: 'vpn-1', label: 'Main'),
        const Direction(
            tag: 'vpn-2', label: 'BL', isDetour: true, nodeFilter: 'BL'),
        const Direction(
            tag: 'vpn-3', label: 'WARP IN', isDetour: true, nodeFilter: 'IN'),
      ]);
      expect(r.validation.isOk, isTrue, reason: r.validation.issues.join('\n'));
      expect(cyclesOf(r), isEmpty);

      final degraded =
          r.emitWarnings.where((w) => w.contains('Dependency cycle')).toList();
      expect(degraded, hasLength(1));
      expect(degraded.single, contains('"IN Awg"'));
      expect(byTag(r, 'IN Awg').containsKey('detour'), isFalse);

      for (final tag in ['BL Sofia', 'BL Zagreb', 'BL Varna']) {
        expect(byTag(r, tag)['detour'], 'vpn-3', reason: '$tag невиновен');
      }
      expect(byTag(r, 'vpn-2')['outbounds'],
          ['BL Sofia', 'BL Zagreb', 'BL Varna']);
      expect(degraded.single, isNot(contains('BL Sofia')));
    });

    test('линейная цепочка Направлений C1→C2→C3 без замыкания → ok', () async {


      final r = await build([
        vlessServer(
            id: 'out',
            names: ['OUT Warp'],
            policy: const DetourPolicy(overrideDetour: NodeLink(tag: 'vpn-3'))),
        vlessServer(
            id: 'bl',
            names: ['BL Sofia', 'BL Zagreb'],
            policy: const DetourPolicy(overrideDetour: NodeLink(tag: 'vpn-4'))),
        vlessServer(id: 'in1', names: ['IN Masque'])
      ], [
        const Direction(tag: 'vpn-1', label: 'Main'),
        const Direction(
            tag: 'vpn-2', label: 'OUT', isDetour: true, nodeFilter: 'OUT'),
        const Direction(
            tag: 'vpn-3', label: 'BL', isDetour: true, nodeFilter: 'BL'),
        const Direction(
            tag: 'vpn-4', label: 'WARP IN', isDetour: true, nodeFilter: 'IN'),
      ]);
      expect(byTag(r, 'BL Sofia')['detour'], 'vpn-4');
      expect(byTag(r, 'OUT Warp')['detour'], 'vpn-3');
      expect(r.emitWarnings, isNot(contains(contains('Dependency cycle'))));
      expect(r.emitWarnings,
          isNot(contains(contains('it belongs to — excluded'))));
    });

    test('два независимых кольца → два разрыва, по одному на кольцо', () async {



      final r = await buildRaw([
        vlessServer(
            id: 'x',
            names: ['Node X'],
            policy: const DetourPolicy(overrideDetour: NodeLink(tag: 'vpn-2'))),
        vlessServer(
            id: 'y',
            names: ['Node Y'],
            policy: const DetourPolicy(overrideDetour: NodeLink(tag: 'vpn-3'))),
      ], [
        const Direction(tag: 'vpn-1', label: 'Main'),
        const Direction(
            tag: 'vpn-2', label: 'C1', isDetour: true, nodeFilter: 'Node X'),
        const Direction(
            tag: 'vpn-3', label: 'C2', isDetour: true, nodeFilter: 'Node Y'),
      ]);
      expect(r.validation.isOk, isTrue, reason: r.validation.issues.join('\n'));
      expect(cyclesOf(r), isEmpty);

      final degraded = r.emitWarnings
          .where((w) => w.contains('it belongs to — excluded'))
          .toList();
      expect(degraded, hasLength(2));
      expect(degraded.join('\n'), contains('"Node X"'));
      expect(degraded.join('\n'), contains('"Node Y"'));

      for (final tag in ['vpn-2', 'vpn-3']) {
        expect(byTag(r, tag)['outbounds'], ['block', 'direct-out']);
        expect(byTag(r, tag)['default'], 'block');
      }
    });
  });

  group('§274/§248 — custom-rule на detour-Направление и омонимия', () {
    test('custom-rule на detour-Направление → конфиг валиден (штатно, §274)',
        () async {



      final r = await buildConfig(
        lists: [vlessServer(id: 'u', names: ['A'])],
        template: template(),
        settings: BuildSettings(
          directions: const [
            Direction(tag: 'vpn-1', label: 'Main'),
            Direction(tag: 'vpn-2', label: 'Relay', isDetour: true),
          ],
          customRules: [
            CustomRuleInline(
                name: 'Pin', domains: const ['x.com'], outbound: 'vpn-2'),
          ],
        ),
      );
      expect(r.validation.isOk, true,
          reason: r.validation.issues.join('\n'));
    });

    test('омоним: member.detour=тёзка Направления → интра-ребро на члена', () async {



      final folder = FolderServers(
        id: 'f1',
        name: 'Homonym',
        enabled: true,
        tagPrefix: 'hm-',
        detourPolicy: DetourPolicy.defaults,
        members: [
          FolderMember(raw: 'vless://u@h.com:443?type=ws&security=tls#vpn-2'),
          FolderMember(
              raw: 'vless://u2@h2.com:443?type=ws&security=tls#node-b',
              detour: const NodeLink(folderId: 'f1', tag: 'vpn-2')),
        ],
      );
      final r = await build([
        folder,
        vlessServer(id: 'x', names: ['Exit Node']),
      ], [
        const Direction(tag: 'vpn-1', label: 'Main'),
        const Direction(
            tag: 'vpn-2', label: 'Relay', isDetour: true, nodeFilter: 'Exit'),
      ]);
      expect(byTag(r, 'hm- node-b')['detour'], 'hm- vpn-2');
      expect(r.emitWarnings, isNot(contains(contains('removed detour'))));
      expect(r.emitWarnings, isNot(contains(contains('routing loop'))));
    });
  });

  group('§274 — route_final может быть detour-Направлением', () {
    test('route_final=detour-Направление остаётся, warning отсутствует', () async {


      final r = await build(
        [vlessServer(id: 'u', names: ['A'])],
        [
          const Direction(tag: 'vpn-1', label: 'Main'),
          const Direction(tag: 'vpn-2', label: 'Relay', isDetour: true),
        ],
        routeFinal: 'vpn-2',
      );
      expect((r.config['route'] as Map)['final'], 'vpn-2');
      expect(
          r.emitWarnings, isNot(contains(contains('is a detour direction'))));
      expect(
          r.emitWarnings, isNot(contains(contains('switched to vpn-1'))));
    });

    test('route_final=auto-двойник detour-Направления остаётся (двойник эмитится)',
        () async {


      final r = await build(
        [vlessServer(id: 'u', names: ['A'])],
        [
          const Direction(tag: 'vpn-1', label: 'Main'),
          const Direction(
              tag: 'vpn-2',
              label: 'Relay',
              isDetour: true,
              auto: DirectionAuto()),
        ],
        routeFinal: 'vpn-2-auto',
      );
      expect((r.config['route'] as Map)['final'], 'vpn-2-auto');
      expect(
          r.emitWarnings, isNot(contains(contains('is a detour direction'))));
    });

    test('route_final=НЕэмитящийся auto-двойник (0 нод) → vpn-1 + warning',
        () async {



      final r = await build(
        [vlessServer(id: 'u', names: ['A'])],
        [
          const Direction(tag: 'vpn-1', label: 'Main'),
          const Direction(
              tag: 'vpn-2',
              label: 'Relay',
              isDetour: true,
              nodeFilter: 'no-such-node',
              auto: DirectionAuto()),
        ],
        routeFinal: 'vpn-2-auto',
      );
      expect((r.config['route'] as Map)['final'], 'vpn-1');
      expect(
          r.emitWarnings,
          contains(contains(
              'Route final "vpn-2-auto" no longer exists — switched to '
              'vpn-1')));
    });

    test('route_final=обычное Направление остаётся как есть', () async {
      final r = await build(
        [vlessServer(id: 'u', names: ['A'])],
        [
          const Direction(tag: 'vpn-1', label: 'Main'),
          const Direction(tag: 'vpn-2', label: 'Plain'),
        ],
        routeFinal: 'vpn-2',
      );
      expect((r.config['route'] as Map)['final'], 'vpn-2');
    });
  });
}
