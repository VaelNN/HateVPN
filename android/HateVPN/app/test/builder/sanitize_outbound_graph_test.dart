import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/services/builder/post_steps.dart';
import 'package:lxbox/services/builder/validator.dart';






void main() {
  List<Map<String, dynamic>> outs(Map<String, dynamic> config) =>
      (config['outbounds'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic>? byTag(Map<String, dynamic> config, String tag) {
    for (final o in [
      ...(config['outbounds'] as List? ?? const []),
      ...(config['endpoints'] as List? ?? const []),
    ]) {
      if (o is Map<String, dynamic> && o['tag'] == tag) return o;
    }
    return null;
  }

  group('правило 1 — висячий detour (поглощённый §172)', () {
    test('битый detour ("warp gen") → снят, нода остаётся', () {
      final config = {
        'outbounds': [
          {'tag': '🇫🇮 Finland', 'type': 'vless', 'detour': 'warp gen'},
          {'tag': 'direct-out', 'type': 'direct'},
        ],
      };
      final warnings = sanitizeOutboundGraph(config);

      expect(warnings, hasLength(1));
      expect(warnings.single, contains('Detour removed'));
      expect(warnings.single, contains('"warp gen"'));
      expect(warnings.single, contains('"🇫🇮 Finland"'));
      final node = outs(config)[0];
      expect(node.containsKey('detour'), isFalse, reason: 'detour снят');
      expect(node['tag'], '🇫🇮 Finland', reason: 'нода не выброшена');
      expect(outs(config), hasLength(2));
    });

    test('валидный detour → НЕ трогаем', () {
      final config = {
        'outbounds': [
          {'tag': 'main', 'type': 'vless', 'detour': 'hop'},
          {'tag': 'hop', 'type': 'shadowsocks'},
        ],
      };
      expect(sanitizeOutboundGraph(config), isEmpty);
      expect(outs(config)[0]['detour'], 'hop');
    });

    test('detour на endpoint (wireguard) → валиден, НЕ трогаем', () {
      final config = {
        'outbounds': [
          {'tag': 'main', 'type': 'vless', 'detour': 'wg-1'},
        ],
        'endpoints': [
          {'tag': 'wg-1', 'type': 'wireguard'},
        ],
      };
      expect(sanitizeOutboundGraph(config), isEmpty);
      expect(outs(config)[0]['detour'], 'wg-1');
    });

    test('несколько битых detour → все сняты, валидный уцелел', () {
      final config = {
        'outbounds': [
          {'tag': 'a', 'type': 'vless', 'detour': 'ghost1'},
          {'tag': 'b', 'type': 'vless', 'detour': 'ghost2'},
          {'tag': 'c', 'type': 'vless', 'detour': 'a'},
          {'tag': 'direct-out', 'type': 'direct'},
        ],
      };
      final warnings = sanitizeOutboundGraph(config);

      expect(warnings.where((w) => w.contains('Detour removed')), hasLength(2));
      expect(outs(config)[2]['detour'], 'a');
      expect(outs(config)[0].containsKey('detour'), isFalse);
      expect(outs(config)[1].containsKey('detour'), isFalse);
    });

    test('detour endpoint\'а на призрака тоже деградирует', () {
      final config = {
        'endpoints': [
          {'tag': 'wg-1', 'type': 'wireguard', 'detour': 'ghost'},
        ],
      };
      final warnings = sanitizeOutboundGraph(config);
      expect(warnings, hasLength(1));
      expect((config['endpoints'] as List)[0], isNot(contains('detour')));
    });

    test('нет detour-полей → no-op', () {
      final config = {
        'outbounds': [
          {'tag': 'a', 'type': 'direct'},
        ],
      };
      expect(sanitizeOutboundGraph(config), isEmpty);
    });

    test('§377 — одна агрегированная строка на отсутствующий target', () {
      final config = {
        'outbounds': [
          for (var i = 1; i <= 7; i++)
            {'tag': 'Node-$i', 'type': 'vless', 'detour': 'warp gen'},
          {'tag': 'direct-out', 'type': 'direct'},
        ],
      };
      final lines = sanitizeOutboundGraph(config)
          .where((w) => w.contains('Detour removed'))
          .toList();

      expect(lines, hasLength(1), reason: 'одна строка на target, не 7');
      expect(lines.single, contains('7 outbounds'));
      expect(lines.single, contains('"Node-5"'));
      expect(lines.single, isNot(contains('"Node-6"')));
      expect(lines.single, contains('and 2 more'));
      expect(lines.single, contains('nodes work directly'));
    });
  });

  group('правило 2 — члены-призраки состава группы', () {
    test('призрачный член исключён, живые остаются', () {
      final config = {
        'outbounds': [
          {'tag': 'n1', 'type': 'vless'},
          {
            'tag': 'grp',
            'type': 'selector',
            'outbounds': ['n1', 'ghost'],
          },
        ],
      };
      final warnings = sanitizeOutboundGraph(config);
      expect(byTag(config, 'grp')!['outbounds'], ['n1']);
      expect(warnings.single, contains('"ghost"'));
      expect(warnings.single, contains('do not exist in the final config'));
    });

    test('include-тег на несуществующее Направление исключён (A3-остаток)',
        () {



      final config = {
        'outbounds': [
          {'tag': 'n1', 'type': 'vless'},
          {
            'tag': 'vpn-2',
            'type': 'selector',
            'outbounds': ['vpn-1', 'n1'],
          },
        ],
      };
      sanitizeOutboundGraph(config, directionTags: {'vpn-1', 'vpn-2'});
      expect(byTag(config, 'vpn-2')!['outbounds'], ['n1']);
    });

    test('состав узла автовыбора чистится так же (urltest)', () {
      final config = {
        'outbounds': [
          {'tag': 'n1', 'type': 'vless'},
          {
            'tag': 'vpn-1-auto',
            'type': 'urltest',
            'outbounds': ['n1', 'gone'],
          },
        ],
      };
      sanitizeOutboundGraph(config);
      expect(byTag(config, 'vpn-1-auto')!['outbounds'], ['n1']);
    });

    test('прочая группа, оставшаяся без участников → дроп с warning', () {
      final config = {
        'outbounds': [
          {
            'tag': '✨auto',
            'type': 'urltest',
            'outbounds': ['gone1', 'gone2'],
          },
          {'tag': 'direct-out', 'type': 'direct'},
        ],
      };
      final warnings = sanitizeOutboundGraph(config);
      expect(byTag(config, '✨auto'), isNull, reason: 'группа дропнута');
      expect(warnings.any((w) => w.contains('no members left')), isTrue);
    });

    test('пустеющее Направление → block-fallback, НЕ дроп', () {
      final config = {
        'outbounds': [
          {
            'tag': 'vpn-1',
            'type': 'selector',
            'outbounds': ['gone'],
          },
          {'tag': 'block', 'type': 'block'},
          {'tag': 'direct-out', 'type': 'direct'},
        ],
      };
      final warnings = sanitizeOutboundGraph(config, directionTags: {'vpn-1'});
      final dir = byTag(config, 'vpn-1')!;
      expect(dir, isNotNull, reason: 'Направление — цель правил, не дропается');
      expect(dir['outbounds'], ['block', 'direct-out']);
      expect(dir['default'], 'block');
      expect(warnings.any((w) => w.contains('traffic is blocked')), isTrue);
    });
  });

  group('правило 3 — default вне состава', () {
    test('default-призрак → заменён на первого участника с warning', () {
      final config = {
        'outbounds': [
          {'tag': 'n1', 'type': 'vless'},
          {'tag': 'n2', 'type': 'vless'},
          {
            'tag': 'grp',
            'type': 'selector',
            'outbounds': ['n1', 'n2'],
            'default': 'gone',
          },
        ],
      };
      final warnings = sanitizeOutboundGraph(config);
      expect(byTag(config, 'grp')!['default'], 'n1');
      expect(warnings.any((w) => w.contains('replaced with "n1"')), isTrue);
    });

    test('default выпал из состава каскадом → подхвачен kept[0]', () {
      final config = {
        'outbounds': [
          {'tag': 'n1', 'type': 'vless'},
          {
            'tag': 'grp',
            'type': 'selector',
            'outbounds': ['ghost', 'n1'],
            'default': 'ghost',
          },
        ],
      };
      sanitizeOutboundGraph(config);
      expect(byTag(config, 'grp')!['outbounds'], ['n1']);
      expect(byTag(config, 'grp')!['default'], 'n1');
    });

    test('default=block от emptyFallback НЕ перетирается', () {



      final config = {
        'outbounds': [
          {
            'tag': 'vpn-1',
            'type': 'selector',
            'outbounds': ['block', 'direct-out'],
            'default': 'block',
          },
          {'tag': 'block', 'type': 'block'},
          {'tag': 'direct-out', 'type': 'direct'},
        ],
      };
      final warnings = sanitizeOutboundGraph(config, directionTags: {'vpn-1'});
      expect(warnings, isEmpty);
      expect(byTag(config, 'vpn-1')!['default'], 'block');
      expect(byTag(config, 'vpn-1')!['outbounds'], ['block', 'direct-out']);
    });

    test('валидный default → не трогаем', () {
      final config = {
        'outbounds': [
          {'tag': 'n1', 'type': 'vless'},
          {'tag': 'n2', 'type': 'vless'},
          {
            'tag': 'grp',
            'type': 'selector',
            'outbounds': ['n1', 'n2'],
            'default': 'n2',
          },
        ],
      };
      expect(sanitizeOutboundGraph(config), isEmpty);
      expect(byTag(config, 'grp')!['default'], 'n2');
    });
  });

  group('правило 4 — узел с detour на группу со своим участием', () {
    test('вон из состава, detour СОХРАНЁН (fail-open)', () {


      final config = {
        'outbounds': [
          {'tag': 'Proton', 'type': 'vless', 'detour': 'vpn-2'},
          {'tag': 'Other', 'type': 'vless'},
          {
            'tag': 'vpn-2',
            'type': 'selector',
            'outbounds': ['Proton', 'Other'],
          },
        ],
      };
      final warnings = sanitizeOutboundGraph(config, directionTags: {'vpn-2'});

      expect(byTag(config, 'vpn-2')!['outbounds'], ['Other']);
      expect(byTag(config, 'Proton')!['detour'], 'vpn-2',
          reason: 'detour сохранён — fail-open');
      expect(
          warnings.any((w) => w.contains(
              'Outbound "Proton" detours through group "vpn-2" it belongs '
              'to — excluded from it')),
          isTrue);
      expect(validateConfig(config).isOk, isTrue);
    });

    test('detour на СЕЛЕКТОР при живом auto-двойнике → вон из обоих', () {





      final config = {
        'outbounds': [
          {'tag': 'Relay', 'type': 'vless', 'detour': 'vpn-2'},
          {'tag': 'Other', 'type': 'vless'},
          {
            'tag': 'vpn-2-auto',
            'type': 'urltest',
            'outbounds': ['Relay', 'Other'],
          },
          {
            'tag': 'vpn-2',
            'type': 'selector',
            'outbounds': ['vpn-2-auto', 'Relay', 'Other'],
          },
        ],
      };
      final warnings = sanitizeOutboundGraph(config, directionTags: {'vpn-2'});

      expect(byTag(config, 'vpn-2')!['outbounds'], ['vpn-2-auto', 'Other']);
      expect(byTag(config, 'vpn-2-auto')!['outbounds'], ['Other']);
      expect(byTag(config, 'Relay')!['detour'], 'vpn-2',
          reason: 'fail-open: detour пережил обе группы');
      expect(warnings.every((w) => !w.contains('Dependency cycle')), isTrue,
          reason: 'кольцо снято правилом 4, до правила 5 не дошло');
      expect(validateConfig(config).isOk, isTrue);
    });

    test(
        'композиция fail-open → fail-closed: detour цел, но КОМПОЗИТНЫЙ '
        'warning называет узел и последствие', () {








      final config = {
        'outbounds': [
          {'tag': 'block', 'type': 'block'},
          {'tag': 'direct-out', 'type': 'direct'},
          {
            'tag': 'vpn-1',
            'type': 'selector',
            'outbounds': ['a'],
          },
          {'tag': 'a', 'type': 'vless', 'detour': 'vpn-1'},
        ],
      };
      final warnings = sanitizeOutboundGraph(config, directionTags: {'vpn-1'});


      expect(byTag(config, 'a')!['detour'], 'vpn-1');

      expect(byTag(config, 'vpn-1')!['outbounds'], ['block', 'direct-out']);
      expect(byTag(config, 'vpn-1')!['default'], 'block');

      final composite = warnings
          .where((w) => w.contains('which is now blocked'))
          .toList();
      expect(composite, hasLength(1), reason: 'композитный warning есть');
      expect(composite.single, contains('"a"'), reason: 'узел назван');
      expect(composite.single, contains('"vpn-1"'));
      expect(composite.single, contains('traffic is blocked too'),
          reason: 'последствие названо прямым текстом');
      expect(composite.single, contains('outside the VPN'),
          reason: 'объяснено, почему detour не снят');
      expect(validateConfig(config).isOk, isTrue);
    });

    test(
        'Направление в block-fallback БЕЗ живых detour-ов → композитного '
        'warning нет', () {



      final config = {
        'outbounds': [
          {
            'tag': 'vpn-1',
            'type': 'selector',
            'outbounds': ['gone'],
          },
          {'tag': 'block', 'type': 'block'},
          {'tag': 'direct-out', 'type': 'direct'},
        ],
      };
      final warnings = sanitizeOutboundGraph(config, directionTags: {'vpn-1'});
      expect(warnings.any((w) => w.contains('which is now blocked')), isFalse);
    });

    test('единственный участник детурит в группу → Направление в block', () {
      final config = {
        'outbounds': [
          {'tag': 'Proton', 'type': 'vless', 'detour': 'vpn-1'},
          {
            'tag': 'vpn-1',
            'type': 'selector',
            'outbounds': ['Proton'],
          },
          {'tag': 'block', 'type': 'block'},
          {'tag': 'direct-out', 'type': 'direct'},
        ],
      };
      sanitizeOutboundGraph(config, directionTags: {'vpn-1'});
      expect(byTag(config, 'vpn-1')!['outbounds'], ['block', 'direct-out']);
      expect(byTag(config, 'Proton')!['detour'], 'vpn-1');
      expect(validateConfig(config).isOk, isTrue);
    });
  });

  group('§377-агрегация правила 4 — по УЗЛУ, а не по группе', () {
    test('узел в селекторе И в auto-двойнике → ОДИН warning со списком групп',
        () {



      final config = {
        'outbounds': [
          {'tag': 'Relay', 'type': 'vless', 'detour': 'vpn-1'},
          {'tag': 'Other', 'type': 'vless'},
          {
            'tag': 'vpn-1-auto',
            'type': 'urltest',
            'outbounds': ['Relay', 'Other'],
          },
          {
            'tag': 'vpn-1',
            'type': 'selector',
            'outbounds': ['vpn-1-auto', 'Relay', 'Other'],
          },
        ],
      };
      final warnings = sanitizeOutboundGraph(config, directionTags: {'vpn-1'});

      final lines =
          warnings.where((w) => w.contains('it belongs to — excluded')).toList();
      expect(lines, hasLength(1), reason: 'один узел — один warning, не два');
      expect(lines.single, contains('"Relay"'));
      expect(lines.single, contains('"vpn-1"'));
      expect(lines.single, contains('"vpn-1-auto"'));
      expect(lines.single, contains('groups'),
          reason: 'множественное число при двух группах');
      expect(byTag(config, 'Relay')!['detour'], 'vpn-1');
      expect(validateConfig(config).isOk, isTrue);
    });

    test('два разных виноватых узла в одной группе → два warning\'а', () {


      final config = {
        'outbounds': [
          {'tag': 'A', 'type': 'vless', 'detour': 'vpn-1'},
          {'tag': 'B', 'type': 'vless', 'detour': 'vpn-1'},
          {'tag': 'C', 'type': 'vless'},
          {
            'tag': 'vpn-1',
            'type': 'selector',
            'outbounds': ['A', 'B', 'C'],
          },
        ],
      };
      final warnings = sanitizeOutboundGraph(config, directionTags: {'vpn-1'});
      final lines =
          warnings.where((w) => w.contains('it belongs to — excluded')).toList();
      expect(lines, hasLength(2));
      expect(lines.join('\n'), contains('"A"'));
      expect(lines.join('\n'), contains('"B"'));
      expect(byTag(config, 'vpn-1')!['outbounds'], ['C']);
    });
  });

  group('ФИКС 2 — честный текст про цель, снятую самим санитайзером', () {
    test('НЕ-Направленческая группа дропнута → detour снят, «missing» нет',
        () {





      final config = {
        'outbounds': [
          {
            'tag': 'g',
            'type': 'selector',
            'outbounds': ['a'],
          },
          {'tag': 'a', 'type': 'vless', 'detour': 'g'},
        ],
      };
      final warnings = sanitizeOutboundGraph(config);

      expect(byTag(config, 'g'), isNull, reason: 'группа дропнута');
      expect(byTag(config, 'a'), isNotNull, reason: 'узел жив');
      expect(byTag(config, 'a')!.containsKey('detour'), isFalse,
          reason: 'detour снят правилом 1 — цели больше нет');

      final line = warnings.singleWhere((w) => w.startsWith('Detour removed:'));
      expect(line, contains('"a"'));
      expect(line, contains('"g"'));
      expect(line, contains('left with no members and removed during sanitation'),
          reason: 'честная причина');
      expect(line, isNot(contains('missing')),
          reason: 'санитайзер не сваливает вину на подписку');
    });

    test('цель, которой не было изначально → прежний текст «missing»', () {


      final config = {
        'outbounds': [
          {
            'tag': 'g',
            'type': 'selector',
            'outbounds': ['a'],
          },
          {'tag': 'a', 'type': 'vless', 'detour': 'g'},
          {'tag': 'b', 'type': 'vless', 'detour': 'never-existed'},
        ],
      };
      final lines = sanitizeOutboundGraph(config)
          .where((w) => w.startsWith('Detour removed:'))
          .toList();

      expect(lines, hasLength(2));
      final missing =
          lines.singleWhere((w) => w.contains('"never-existed"'));
      expect(missing, contains('referenced missing'));
      expect(missing, contains('"b"'));
      final sanitized = lines.singleWhere((w) => w.contains('"g"'));
      expect(sanitized, contains('removed during sanitation'));
      expect(sanitized, isNot(contains('missing')));
    });
  });

  group('ФИКС 3 — живость только по ФАКТУ записи (контракт с валидатором)', () {
    test('block БЕЗ записи в конфиге — призрак, как и для validateConfig', () {




      final config = {
        'outbounds': [
          {'tag': 'n1', 'type': 'vless', 'detour': 'block'},
          {
            'tag': 'grp',
            'type': 'selector',
            'outbounds': ['n1', 'block'],
          },
        ],
      };
      sanitizeOutboundGraph(config);
      expect(byTag(config, 'n1')!.containsKey('detour'), isFalse);
      expect(byTag(config, 'grp')!['outbounds'], ['n1']);
      expect(validateConfig(config).isOk, isTrue,
          reason: 'санитайзер не оставляет валидатору фатальной ссылки');
    });

    test('block С записью (боевой wizard_template) — живой', () {



      final config = {
        'outbounds': [
          {'tag': 'n1', 'type': 'vless', 'detour': 'block'},
          {
            'tag': 'grp',
            'type': 'selector',
            'outbounds': ['n1', 'block'],
          },
          {'tag': 'block', 'type': 'block'},
          {'tag': 'direct-out', 'type': 'direct'},
        ],
      };
      expect(sanitizeOutboundGraph(config), isEmpty);
      expect(byTag(config, 'n1')!['detour'], 'block');
      expect(byTag(config, 'grp')!['outbounds'], ['n1', 'block']);
    });

    test('ACTION-псевдоцели правил (direct/reject/drop) — не outbound-теги',
        () {



      final config = {
        'outbounds': [
          {'tag': 'n1', 'type': 'vless', 'detour': 'reject'},
          {'tag': 'n2', 'type': 'vless', 'detour': 'direct'},
          {'tag': 'n3', 'type': 'vless', 'detour': 'dns-out'},
        ],
      };
      sanitizeOutboundGraph(config);
      for (final t in ['n1', 'n2', 'n3']) {
        expect(byTag(config, t)!.containsKey('detour'), isFalse, reason: t);
      }
      expect(validateConfig(config).isOk, isTrue);
    });
  });

  group('правило 5 — кольца по любым рёбрам', () {
    test('detour→группа→член: кольцо разорвано, конфиг валиден', () {



      final config = {
        'outbounds': [
          {'tag': 'Node', 'type': 'vless', 'detour': 'vpn-1'},
          {'tag': 'Relay', 'type': 'vless', 'detour': 'Node'},
          {
            'tag': 'vpn-1',
            'type': 'selector',
            'outbounds': ['Relay'],
          },
        ],
      };
      final warnings = sanitizeOutboundGraph(config, directionTags: {'vpn-1'});
      expect(warnings.any((w) => w.contains('Dependency cycle')), isTrue);
      expect(validateConfig(config).isOk, isTrue,
          reason: '§254-fatal валидатора уже не срабатывает');
    });

    test('member-кольцо selector↔selector: замыкающее ребро исключено', () {
      final config = {
        'outbounds': [
          {'tag': 'n1', 'type': 'vless'},
          {
            'tag': 'vpn-1',
            'type': 'selector',
            'outbounds': ['vpn-2', 'n1'],
          },
          {
            'tag': 'vpn-2',
            'type': 'selector',
            'outbounds': ['vpn-1', 'n1'],
          },
        ],
      };
      final warnings =
          sanitizeOutboundGraph(config, directionTags: {'vpn-1', 'vpn-2'});
      expect(warnings.any((w) => w.contains('excluded from group')), isTrue);
      expect(validateConfig(config).isOk, isTrue);

      expect((byTag(config, 'vpn-1')!['outbounds'] as List), contains('n1'));
      expect((byTag(config, 'vpn-2')!['outbounds'] as List), contains('n1'));
    });

    test('include-кольцо после reorder (A3): состав спасён, кольца нет', () {



      final config = {
        'outbounds': [
          {'tag': 'n1', 'type': 'vless'},
          {'tag': 'n2', 'type': 'vless'},
          {
            'tag': 'vpn-1',
            'type': 'selector',
            'outbounds': ['vpn-2', 'n1'],
          },
          {
            'tag': 'vpn-2',
            'type': 'selector',
            'outbounds': ['vpn-1', 'n2'],
          },
        ],
      };
      sanitizeOutboundGraph(config, directionTags: {'vpn-1', 'vpn-2'});
      expect(validateConfig(config).isOk, isTrue);

      expect((byTag(config, 'vpn-1')!['outbounds'] as List), isNotEmpty);
      expect((byTag(config, 'vpn-2')!['outbounds'] as List), isNotEmpty);
    });

    test(
        '§254-минимальность: кольцо рвётся у виноватого, невиновный флот в '
        'составе цел', () {






      final config = {
        'outbounds': [
          for (final n in ['BL Sofia', 'BL Zagreb', 'BL Varna'])
            {'tag': n, 'type': 'vless', 'detour': 'vpn-3'},
          {'tag': 'IN Masque A', 'type': 'vless'},
          {'tag': 'IN Awg', 'type': 'vless', 'detour': 'vpn-2'},
          {
            'tag': 'vpn-2',
            'type': 'selector',
            'outbounds': ['BL Sofia', 'BL Zagreb', 'BL Varna'],
          },
          {
            'tag': 'vpn-3',
            'type': 'selector',
            'outbounds': ['IN Masque A', 'IN Awg'],
          },
        ],
      };
      final warnings =
          sanitizeOutboundGraph(config, directionTags: {'vpn-2', 'vpn-3'});

      expect(warnings, hasLength(1), reason: 'ровно одна деградация');
      expect(warnings.single, contains('"IN Awg"'));
      expect(warnings.single, contains('detour removed'));
      expect(byTag(config, 'IN Awg')!.containsKey('detour'), isFalse);

      for (final n in ['BL Sofia', 'BL Zagreb', 'BL Varna']) {
        expect(byTag(config, n)!['detour'], 'vpn-3', reason: '$n невиновен');
      }
      expect(byTag(config, 'vpn-2')!['outbounds'],
          ['BL Sofia', 'BL Zagreb', 'BL Varna']);
      expect(validateConfig(config).isOk, isTrue);
    });

    test('detour-самоссылка (self-loop) → detour снят', () {
      final config = {
        'outbounds': [
          {'tag': 'loop', 'type': 'vless', 'detour': 'loop'},
        ],
      };
      final warnings = sanitizeOutboundGraph(config);
      expect(byTag(config, 'loop')!.containsKey('detour'), isFalse);
      expect(warnings.any((w) => w.contains('Dependency cycle')), isTrue);
    });

    test('чистый граф без колец → no-op', () {
      final config = {
        'outbounds': [
          {'tag': 'hop', 'type': 'vless'},
          {'tag': 'n1', 'type': 'vless', 'detour': 'hop'},
          {
            'tag': 'vpn-1',
            'type': 'selector',
            'outbounds': ['n1', 'hop'],
            'default': 'n1',
          },
        ],
      };
      expect(sanitizeOutboundGraph(config, directionTags: {'vpn-1'}), isEmpty);
    });
  });

  group('КАСКАД до фикспойнта', () {
    test('дроп группы → член-призрак → пустеющая группа → висячая ссылка', () {







      final config = {
        'outbounds': [
          {
            'tag': 'inner',
            'type': 'urltest',
            'outbounds': ['gone'],
          },
          {
            'tag': 'mid',
            'type': 'selector',
            'outbounds': ['inner'],
            'default': 'inner',
          },
          {
            'tag': 'outer',
            'type': 'selector',
            'outbounds': ['mid'],
          },
          {
            'tag': 'vpn-1',
            'type': 'selector',
            'outbounds': ['outer'],
          },
          {'tag': 'Rider', 'type': 'vless', 'detour': 'outer'},
          {'tag': 'block', 'type': 'block'},
          {'tag': 'direct-out', 'type': 'direct'},
        ],
      };
      sanitizeOutboundGraph(config, directionTags: {'vpn-1'});

      expect(byTag(config, 'inner'), isNull);
      expect(byTag(config, 'mid'), isNull);
      expect(byTag(config, 'outer'), isNull);
      expect(byTag(config, 'vpn-1')!['outbounds'], ['block', 'direct-out'],
          reason: 'Направление уцелело block-fallback\'ом');
      expect(byTag(config, 'vpn-1')!['default'], 'block');
      expect(byTag(config, 'Rider')!.containsKey('detour'), isFalse,
          reason: 'detour на дропнутую группу снят на следующей итерации');
      expect(validateConfig(config).isOk, isTrue);
    });

    test('каскад через endpoints: дроп группы чистит detour endpoint\'а', () {
      final config = {
        'outbounds': [
          {
            'tag': 'grp',
            'type': 'selector',
            'outbounds': ['gone'],
          },
        ],
        'endpoints': [
          {'tag': 'wg-1', 'type': 'wireguard', 'detour': 'grp'},
        ],
      };
      sanitizeOutboundGraph(config);
      expect(byTag(config, 'grp'), isNull);
      expect(byTag(config, 'wg-1')!.containsKey('detour'), isFalse);
      expect((config['endpoints'] as List), hasLength(1),
          reason: 'endpoint не дропнут, только его detour');
    });
  });








  group('правило 6 — висячий хоп дропает ЦЕПОЧКУ целиком', () {
    test('позиция на несуществующий тег → цепочки нет, состав НЕ правится', () {
      final config = {
        'outbounds': [
          {'tag': 'DE', 'type': 'vless'},
          {
            'tag': 'ch',
            'type': 'chain',
            'outbounds': ['DE', 'gone'],
          },
        ],
      };
      final warnings = sanitizeOutboundGraph(config);
      expect(byTag(config, 'ch'), isNull,
          reason: 'маршрут без хопа — другой маршрут, а не урезанный');
      expect(byTag(config, 'DE'), isNotNull, reason: 'узел невиновен');
      expect(warnings.join('\n'), contains('"gone"'));
      expect(warnings.join('\n'), contains('position 2'));
    });

    test('живая цепочка не трогается', () {
      final config = {
        'outbounds': [
          {'tag': 'DE', 'type': 'vless'},
          {'tag': 'NL', 'type': 'vless'},
          {
            'tag': 'ch',
            'type': 'chain',
            'outbounds': ['DE', 'NL'],
          },
        ],
      };
      expect(sanitizeOutboundGraph(config), isEmpty);
      expect(byTag(config, 'ch')!['outbounds'], ['DE', 'NL']);
    });

    test('каскад: группа опустела → снята → цепочка через неё дропнута', () {


      final config = {
        'outbounds': [
          {'tag': 'NL', 'type': 'vless'},
          {
            'tag': 'grp',
            'type': 'selector',
            'outbounds': ['ghost'],
          },
          {
            'tag': 'ch',
            'type': 'chain',
            'outbounds': ['grp', 'NL'],
          },
        ],
      };
      sanitizeOutboundGraph(config);
      expect(byTag(config, 'grp'), isNull);
      expect(byTag(config, 'ch'), isNull, reason: 'позиция исчезла каскадом');
      expect(byTag(config, 'NL'), isNotNull);
    });

    test('вложенная цепочка позицией ≥1 дропает внешнюю цепочку', () {


      final config = {
        'outbounds': [
          {'tag': 'DE', 'type': 'vless'},
          {'tag': 'NL', 'type': 'vless'},
          {
            'tag': 'inner',
            'type': 'chain',
            'outbounds': ['DE', 'NL'],
          },
          {
            'tag': 'outer',
            'type': 'chain',
            'outbounds': ['DE', 'inner'],
          },
        ],
      };
      final warnings = sanitizeOutboundGraph(config);
      expect(byTag(config, 'outer'), isNull);
      expect(byTag(config, 'inner'), isNotNull, reason: 'внутренняя невиновна');
      expect(warnings.join('\n'), contains('only as the first hop'));
    });

    test('вложенная цепочка ПОЗИЦИЕЙ 0 законна', () {
      final config = {
        'outbounds': [
          {'tag': 'DE', 'type': 'vless'},
          {'tag': 'NL', 'type': 'vless'},
          {
            'tag': 'inner',
            'type': 'chain',
            'outbounds': ['DE', 'NL'],
          },
          {
            'tag': 'outer',
            'type': 'chain',
            'outbounds': ['inner', 'NL'],
          },
        ],
      };
      expect(sanitizeOutboundGraph(config), isEmpty);
      expect(byTag(config, 'outer')!['outbounds'], ['inner', 'NL']);
    });

    test('цепочка НЕ считается группой: её хопы не «члены состава»', () {


      final config = {
        'outbounds': [
          {'tag': 'DE', 'type': 'vless'},
          {
            'tag': 'ch',
            'type': 'chain',
            'outbounds': ['DE', 'ghost'],
          },
        ],
      };
      final warnings = sanitizeOutboundGraph(config);
      expect(byTag(config, 'ch'), isNull);
      expect(warnings.join('\n'), isNot(contains('excluded from the group')));
    });
  });

  group('правило 7 — цепочки в листьях группы, стоящей позицией ≥1', () {
    test('группа-позиция ≥1 теряет цепочку из состава (сама группа жива)', () {



      final config = {
        'outbounds': [
          {'tag': 'DE', 'type': 'vless'},
          {'tag': 'NL', 'type': 'vless'},
          {
            'tag': 'nested',
            'type': 'chain',
            'outbounds': ['DE', 'NL'],
          },
          {
            'tag': 'grp',
            'type': 'selector',
            'outbounds': ['DE', 'nested'],
          },
          {
            'tag': 'outer',
            'type': 'chain',
            'outbounds': ['NL', 'grp'],
          },
        ],
      };
      final warnings = sanitizeOutboundGraph(config);
      expect(byTag(config, 'grp')!['outbounds'], ['DE'],
          reason: 'цепочка вычеркнута ИЗ СОСТАВА — тут она взаимозаменяемая опция');
      expect(byTag(config, 'nested'), isNotNull, reason: 'сама цепочка жива');
      expect(byTag(config, 'outer'), isNotNull);
      expect(warnings.join('\n'), contains('only as the first hop'));
    });

    test('ТРАНЗИТИВНО через вложенную группу', () {
      final config = {
        'outbounds': [
          {'tag': 'DE', 'type': 'vless'},
          {'tag': 'NL', 'type': 'vless'},
          {
            'tag': 'nested',
            'type': 'chain',
            'outbounds': ['DE', 'NL'],
          },
          {
            'tag': 'inner-grp',
            'type': 'selector',
            'outbounds': ['DE', 'nested'],
          },
          {
            'tag': 'outer-grp',
            'type': 'selector',
            'outbounds': ['inner-grp'],
          },
          {
            'tag': 'ch',
            'type': 'chain',
            'outbounds': ['NL', 'outer-grp'],
          },
        ],
      };
      sanitizeOutboundGraph(config);
      expect(byTag(config, 'inner-grp')!['outbounds'], ['DE']);
    });

    test('группа ПОЗИЦИЕЙ 0 цепочки состав не теряет', () {

      final config = {
        'outbounds': [
          {'tag': 'DE', 'type': 'vless'},
          {'tag': 'NL', 'type': 'vless'},
          {
            'tag': 'nested',
            'type': 'chain',
            'outbounds': ['DE', 'NL'],
          },
          {
            'tag': 'grp',
            'type': 'selector',
            'outbounds': ['DE', 'nested'],
          },
          {
            'tag': 'ch',
            'type': 'chain',
            'outbounds': ['grp', 'NL'],
          },
        ],
      };
      expect(sanitizeOutboundGraph(config), isEmpty);
      expect(byTag(config, 'grp')!['outbounds'], ['DE', 'nested']);
    });

    test('группа без цепочек в составе не трогается', () {
      final config = {
        'outbounds': [
          {'tag': 'DE', 'type': 'vless'},
          {'tag': 'NL', 'type': 'vless'},
          {
            'tag': 'grp',
            'type': 'selector',
            'outbounds': ['DE', 'NL'],
          },
          {
            'tag': 'ch',
            'type': 'chain',
            'outbounds': ['DE', 'grp'],
          },
        ],
      };
      expect(sanitizeOutboundGraph(config), isEmpty);
      expect(byTag(config, 'grp')!['outbounds'], ['DE', 'NL']);
    });
  });

  group('правило 5 — кольцо через позицию цепочки', () {
    test('цепочка через группу, содержащую саму цепочку → разрыв', () {



      final config = {
        'outbounds': [
          {'tag': 'DE', 'type': 'vless'},
          {
            'tag': 'grp',
            'type': 'selector',
            'outbounds': ['DE', 'ch'],
          },
          {
            'tag': 'ch',
            'type': 'chain',
            'outbounds': ['grp', 'DE'],
          },
        ],
      };
      final warnings = sanitizeOutboundGraph(config);
      expect(warnings, isNotEmpty);

      expect(validateConfig(config).isOk, isTrue);
      final grp = byTag(config, 'grp');
      final ch = byTag(config, 'ch');
      expect(grp == null || !(grp['outbounds'] as List).contains('ch') ||
          ch == null, isTrue);
    });
  });

}
