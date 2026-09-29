import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/import_rule.dart';
import 'package:lxbox/models/node_spec.dart';
import 'package:lxbox/models/template_vars.dart';
import 'package:lxbox/services/node_hash.dart';
import 'package:lxbox/services/parser/uri_parsers.dart';
import 'package:lxbox/services/subscription/import_rules.dart';

import '../parser/engine_test_setup.dart';




void main() {


  setUpAll(loadEngineSections);

  NodeSpec node(String uri) => parseUri(uri)!;





  NodeSpec fpNode(String fp, {String name = 'NL'}) =>
      node('vless://u@h.com:443?security=tls&sni=h.com&fp=$fp&type=ws#$name');

  ImportRuleCondition cond(
    String path,
    ImportRuleOperator op,
    String pattern, {
    bool negate = false,
    bool caseSensitive = false,
  }) =>
      ImportRuleCondition(
        path: path,
        op: op,
        pattern: pattern,
        negate: negate,
        caseSensitive: caseSensitive,
      );

  group('readJsonPath', () {
    test('лист, вложенный путь, отсутствие пути', () {
      final map = node('vless://u@h.com:443?security=tls&sni=x.com#A')
          .emit(TemplateVars.empty)
          .map;
      expect(readJsonPath(map, 'tag'), 'A');
      expect(readJsonPath(map, 'server'), 'h.com');
      expect(readJsonPath(map, 'tls.server_name'), 'x.com');
      expect(readJsonPath(map, 'nope'), isNull);
      expect(readJsonPath(map, 'tls.nope.deep'), isNull);
    });

    test('число отдаётся строкой, поддерево — компактным JSON', () {
      final map = node('vless://u@h.com:8443?security=tls&sni=x.com#A')
          .emit(TemplateVars.empty)
          .map;
      expect(readJsonPath(map, 'server_port'), '8443');
      final tls = readJsonPath(map, 'tls');
      expect(tls, startsWith('{'));
      expect(tls, contains('x.com'));
    });
  });

  group('writeJsonPath', () {
    test('пишет лист и создаёт промежуточные мапы', () {
      final map = <String, dynamic>{'tag': 'A'};
      expect(writeJsonPath(map, 'tag', 'B'), isTrue);
      expect(map['tag'], 'B');
      expect(writeJsonPath(map, 'tls.utls.fingerprint', 'chrome'), isTrue);
      expect((map['tls'] as Map)['utls'], {'fingerprint': 'chrome'});
    });

    test('сохраняет тип значения (порт остаётся числом)', () {
      final map = <String, dynamic>{'server_port': 443, 'ok': true};
      writeJsonPath(map, 'server_port', '8443');
      writeJsonPath(map, 'ok', 'false');
      expect(map['server_port'], 8443);
      expect(map['ok'], false);
    });

    test('не перезаписывает лист как мапу', () {
      final map = <String, dynamic>{'tag': 'A'};
      expect(writeJsonPath(map, 'tag.deep', 'x'), isFalse);
      expect(map['tag'], 'A');
    });

    test('§350: сегмент //... отвергается (unknown-field = fatal ядра)', () {
      final map = <String, dynamic>{'tag': 'A'};
      expect(writeJsonPath(map, '//note', 'x'), isFalse);
      expect(writeJsonPath(map, 'tls.//c.enabled', 'true'), isFalse);
      expect(map, {'tag': 'A'}, reason: 'ничего не создано по пути');
    });
  });

  group('условия', () {
    test('contains по tag — регистронезависим по умолчанию', () {
      final rule = ImportRule(
        conditions: [cond('tag', ImportRuleOperator.contains, 'nl')],
        action: ImportRuleAction.disable,
      );
      expect(applyRulesToNode(fpNode('chrome', name: 'NL-01'), [rule]).disabled,
          isTrue);

      expect(applyRulesToNode(fpNode('chrome', name: 'DE-01'), [rule]).disabled,
          isNull);
    });

    test('caseSensitive различает регистр', () {
      final rule = ImportRule(
        conditions: [
          cond('tag', ImportRuleOperator.contains, 'nl', caseSensitive: true)
        ],
        action: ImportRuleAction.disable,
      );
      expect(applyRulesToNode(fpNode('chrome', name: 'NL'), [rule]).disabled,
          isNull);
      expect(applyRulesToNode(fpNode('chrome', name: 'nl'), [rule]).disabled,
          isTrue);
    });

    test('equals требует полного совпадения', () {
      final rule = ImportRule(
        conditions: [cond('tag', ImportRuleOperator.equals, 'NL')],
        action: ImportRuleAction.disable,
      );
      expect(applyRulesToNode(fpNode('chrome', name: 'NL'), [rule]).disabled,
          isTrue);
      expect(applyRulesToNode(fpNode('chrome', name: 'NL-01'), [rule]).disabled,
          isNull);
    });

    test('negate инвертирует — и ловит отсутствие поля', () {
      final rule = ImportRule(
        conditions: [
          cond('tls.utls.fingerprint', ImportRuleOperator.contains, 'chrome',
              negate: true)
        ],
        action: ImportRuleAction.disable,
      );

      expect(applyRulesToNode(fpNode('chrome'), [rule]).disabled, isNull);

      expect(applyRulesToNode(fpNode('firefox'), [rule]).disabled, isTrue);

      expect(applyRulesToNode(node('vless://u@h.com:443#A'), [rule]).disabled,
          isTrue);
    });

    test('AND требует всех условий, OR — любого', () {
      final conds = [
        cond('tag', ImportRuleOperator.contains, 'NL'),
        cond('server', ImportRuleOperator.contains, 'zzz'),
      ];
      final and = ImportRule(
          conditions: conds,
          matchMode: ImportRuleMatchMode.all,
          action: ImportRuleAction.disable);
      final or = ImportRule(
          conditions: conds,
          matchMode: ImportRuleMatchMode.any,
          action: ImportRuleAction.disable);
      final n = fpNode('chrome', name: 'NL');
      expect(applyRulesToNode(n, [and]).disabled, isNull,
          reason: 'server не содержит zzz');
      expect(applyRulesToNode(n, [or]).disabled, isTrue,
          reason: 'tag содержит NL');
    });

    test('пустой путь = поиск по всему JSON узла', () {

      final rule = ImportRule(
        conditions: [cond('', ImportRuleOperator.contains, 'h.com')],
        action: ImportRuleAction.disable,
      );
      expect(rule.isUsable, isTrue, reason: 'пустой путь допустим в условии');

      expect(applyRulesToNode(fpNode('chrome'), [rule]).disabled, isTrue);

      final other = node('vless://u@other.net:443#A');
      expect(applyRulesToNode(other, [rule]).disabled, isNull);
    });

    test('пустой путь ловит значение в глубоком поле', () {

      final rule = ImportRule(
        conditions: [cond('', ImportRuleOperator.contains, 'firefox')],
        action: ImportRuleAction.disable,
      );
      expect(applyRulesToNode(fpNode('firefox'), [rule]).disabled, isTrue);
      expect(applyRulesToNode(fpNode('chrome'), [rule]).disabled, isNull);
    });

    test('Replace(set) с пустой целью непригоден (узел не затирается)', () {
      final rule = ImportRule(
        conditions: [cond('', ImportRuleOperator.contains, 'h.com')],
        action: ImportRuleAction.replace,
        targetPath: '',
        replacement: 'x',
      );
      expect(rule.isUsable, isFalse);
      expect(applyRulesToNode(fpNode('chrome'), [rule]).changed, isFalse);
    });

    test('битый regex делает правило непригодным (узел не трогаем)', () {
      final rule = ImportRule(
        conditions: [cond('tag', ImportRuleOperator.matches, '[')],
        action: ImportRuleAction.disable,
      );
      expect(rule.isUsable, isFalse);
      expect(applyRulesToNode(fpNode('chrome'), [rule]).disabled, isNull);
    });
  });

  group('Replace', () {
    test('set пишет значение целиком', () {
      final rule = ImportRule(
        conditions: [
          cond('tls.utls.fingerprint', ImportRuleOperator.contains, 'firefox')
        ],
        action: ImportRuleAction.replace,
        targetPath: 'tls.utls.fingerprint',
        replacement: 'chrome',
      );
      final out = applyRulesToNode(fpNode('firefox'), [rule]);
      expect(out.patchedJson, isNotNull);
      expect(readJsonPath(out.patchedJson!, 'tls.utls.fingerprint'), 'chrome');
    });

    test('карманы из matches подставляются в замену', () {
      final rule = ImportRule(
        conditions: [
          cond('tag', ImportRuleOperator.matches, r'^(NL)-\d+$'),
        ],
        action: ImportRuleAction.replace,
        targetPath: 'tag',
        replacement: r'$1',
      );
      final out = applyRulesToNode(fpNode('chrome', name: 'NL-01'), [rule]);
      expect(readJsonPath(out.patchedJson!, 'tag'), 'NL');
    });

    test('substitute вырезает фрагмент, остальное значение сохраняется', () {

      final rule = ImportRule(
        conditions: [
          cond('tag', ImportRuleOperator.matches, r'^(.*)⚡(.*)$'),
        ],
        action: ImportRuleAction.replace,
        targetPath: 'tag',
        replacement: r'$1$2',
      );
      final out = applyRulesToNode(fpNode('chrome', name: 'DE⚡Berlin'), [rule]);
      expect(readJsonPath(out.patchedJson!, 'tag'), 'DEBerlin');
    });

    test('substitute-режим по подстроке без regex', () {
      final rule = ImportRule(
        conditions: [cond('tag', ImportRuleOperator.contains, '⚡')],
        action: ImportRuleAction.replace,
        targetPath: 'tag',
        replaceMode: ImportRuleReplaceMode.substitute,
        replacement: '',
      );
      final out = applyRulesToNode(fpNode('chrome', name: 'DE⚡Berlin'), [rule]);
      expect(readJsonPath(out.patchedJson!, 'tag'), 'DEBerlin');
    });

    test('порт остаётся числом после замены', () {
      final rule = ImportRule(
        conditions: [cond('server_port', ImportRuleOperator.equals, '443')],
        action: ImportRuleAction.replace,
        targetPath: 'server_port',
        replacement: '8443',
      );
      final out = applyRulesToNode(fpNode('chrome'), [rule]);
      expect(out.patchedJson!['server_port'], 8443);
      expect(out.patchedJson!['server_port'], isA<int>());
    });

    test('замена того же значения — не считается изменением', () {
      final rule = ImportRule(
        conditions: [cond('tag', ImportRuleOperator.contains, 'NL')],
        action: ImportRuleAction.replace,
        targetPath: 'tag',
        replacement: 'NL',
      );
      final out = applyRulesToNode(fpNode('chrome', name: 'NL'), [rule]);
      expect(out.changed, isFalse);
    });





    test('§307: повторное применение стартует с чистого узла', () {
      final n = fpNode('chrome', name: 'NL-Ams');
      final rule = ImportRule(
        conditions: [cond('tag', ImportRuleOperator.contains, 'NL')],
        action: ImportRuleAction.replace,
        targetPath: 'tag',
        replaceMode: ImportRuleReplaceMode.substitute,
        substitutePattern: 'NL',
        replacement: 'XX NL',
      );
      final first = applyRulesToNode(n, [rule]);
      expect(readJsonPath(first.patchedJson!, 'tag'), 'XX NL-Ams');


      n.patchedJson = first.patchedJson;
      n.ruleTrail = first.replacements;
      final second = applyRulesToNode(n, [rule]);
      expect(readJsonPath(second.patchedJson!, 'tag'), 'XX NL-Ams',
          reason: 'не «XX XX NL-Ams» — прошлый патч не исходник');
      expect(second.patchedJson, first.patchedJson,
          reason: 'прогон детерминирован');
    });

    test('§307: emit отдаёт копию патча — мутации потребителя не текут', () {
      final n = fpNode('firefox', name: 'NL');
      final rule = ImportRule(
        conditions: [
          cond('tls.utls.fingerprint', ImportRuleOperator.contains, 'firefox')
        ],
        action: ImportRuleAction.replace,
        targetPath: 'tls.utls.fingerprint',
        replacement: 'chrome',
      );
      n.patchedJson = applyRulesToNode(n, [rule]).patchedJson;



      final e1 = n.emit(TemplateVars.empty);
      e1.map['tag'] = 'prefix ${e1.map['tag']}';
      e1.map['detour'] = 'hop';

      (e1.map['tls'] as Map<String, dynamic>)['server_name'] = 'evil.com';

      expect(n.patchedJson!['tag'], 'NL');
      expect(n.patchedJson!.containsKey('detour'), isFalse);
      expect(readJsonPath(n.patchedJson!, 'tls.server_name'), 'h.com');

      final e2 = n.emit(TemplateVars.empty);
      expect(e2.map['tag'], 'NL', reason: 'префикс не накапливается');
      expect(e2.map.containsKey('detour'), isFalse);
    });

    test('emit узла отдаёт патч (замена доезжает до конфига)', () {
      final n = fpNode('firefox');
      final rule = ImportRule(
        conditions: [
          cond('tls.utls.fingerprint', ImportRuleOperator.contains, 'firefox')
        ],
        action: ImportRuleAction.replace,
        targetPath: 'tls.utls.fingerprint',
        replacement: 'chrome',
      );
      final out = applyRulesToNode(n, [rule]);
      n.patchedJson = out.patchedJson;
      expect(
        readJsonPath(n.emit(TemplateVars.empty).map, 'tls.utls.fingerprint'),
        'chrome',
      );
    });
  });



  group('§307 Replace по всему узлу (пустая цель)', () {
    test('явный substitutePattern меняет все листья с совпадением', () {
      final rule = ImportRule(
        conditions: [cond('', ImportRuleOperator.contains, 'h.com')],
        action: ImportRuleAction.replace,
        targetPath: '',
        replaceMode: ImportRuleReplaceMode.substitute,
        substitutePattern: 'h.com',
        replacement: 'proxy.net',
      );
      expect(rule.isUsable, isTrue);
      final out = applyRulesToNode(fpNode('chrome'), [rule]);
      expect(out.patchedJson, isNotNull);

      expect(readJsonPath(out.patchedJson!, 'server'), 'proxy.net');
      expect(readJsonPath(out.patchedJson!, 'tls.server_name'), 'proxy.net');

      expect(out.replacements.any((t) => t.startsWith('server:')), isTrue);
      expect(out.replacements.any((t) => t.startsWith('tls.server_name:')),
          isTrue);
    });

    test('без явного паттерна берётся условие с пустым путём', () {

      final rule = ImportRule(
        conditions: [cond('', ImportRuleOperator.contains, '⚡')],
        action: ImportRuleAction.replace,
        targetPath: '',
        replaceMode: ImportRuleReplaceMode.substitute,
        replacement: '',
      );
      final out =
          applyRulesToNode(fpNode('chrome', name: 'DE⚡Berlin'), [rule]);
      expect(readJsonPath(out.patchedJson!, 'tag'), 'DEBerlin');
    });

    test('regex-условие: карманы раскрываются по совпадению в самом листе',
        () {
      final rule = ImportRule(
        conditions: [cond('', ImportRuleOperator.matches, r'NL-(\d+)')],
        action: ImportRuleAction.replace,
        targetPath: '',
        replaceMode: ImportRuleReplaceMode.substitute,
        replacement: r'N$1',
      );
      final out =
          applyRulesToNode(fpNode('chrome', name: 'NL-01'), [rule]);
      expect(readJsonPath(out.patchedJson!, 'tag'), 'N01');
    });

    test('тип листа сохраняется (порт остаётся числом)', () {
      final rule = ImportRule(
        conditions: [cond('', ImportRuleOperator.contains, '443')],
        action: ImportRuleAction.replace,
        targetPath: '',
        replaceMode: ImportRuleReplaceMode.substitute,
        substitutePattern: '443',
        replacement: '8443',
      );
      final out = applyRulesToNode(fpNode('chrome'), [rule]);
      expect(out.patchedJson!['server_port'], 8443);
      expect(out.patchedJson!['server_port'], isA<int>());
    });

    test('substitute без паттерна поиска непригоден (нечего искать)', () {
      final rule = ImportRule(
        conditions: [cond('tag', ImportRuleOperator.contains, 'NL')],
        action: ImportRuleAction.replace,
        targetPath: '',
        replaceMode: ImportRuleReplaceMode.substitute,
        replacement: 'x',
      );
      expect(rule.isUsable, isFalse);
    });

    test('summary показывает пустую цель как *', () {
      final rule = ImportRule(
        conditions: [cond('', ImportRuleOperator.contains, '⚡')],
        action: ImportRuleAction.replace,
        targetPath: '',
        replaceMode: ImportRuleReplaceMode.substitute,
        replacement: '',
      );
      expect(rule.summary, contains('* = '));
    });
  });




  group('§307 identity-хеш и патч', () {
    test('патч только тега не меняет nodeIdentityHash', () {
      final n = fpNode('chrome', name: 'NL');
      final before = legacyNodeIdentityHash(n);
      final rule = ImportRule(
        conditions: [cond('tag', ImportRuleOperator.contains, 'NL')],
        action: ImportRuleAction.replace,
        targetPath: 'tag',
        replacement: 'Amsterdam',
      );
      n.patchedJson = applyRulesToNode(n, [rule]).patchedJson;
      expect(legacyNodeIdentityHash(n), before);
    });

    test('патч сути (fingerprint) меняет хеш — by design §283', () {
      final n = fpNode('firefox');
      final before = legacyNodeIdentityHash(n);
      final rule = ImportRule(
        conditions: [
          cond('tls.utls.fingerprint', ImportRuleOperator.contains, 'firefox')
        ],
        action: ImportRuleAction.replace,
        targetPath: 'tls.utls.fingerprint',
        replacement: 'chrome',
      );
      n.patchedJson = applyRulesToNode(n, [rule]).patchedJson;
      expect(legacyNodeIdentityHash(n), isNot(before),
          reason: 'хеш считается от итогового вида узла');
    });
  });

  group('applyImportRules по списку узлов', () {
    test('индексы выключенных + следы замен', () {
      final nodes = [
        fpNode('chrome', name: 'NL-1'),
        fpNode('chrome', name: 'DE-1'),
        fpNode('firefox', name: 'NL-2'),
      ];
      final rules = [
        ImportRule(
          conditions: [cond('tag', ImportRuleOperator.contains, 'DE')],
          action: ImportRuleAction.disable,
        ),
        ImportRule(
          conditions: [
            cond('tls.utls.fingerprint', ImportRuleOperator.contains, 'firefox')
          ],
          action: ImportRuleAction.replace,
          targetPath: 'tls.utls.fingerprint',
          replacement: 'chrome',
        ),
      ];
      final res = applyImportRules(nodes, rules);
      expect(res.disabledIndexes, {1});
      expect(res.outcomes[2]!.replacements.single, contains('chrome'));
      expect(res.outcomes.containsKey(0), isFalse, reason: 'узел не затронут');
    });

    test('выключенное правило игнорируется', () {
      final res = applyImportRules([
        fpNode('chrome', name: 'NL')
      ], [
        ImportRule(
          conditions: [cond('tag', ImportRuleOperator.contains, 'NL')],
          action: ImportRuleAction.disable,
          enabled: false,
        )
      ]);
      expect(res.isEmpty, isTrue);
    });

    test('правила применяются по порядку — следующее видит патч', () {
      final rules = [
        ImportRule(
          conditions: [cond('tag', ImportRuleOperator.contains, 'raw')],
          action: ImportRuleAction.replace,
          targetPath: 'tag',
          replacement: 'stage1',
        ),
        ImportRule(
          conditions: [cond('tag', ImportRuleOperator.contains, 'stage1')],
          action: ImportRuleAction.replace,
          targetPath: 'tag',
          replacement: 'stage2',
        ),
      ];
      final out = applyRulesToNode(fpNode('chrome', name: 'raw'), rules);
      expect(readJsonPath(out.patchedJson!, 'tag'), 'stage2');
    });
  });

  group('§332 Enable', () {


    final matchAll = cond('', ImportRuleOperator.matches, '.*');

    test('enable даёт disabled=false, узел «затронут»', () {
      final rule = ImportRule(
        conditions: [cond('tag', ImportRuleOperator.contains, 'NL')],
        action: ImportRuleAction.enable,
      );
      final out = applyRulesToNode(fpNode('chrome', name: 'NL'), [rule]);
      expect(out.disabled, isFalse);
      expect(out.changed, isTrue);
      expect(
          applyRulesToNode(fpNode('chrome', name: 'DE'), [rule]).disabled,
          isNull);
    });

    test('последнее сработавшее правило побеждает: enable-all → disable FI',
        () {

      final rules = [
        ImportRule(conditions: [matchAll], action: ImportRuleAction.enable),
        ImportRule(
          conditions: [cond('tag', ImportRuleOperator.contains, 'FI')],
          action: ImportRuleAction.disable,
        ),
      ];
      expect(applyRulesToNode(fpNode('chrome', name: 'FI-1'), rules).disabled,
          isTrue);
      expect(applyRulesToNode(fpNode('chrome', name: 'NL-1'), rules).disabled,
          isFalse, reason: 'enable-all снял бы старую отметку');
    });

    test('whitelist: disable-all → enable NL', () {
      final rules = [
        ImportRule(conditions: [matchAll], action: ImportRuleAction.disable),
        ImportRule(
          conditions: [cond('tag', ImportRuleOperator.contains, 'NL')],
          action: ImportRuleAction.enable,
        ),
      ];
      expect(applyRulesToNode(fpNode('chrome', name: 'NL-1'), rules).disabled,
          isFalse);
      expect(applyRulesToNode(fpNode('chrome', name: 'DE-1'), rules).disabled,
          isTrue);
    });

    test('applyImportRules разводит индексы по наборам', () {
      final nodes = [
        fpNode('chrome', name: 'NL-1'),
        fpNode('chrome', name: 'FI-1'),
      ];
      final rules = [
        ImportRule(conditions: [matchAll], action: ImportRuleAction.enable),
        ImportRule(
          conditions: [cond('tag', ImportRuleOperator.contains, 'FI')],
          action: ImportRuleAction.disable,
        ),
      ];
      final res = applyImportRules(nodes, rules);
      expect(res.enabledIndexes, {0});
      expect(res.disabledIndexes, {1});
    });

    test('сериализация: enable переживает round-trip', () {
      final rule = ImportRule(
        conditions: [cond('tag', ImportRuleOperator.contains, 'NL')],
        action: ImportRuleAction.enable,
      );
      expect(ImportRule.fromJson(rule.toJson()), rule);
      expect(ImportRuleAction.fromName('enable'), ImportRuleAction.enable);
    });

    test('summary показывает Enable', () {
      final rule = ImportRule(
        conditions: [cond('tag', ImportRuleOperator.contains, 'NL')],
        action: ImportRuleAction.enable,
      );
      expect(rule.summary, endsWith('→ Enable'));
    });
  });

  group('сериализация', () {
    test('round-trip нового формата', () {
      final rule = ImportRule(
        conditions: [
          cond('tls.utls.fingerprint', ImportRuleOperator.matches,
              r'^hello(.*)$'),
          cond('tag', ImportRuleOperator.contains, 'NL', negate: true),
        ],
        matchMode: ImportRuleMatchMode.any,
        action: ImportRuleAction.replace,
        targetPath: 'tls.utls.fingerprint',
        replacement: r'$1',
        replaceMode: ImportRuleReplaceMode.substitute,
        substitutePattern: 'hello',
        enabled: false,
      );
      expect(ImportRule.fromJson(rule.toJson()), rule);
    });

    test('миграция старого плоского правила → условие по tag', () {

      final migrated = ImportRule.fromJson({
        'action': 'disable',
        'pattern': '⚡',
      });
      expect(migrated.conditions.single.path, 'tag');
      expect(migrated.conditions.single.op, ImportRuleOperator.contains);
      expect(migrated.conditions.single.pattern, '⚡');
      expect(migrated.action, ImportRuleAction.disable);

      expect(
          applyRulesToNode(fpNode('chrome', name: 'HU⚡Budapest'), [migrated])
              .disabled,
          isTrue);
    });

    test('миграция v1 replace несёт substitute-семантику', () {
      final migrated = ImportRule.fromJson({
        'action': 'replace',
        'pattern': 'hellochrome_120',
        'replacement': 'chrome',
      });
      expect(migrated.replaceMode, ImportRuleReplaceMode.substitute);
      expect(migrated.targetPath, 'tag');
    });
  });
}
