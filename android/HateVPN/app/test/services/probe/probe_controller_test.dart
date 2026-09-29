import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/auto_select.dart';
import 'package:lxbox/models/node_spec.dart';
import 'package:lxbox/models/server_list.dart';
import 'package:lxbox/services/probe/probe_controller.dart';
import 'package:lxbox/services/probe/probe_runner.dart';

import '../../parser/engine_test_setup.dart';


void main() {


  setUpAll(loadEngineSections);

  ProbeResult ok(int ms) => ProbeResult(ProbeStatus.ok, delayMs: ms);
  const failed = ProbeResult(ProbeStatus.failed);
  const broken = ProbeResult(ProbeStatus.broken);
  const pending = ProbeResult(ProbeStatus.pending);
  const groupNode = ProbeResult(ProbeStatus.group);

  group('unreachableIndexes', () {
    test('failed/broken/invalid → в наборе; ok/pending/group → нет', () {
      final probe = {
        0: ok(100),
        1: failed,
        2: broken,
        3: const ProbeResult(ProbeStatus.invalid),
        4: pending,

        5: groupNode,
      };
      expect(ProbeController.unreachableIndexes(probe), {1, 2, 3});
    });
    test('пусто → пустой набор', () {
      expect(ProbeController.unreachableIndexes({}), isEmpty);
    });
  });

  group('slowerThan', () {
    test('только ok медленнее порога', () {
      final probe = {0: ok(100), 1: ok(500), 2: ok(300), 3: failed};
      expect(ProbeController.slowerThan(probe, 250), {1, 2});
    });
    test('failed НЕ попадает (не ok)', () {
      expect(ProbeController.slowerThan({0: failed}, 0), isEmpty);
    });
  });

  group('pingSortOrder', () {
    test('ok по возрастанию delay, err в конец, stable tie-break', () {
      final probe = {0: ok(300), 1: failed, 2: ok(100), 3: pending};

      expect(ProbeController.pingSortOrder(probe, 4), [2, 0, 3, 1]);
    });
    test('нетестированные (нет в map) — как pending, перед err', () {
      final probe = {0: failed, 1: ok(50)};

      expect(ProbeController.pingSortOrder(probe, 3), [1, 2, 0]);
    });
    test('стабильность: равный ранг → по исходному индексу', () {
      final probe = {0: ok(100), 1: ok(100)};
      expect(ProbeController.pingSortOrder(probe, 2), [0, 1]);
    });
    test('§336: group — корзина «не тестировалась» (с pending), перед err', () {
      final probe = {0: failed, 1: groupNode, 2: ok(50), 3: pending};

      expect(ProbeController.pingSortOrder(probe, 4), [2, 1, 3, 0]);
    });
  });


  group('probeKeysForNodes', () {
    NodeSpec? node(String raw) => FolderMember(raw: raw).node;
    const uriA = 'vless://u1@h1.example:443?type=ws&security=tls#Alpha';
    const uriB = 'vless://u2@h2.example:443?type=ws&security=tls#Beta';

    test('§400 ключ = идентичность (тег); тёзку разводит `-2`, null → slot',
        () {



      final keys = ProbeController.probeKeysForNodes(
          [node(uriA), node(uriB), node(uriA), null]);
      expect(keys, ['Alpha', 'Beta', 'Alpha-2', 'slot:3']);
      expect(keys.toSet(), hasLength(4));
    });

    test('§400 узел БЕЗ идентичности падает на позиционный slot', () {


      final keys = ProbeController.probeKeysForNodes([
        AutoSelectSpec(
          id: 'g1',
          tag: 'Auto',
          label: 'Auto',
          membership: const RuleMembers(include: '.'),
        ),
        node(uriA),
      ]);
      expect(keys, ['slot:0', 'Alpha']);
    });

    test('ключ — функция идентичности: re-parse даёт тот же ключ', () {
      final k1 = ProbeController.probeKeysForNodes([node(uriA)]);
      final k2 = ProbeController.probeKeysForNodes([node(uriA)]);
      expect(k1, k2);
    });
  });



  group('probeKeys', () {
    FolderMember m(String raw) => FolderMember(raw: raw);
    const a = 'vless://u@h1:443?type=ws&security=tls#A';
    const b = 'vless://u@h2:443?type=ws&security=tls#B';

    test('разные узлы → разные ключи', () {
      final keys = ProbeController.probeKeys([m(a), m(b)]);
      expect(keys[0], isNot(keys[1]));
    });

    test('ключ не зависит от позиции: удаление соседа не двигает остальные', () {
      final before = ProbeController.probeKeys([m(a), m(b)]);
      final after = ProbeController.probeKeys([m(b)]);
      expect(after.single, before[1]);
    });

    test('§400 ПЕРЕИМЕНОВАНИЕ ключ МЕНЯЕТ — это смена идентичности', () {


      final keys = ProbeController.probeKeys([m(a), m('${a}renamed')]);
      expect(keys, ['A', 'Arenamed']);
    });

    test('§400 правка АДРЕСА ключ не меняет — имя то же', () {



      expect(ProbeController.probeKeys([m(a)]),
          ProbeController.probeKeys([m('vless://u@h9:443?type=ws&security=tls#A')]));
    });

    test('дубли одного узла ячейку не делят: X, X-2, X-3', () {



      final keys = ProbeController.probeKeys([m(a), m(a), m(a)]);
      expect(keys, ['A', 'A-2', 'A-3']);
    });

    test('битый член (node == null) получает raw-ключ', () {
      final keys = ProbeController.probeKeys([m('garbage'), m('other junk')]);
      expect(keys[0], 'raw:garbage');
      expect(keys[1], 'raw:other junk');
    });

    test('длина всегда равна числу членов (слот на каждую строку)', () {
      expect(ProbeController.probeKeys([m(a), m('garbage'), m(a)]).length, 3);
    });
  });

  group('probeNodesOf', () {
    test('папка → члены (nullable, unfiltered — сохраняет disabled+broken)', () {
      final folder = FolderServers(
        id: 'f', name: 'F', enabled: true, tagPrefix: 'p:',
        detourPolicy: DetourPolicy.defaults,
        members: [
          FolderMember(raw: 'vless://u@h:443?type=ws&security=tls#A'),
          FolderMember(raw: 'garbage'),
        ],
      );
      final nodes = ProbeController.probeNodesOf(folder);
      expect(nodes.length, 2);
      expect(nodes[1], isNull);
    });
    test('подписка → базовый nodes[]', () {
      final sub = SubscriptionServers(
        id: 's', name: 'S', enabled: true, tagPrefix: 'p:',
        detourPolicy: DetourPolicy.defaults, url: 'https://x',
        nodes: <NodeSpec>[],
      );
      expect(ProbeController.probeNodesOf(sub), sub.nodes);
    });
  });
}
