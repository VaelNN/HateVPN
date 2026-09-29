import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lxbox/models/parser_config.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:lxbox/services/l10n/locale_controller.dart';
import 'package:lxbox/widgets/template_var_list.dart';
import 'package:lxbox/widgets/var_values_model.dart';











Future<VarValuesModel> _pump(
  WidgetTester tester, {
  required List<WizardVar> vars,
  required Map<String, String> initialValues,
  required void Function(String, String) onChanged,
}) async {
  final model = VarValuesModel({
    for (final v in vars) v.name: initialValues[v.name] ?? v.defaultValue,
  });
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: LocaleController.supportedLocales,
    home: Scaffold(
      body: TemplateVarListView(
        vars: vars,
        model: model,
        onChanged: onChanged,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return model;
}

void main() {
  group('§161 — self-repair при загрузке', () {
    testWidgets('пустое required с default → подставляется и персистится',
        (tester) async {
      final captured = <String, String>{};
      await _pump(
        tester,
        vars: [WizardVar(name: 'tol', type: 'int', defaultValue: '30')],
        initialValues: {'tol': ''},
        onChanged: (n, v) => captured[n] = v,
      );

      expect(captured['tol'], '30');
      expect(find.text('30'), findsOneWidget);
    });

    testWidgets('optional (required:false) пустое → НЕ чинится', (tester) async {
      final captured = <String, String>{};
      await _pump(
        tester,
        vars: [
          WizardVar(
              name: 'opt',
              type: 'text',
              defaultValue: 'fallback',
              required: false),
        ],
        initialValues: {'opt': ''},
        onChanged: (n, v) => captured[n] = v,
      );
      expect(captured.containsKey('opt'), false);
    });

    testWidgets('secret пустое → НЕ чинится (стёртый пароль не воскрешаем)',
        (tester) async {
      final captured = <String, String>{};
      await _pump(
        tester,
        vars: [WizardVar(name: 'pw', type: 'secret', defaultValue: 'seed')],
        initialValues: {'pw': ''},
        onChanged: (n, v) => captured[n] = v,
      );
      expect(captured.containsKey('pw'), false);
    });
  });

  group('§161 — нельзя сохранить пустое required', () {
    testWidgets('стираем required-поле → onChanged НЕ зовётся + errorText',
        (tester) async {
      final captured = <String, String>{};
      await _pump(
        tester,
        vars: [WizardVar(name: 'tol', type: 'int', defaultValue: '30')],
        initialValues: {'tol': '50'},
        onChanged: (n, v) => captured[n] = v,
      );
      captured.clear();

      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump();

      expect(captured.containsKey('tol'), false);

      expect(find.text('Required'), findsOneWidget);
    });

    testWidgets('ввод валидного значения после пустого → персистится + ошибка снята',
        (tester) async {
      final captured = <String, String>{};
      await _pump(
        tester,
        vars: [WizardVar(name: 'tol', type: 'int', defaultValue: '30')],
        initialValues: {'tol': '50'},
        onChanged: (n, v) => captured[n] = v,
      );
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump();
      expect(find.text('Required'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '40');
      await tester.pump();
      expect(captured['tol'], '40');
      expect(find.text('Required'), findsNothing);
    });
  });




  group('§232 — per-key подписка на VarValuesModel', () {
    testWidgets('внешний model.set обновляет enum-dropdown', (tester) async {
      final model = await _pump(
        tester,
        vars: [
          WizardVar(name: 'strategy', type: 'enum', defaultValue: 'prefer_ipv4',
              options: [
                WizardOption.fromAny('prefer_ipv4'),
                WizardOption.fromAny('prefer_ipv6'),
              ]),
        ],
        initialValues: {'strategy': 'prefer_ipv4'},
        onChanged: (_, _) {},
      );
      expect(find.text('prefer_ipv4'), findsOneWidget);

      model.set('strategy', 'prefer_ipv6');
      await tester.pump();
      expect(find.text('prefer_ipv6'), findsOneWidget);
      expect(model.dirtyKeys, contains('strategy'));
    });

    testWidgets('внешний model.set обновляет bool-switch', (tester) async {
      final model = await _pump(
        tester,
        vars: [WizardVar(name: 'flag', type: 'bool', defaultValue: 'false')],
        initialValues: {'flag': 'false'},
        onChanged: (_, _) {},
      );
      var sw = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(sw.value, isFalse);
      model.set('flag', 'true');
      await tester.pump();
      sw = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(sw.value, isTrue);
    });

    test('unstage/markDirty: пустое required не доезжает до dirty', () {
      final m = VarValuesModel({'tol': '30'});
      m.set('tol', '50');
      expect(m.dirtyKeys, {'tol'});

      m.set('tol', '', markDirty: false);
      m.unstage('tol');
      expect(m.get('tol'), '');
      expect(m.dirtyKeys, isEmpty);
    });
  });
}
