import 'package:flutter_test/flutter_test.dart';

import 'package:lxbox/models/custom_rule.dart';
import 'package:lxbox/screens/custom_rule_edit/edit_controller.dart';










void main() {


  TestWidgetsFlutterBinding.ensureInitialized();

  group('§381 snapshot() сохраняет orderNum', () {
    test('inline: номер переносится из initial', () {
      final ctrl = _controllerFor(
        CustomRuleInline(name: 'flibusta', orderNum: 1042, domains: ['a.ru']),
      );
      addTearDown(ctrl.dispose);

      expect(ctrl.snapshot().orderNum, 1042);
    });

    test('inline: правило без правок не грязное', () {
      final ctrl = _controllerFor(
        CustomRuleInline(name: 'flibusta', orderNum: 1042, domains: ['a.ru']),
      );
      addTearDown(ctrl.dispose);

      expect(ctrl.isDirty(), isFalse);
    });

    test('srs: номер переносится из initial', () {
      final ctrl = _controllerFor(
        CustomRuleSrs(
          name: 'geosite',
          orderNum: 1007,
          srsUrl: 'https://example.invalid/x.srs',
        ),
      );
      addTearDown(ctrl.dispose);

      expect(ctrl.snapshot().orderNum, 1007);
      expect(ctrl.isDirty(), isFalse);
    });

    test('json: номер переносится из initial', () {
      final ctrl = _controllerFor(
        CustomRuleJson(name: 'raw', orderNum: 1003, json: '{"outbound":"direct"}'),
      );
      addTearDown(ctrl.dispose);

      expect(ctrl.snapshot().orderNum, 1003);
      expect(ctrl.isDirty(), isFalse);
    });

    test('preset: номер переносится из initial', () {
      final ctrl = _controllerFor(
        CustomRulePreset(name: 'fcm-push', orderNum: 970, presetId: 'fcm-push'),
      );
      addTearDown(ctrl.dispose);

      expect(ctrl.snapshot().orderNum, 970);
      expect(ctrl.isDirty(), isFalse);
    });

    test('неразмеченное правило остаётся с null (разметку делает markRuleOrder)',
        () {
      final ctrl = _controllerFor(CustomRuleInline(name: 'fresh'));
      addTearDown(ctrl.dispose);

      expect(ctrl.snapshot().orderNum, isNull);
      expect(ctrl.isDirty(), isFalse);
    });
  });
}

CustomRuleEditController _controllerFor(CustomRule initial) =>
    CustomRuleEditController(
      initial: initial,
      preset: null,
      existingNames: const {},
    );
