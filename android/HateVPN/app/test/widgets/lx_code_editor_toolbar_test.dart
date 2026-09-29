import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/widgets/lx_code_editor.dart';
import 'package:re_editor/re_editor.dart';






















void main() {

  const text = 'alpha bravo charlie\nsecond line here\n';


  late List<String> copied;

  setUp(() {
    copied = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
        return null;
      }
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': 'PASTED'};
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<CodeLineEditingController> pumpEditor(WidgetTester tester) async {
    final controller = CodeLineEditingController.fromText(text);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 300,
          child: LxCodeEditor(controller: controller),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    return controller;
  }



  Future<void> longPressWord(WidgetTester tester) async {
    await tester.longPressAt(const Offset(40, 20));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Finder item(String label) => find.widgetWithText(TextButton, label);

  testWidgets('долгий тап: меню показано, выделение не схлопнуто',
      (tester) async {
    final controller = await pumpEditor(tester);
    await longPressWord(tester);

    expect(item('Copy'), findsOneWidget, reason: 'меню не показалось');
    expect(item('Cut'), findsOneWidget);
    expect(item('Paste'), findsOneWidget);
    expect(item('Select all'), findsOneWidget);

    expect(controller.selection.isCollapsed, isFalse,
        reason: 'показ меню схлопнул выделение — регрессия §517');
    expect(controller.selectedText, 'alpha');
  });

  testWidgets('тап Copy кладёт в буфер выделенный фрагмент', (tester) async {
    final controller = await pumpEditor(tester);
    await longPressWord(tester);
    expect(controller.selectedText, 'alpha');

    await tester.tap(item('Copy'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(copied, ['alpha'],
        reason: 'copy сработал по схлопнутому выделению — регрессия §517');

    expect(controller.selectedText, 'alpha');

    expect(item('Copy'), findsNothing);
  });

  testWidgets('тап Cut забирает выделенный фрагмент и вырезает его',
      (tester) async {
    final controller = await pumpEditor(tester);
    await longPressWord(tester);

    await tester.tap(item('Cut'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(copied, ['alpha'], reason: 'cut взял не выделенное');
    expect(controller.text, startsWith(' bravo charlie'),
        reason: 'из текста ушло ровно выделенное слово');
  });

  testWidgets('тап Select all выделяет весь текст', (tester) async {
    final controller = await pumpEditor(tester);
    await longPressWord(tester);

    await tester.tap(item('Select all'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.selection.isCollapsed, isFalse);
    expect(controller.selectedText, text);
  });

  testWidgets('тап Paste заменяет выделение содержимым буфера', (tester) async {
    final controller = await pumpEditor(tester);
    await longPressWord(tester);

    await tester.tap(item('Paste'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.text, startsWith('PASTED bravo charlie'),
        reason: 'paste подставился не на место выделения');
  });

  testWidgets('hide снимает оверлей (было: пустое тело метода)',
      (tester) async {
    await pumpEditor(tester);
    await longPressWord(tester);
    expect(item('Copy'), findsOneWidget);



    await tester.drag(find.byType(CodeEditor), const Offset(0, -40));
    await tester.pump(const Duration(milliseconds: 100));

    expect(item('Copy'), findsNothing,
        reason: 'оверлей остался на экране после hide');
  });

  testWidgets('повторный показ не плодит оверлеи', (tester) async {
    await pumpEditor(tester);
    await longPressWord(tester);
    expect(item('Copy'), findsOneWidget);






    await longPressWord(tester);
    expect(item('Copy').evaluate().length, lessThanOrEqualTo(1),
        reason: 'на экране больше одного меню — оверлей утёк');

    await longPressWord(tester);
    expect(item('Copy').evaluate().length, lessThanOrEqualTo(1),
        reason: 'на экране больше одного меню — оверлей утёк');
  });



























  testWidgets('§521 тап по пустому месту рядом с редактором снимает меню',
      (tester) async {




















    final controller = CodeLineEditingController.fromText(text);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Color(0xFFEEEEEE))),
            Positioned(
              left: 0,
              top: 0,
              child: SizedBox(
                width: 400,
                height: 200,
                child: LxCodeEditor(controller: controller),
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    await longPressWord(tester);
    expect(item('Copy'), findsOneWidget, reason: 'меню не показалось');


    await tester.tapAt(const Offset(200, 400));
    await tester.pump(const Duration(milliseconds: 200));

    expect(item('Copy'), findsNothing,
        reason: 'меню осталось висеть после тапа вне редактора');
  });

  testWidgets('§521 тап по пустому месту внутри редактора: выделение снято '
      'и меню скрыто', (tester) async {




    final controller = await pumpEditor(tester);
    await longPressWord(tester);
    expect(item('Copy'), findsOneWidget);

    await tester.tapAt(const Offset(200, 250));
    await tester.pump(const Duration(milliseconds: 200));

    expect(controller.selection.isCollapsed, isTrue,
        reason: 'тап по пустому месту не снял выделение');
    expect(item('Copy'), findsNothing, reason: 'меню осталось висеть');
  });

  testWidgets('§521 два долгих тапа в разных местах: ровно одно меню',
      (tester) async {
    final controller = await pumpEditor(tester);


    await tester.longPressAt(const Offset(120, 20));
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.selectedText, 'bravo');
    expect(item('Copy'), findsOneWidget);






    await tester.pump(const Duration(milliseconds: 700));
    await tester.longPressAt(const Offset(40, 36));
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.selectedText, 'second',
        reason: 'второй долгий тап не выделил слово на второй строке');

    expect(item('Copy').evaluate().length, 1,
        reason: 'на экране не ровно одно меню — оверлей утёк');
    expect(item('Select all').evaluate().length, 1);
  });

  testWidgets(
      '§521 подмена экземпляра контроллера меню на живом редакторе '
      'не оставляет висячий оверлей', (tester) async {

















    final controller = CodeLineEditingController.fromText(text);
    addTearDown(controller.dispose);
    final first = LxSelectionToolbarController();
    final second = LxSelectionToolbarController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    late StateSetter setOuter;
    var useSecond = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          setOuter = setState;
          return SizedBox(
            width: 400,
            height: 300,
            child: CodeEditor(
              controller: controller,
              toolbarController: useSecond ? second : first,
            ),
          );
        }),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.longPressAt(const Offset(40, 20));
    await tester.pump(const Duration(milliseconds: 400));
    expect(item('Copy'), findsOneWidget);
    expect(first.isShown, isTrue);


    setOuter(() => useSecond = true);
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.longPressAt(const Offset(120, 20));
    await tester.pump(const Duration(milliseconds: 400));



    expect(item('Copy').evaluate().length, 2,
        reason: 'репродукция сломалась: подмена экземпляра больше не течёт, '
            'значит тест ниже проверяет не то');
    expect(first.isShown && second.isShown, isTrue);




  });

  testWidgets('§521 setState родителя при открытом меню не плодит оверлеи',
      (tester) async {




    final controller = CodeLineEditingController.fromText(text);
    addTearDown(controller.dispose);
    late StateSetter setOuter;
    var bump = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          setOuter = setState;
          return SizedBox(
            width: 400,
            height: 300,

            child: LxCodeEditor(controller: controller, hint: 'hint $bump'),
          );
        }),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.longPressAt(const Offset(40, 20));
    await tester.pump(const Duration(milliseconds: 400));
    expect(item('Copy'), findsOneWidget);

    for (var i = 0; i < 3; i++) {
      setOuter(() => bump++);
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.longPressAt(Offset(40 + 40.0 * i, 36));
      await tester.pump(const Duration(milliseconds: 400));
      expect(item('Copy').evaluate().length, lessThanOrEqualTo(1),
          reason: 'после setState родителя меню размножились — дефект §521');
    }
  });

  testWidgets('§521 скролл при открытом меню прячет меню', (tester) async {
    await pumpEditor(tester);
    await longPressWord(tester);
    expect(item('Copy'), findsOneWidget);



    await tester.drag(find.byType(CodeEditor), const Offset(0, -40));
    await tester.pump(const Duration(milliseconds: 100));

    expect(item('Copy'), findsNothing, reason: 'меню уехало вместе со скроллом');
  });

  testWidgets('§521 уход с экрана при открытом меню: без исключений',
      (tester) async {
    final controller = CodeLineEditingController.fromText(text);
    addTearDown(controller.dispose);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => Scaffold(
                body: SizedBox(
                  width: 400,
                  height: 300,
                  child: LxCodeEditor(controller: controller),
                ),
              ),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));


    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(CodeEditor), findsOneWidget,
        reason: 'маршрут с редактором не открылся');




    final origin = tester.getTopLeft(find.byType(CodeEditor));
    await tester.longPressAt(origin + const Offset(40, 20));
    await tester.pump(const Duration(milliseconds: 400));
    expect(item('Copy'), findsOneWidget, reason: 'меню не показалось');




    nav.currentState!.pop();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull,
        reason: 'исключение при снятии OverlayEntry на уходе с экрана');
    expect(item('Copy'), findsNothing,
        reason: 'меню осталось поверх предыдущего экрана');
  });
}
