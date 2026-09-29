import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lxbox/screens/home/home_dialogs.dart';
import 'package:lxbox/services/install_source.dart';
import 'package:lxbox/services/project_links.dart';
import 'package:lxbox/services/settings_storage.dart';
import 'package:lxbox/services/update_checker.dart';









void main() {
  late Directory tmp;
  const ppChannel = MethodChannel('plugins.flutter.io/path_provider');
  const utilsChannel = MethodChannel('com.leadaxe.lxbox/utils');
  final calls = <MethodCall>[];

  const info = UpdateInfo(
    tag: 'v2.18.0',
    name: 'v2.18.0',
    htmlUrl: 'https://github.com/Leadaxe/LxBox/releases/tag/v2.18.0',
  );

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();



    WidgetController.hitTestWarningShouldBeFatal = true;
    tmp = await Directory.systemTemp.createTemp('lxbox_updatesnack_');
    calls.clear();
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(ppChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory' ||
          call.method == 'getApplicationDocumentsPath') {
        return tmp.path;
      }
      return null;
    });
    m.setMockMethodCallHandler(utilsChannel, (call) async {
      calls.add(call);
      return null;
    });
    SettingsStorage.resetCacheForTesting();
    InstallSourceResolver.resetForTest();


    UpdateChecker.I.latest.value = info;
  });

  tearDown(() async {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(ppChannel, null);
    m.setMockMethodCallHandler(utilsChannel, null);
    InstallSourceResolver.resetForTest();
    UpdateChecker.I.latest.value = null;
    try {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    } catch (_) {}
  });


  Future<int> pumpSnack(WidgetTester tester) async {
    var shown = 0;
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox.expand();
      })),
    ));

    await tester.runAsync(() async {
      await maybeShowUpdateSnackbar(ctx, info, onShown: () => shown++);
    });



    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    return shown;
  }

  MethodCall? lastOpenUrl() {
    final opens = calls.where((c) => c.method == 'openUrl').toList();
    return opens.isEmpty ? null : opens.last;
  }



  Future<void> tapAndPump(WidgetTester tester, Finder f) async {
    await tester.tap(f);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }



  Future<void> tapBody(WidgetTester tester) async {
    await tapAndPump(tester, find.textContaining('v2.18.0'));
    await tester.runAsync(() async {
      for (var i = 0; i < 50; i++) {
        if (calls.any((c) => c.method == 'openUrl')) return;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
  }

  Future<String> dismissedTag(WidgetTester tester) async {
    var out = '';
    await tester.runAsync(() async {
      out = await SettingsStorage.getDismissedUpdateVersion();
    });
    return out;
  }

  testWidgets('показывает обе кнопки', (tester) async {
    final shown = await pumpSnack(tester);
    expect(shown, 1);
    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Ignore'), findsOneWidget);

    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('«Later» не персистит — вернётся при следующем запуске',
      (tester) async {
    await pumpSnack(tester);
    await tapAndPump(tester, find.text('Later'));
    expect(await dismissedTag(tester), '');
    expect(lastOpenUrl(), isNull);
  });

  testWidgets('«Ignore» персистит тег — больше не покажем эту версию',
      (tester) async {
    await pumpSnack(tester);
    await tapAndPump(tester, find.text('Ignore'));


    await tester.runAsync(() async {
      for (var i = 0; i < 50; i++) {
        if (await SettingsStorage.getDismissedUpdateVersion() == 'v2.18.0') {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(await dismissedTag(tester), 'v2.18.0');
  });

  testWidgets('уже проигнорированную версию не показываем', (tester) async {
    await tester.runAsync(
        () => SettingsStorage.setDismissedUpdateVersion('v2.18.0'));
    final shown = await pumpSnack(tester);
    expect(shown, 0);
    expect(find.text('Later'), findsNothing);
  });

  testWidgets('клик по телу: переход в стор, но БЕЗ персиста (как Later)',
      (tester) async {
    InstallSourceResolver.setForTest(InstallSource.play);
    await pumpSnack(tester);
    await tapBody(tester);
    final call = lastOpenUrl();
    expect(call, isNotNull);
    expect(call!.arguments['url'], ProjectLinks.playPage);

    expect(call.arguments['fallbackUrl'], ProjectLinks.playPageWeb);

    expect(await dismissedTag(tester), '');
  });

  testWidgets('github-канал ведёт на страницу релиза', (tester) async {
    InstallSourceResolver.setForTest(InstallSource.github);
    await pumpSnack(tester);
    await tapBody(tester);
    final call = lastOpenUrl();
    expect(call!.arguments['url'], ProjectLinks.releaseTag('v2.18.0'));
    expect(call.arguments['fallbackUrl'], isNull);
  });

  testWidgets('f-droid ведёт на страницу пакета', (tester) async {
    InstallSourceResolver.setForTest(InstallSource.fdroid);
    await pumpSnack(tester);
    await tapBody(tester);
    expect(lastOpenUrl()!.arguments['url'], ProjectLinks.fdroidPage);
  });

  testWidgets('узкий экран: кнопки не обрезаются (уезжают под текст)',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpSnack(tester);
    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Ignore'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 7));
  });
}
