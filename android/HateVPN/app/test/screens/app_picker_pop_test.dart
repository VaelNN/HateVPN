import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/screens/app_picker_screen.dart';
import 'package:lxbox/services/l10n/locale_controller.dart';






void main() {
  const channel = MethodChannel('com.leadaxe.lxbox/methods');

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getInstalledApps') return <dynamic>[];
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget host(void Function(AppPickerResult?) onResult) {
    return MaterialApp(
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: LocaleController.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final r = await Navigator.push<AppPickerResult>(
              context,
              MaterialPageRoute(
                builder: (_) => const AppPickerScreen(selected: {'com.a'}),
              ),
            );
            onResult(r);
          },
          child: const Text('open'),
        ),
      ),
    );
  }

  testWidgets('системный back возвращает текущий выбор (§108)',
      (tester) async {
    AppPickerResult? result;
    var popped = false;
    await tester.pumpWidget(host((r) {
      result = r;
      popped = true;
    }));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();


    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(navigator.maybePop());
    await tester.pumpAndSettle();

    expect(popped, isTrue, reason: 'picker должен попаться');
    expect(result, isNotNull, reason: '§108: back не должен терять выбор');
    expect(result!.packages, ['com.a']);
  });

  testWidgets('стрелка в AppBar возвращает выбор (поведение не изменилось)',
      (tester) async {
    AppPickerResult? result;
    await tester.pumpWidget(host((r) => result = r));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.packages, ['com.a']);
  });
}
