import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/screens/app_picker_screen.dart';
import 'package:lxbox/services/app_info_cache.dart';
import 'package:lxbox/services/l10n/locale_controller.dart';





void main() {
  const channel = MethodChannel('com.leadaxe.lxbox/methods');

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    AppInfoCache.resetForTest();

    AppInfoCache.retryDelays = const [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAppIcon') return '';
      if (call.method == 'getInstalledApps') {
        return <dynamic>[
          {'packageName': 'com.a', 'appName': 'Alpha', 'isSystem': false},
          {'packageName': 'com.b', 'appName': 'Beta', 'isSystem': false},
        ];
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    AppInfoCache.resetForTest();
  });

  Widget host() => MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: LocaleController.supportedLocales,
        home: const AppPickerScreen(selected: {'com.a'}),
      );


  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  Checkbox checkboxOf(WidgetTester tester, String title) => tester.widget(
        find.descendant(
          of: find.ancestor(
              of: find.text(title), matching: find.byType(ListTile)),
          matching: find.byType(Checkbox),
        ),
      );

  testWidgets('тап по названию строки выбор не меняет (§412)', (tester) async {
    await tester.pumpWidget(host());
    await settle(tester);
    expect(checkboxOf(tester, 'Alpha').value, isTrue);
    expect(checkboxOf(tester, 'Beta').value, isFalse);

    await tester.tap(find.text('Alpha'));
    await tester.tap(find.text('com.b'));
    await settle(tester);

    expect(checkboxOf(tester, 'Alpha').value, isTrue,
        reason: 'строка не кликабельна — галочка на месте');
    expect(checkboxOf(tester, 'Beta').value, isFalse);
  });

  testWidgets('тап по чекбоксу переключает выбор (§412)', (tester) async {
    await tester.pumpWidget(host());
    await settle(tester);

    await tester.tap(find.descendant(
      of: find.ancestor(
          of: find.text('Beta'), matching: find.byType(ListTile)),
      matching: find.byType(Checkbox),
    ));
    await settle(tester);
    expect(checkboxOf(tester, 'Beta').value, isTrue);

    await tester.tap(find.descendant(
      of: find.ancestor(
          of: find.text('Alpha'), matching: find.byType(ListTile)),
      matching: find.byType(Checkbox),
    ));
    await settle(tester);
    expect(checkboxOf(tester, 'Alpha').value, isFalse);
  });
}
