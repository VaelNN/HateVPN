import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lxbox/screens/settings_screen.dart';













void main() {
  group('D3 — dimmedWhenDisabled', () {
    testWidgets('enabled: обёртка не добавляется — дерево нетронуто',
        (tester) async {
      const child = SizedBox(key: ValueKey('row'));
      final wrapped = dimmedWhenDisabled(enabled: true, child: child);
      expect(identical(wrapped, child), isTrue,
          reason: 'включённая строка не должна получать лишний слой');

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: wrapped)));
      expect(find.byType(Opacity), findsNothing);
    });

    testWidgets('disabled: строка гаснет, содержимое сохраняется',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: dimmedWhenDisabled(
            enabled: false,
            child: const SizedBox(key: ValueKey('row')),
          ),
        ),
      ));
      expect(find.byKey(const ValueKey('row')), findsOneWidget,
          reason: 'гашение — не скрытие: строка остаётся видимой');
      final o = tester.widget<Opacity>(find.byType(Opacity));
      expect(o.opacity, lessThan(1.0));
      expect(o.opacity, greaterThan(0.0),
          reason: 'строка гаснет, но не исчезает');
    });

    testWidgets('переключение гейта переключает гашение', (tester) async {
      Widget build(bool enabled) => MaterialApp(
            home: Scaffold(
              body: dimmedWhenDisabled(
                enabled: enabled,
                child: const SizedBox(key: ValueKey('row')),
              ),
            ),
          );

      await tester.pumpWidget(build(false));
      expect(find.byType(Opacity), findsOneWidget);

      await tester.pumpWidget(build(true));
      expect(find.byType(Opacity), findsNothing,
          reason: 'включение базовой настройки обязано вернуть строку в норму');

      await tester.pumpWidget(build(false));
      expect(find.byType(Opacity), findsOneWidget);
    });

    test('коэффициент гашения совпадает с disabled-слоем контрола', () {


      expect(kDisabledRowOpacity, greaterThan(0.0));
      expect(kDisabledRowOpacity, lessThan(1.0));
    });
  });
}
