import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/controllers/subscription_controller.dart';
import 'package:lxbox/screens/lazy_persist_mixin.dart';
import 'package:lxbox/services/settings_storage.dart';







class _Probe extends StatefulWidget {
  const _Probe({required this.controller, required this.onStage});
  final SubscriptionController controller;
  final VoidCallback onStage;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe>
    with WidgetsBindingObserver, LazyPersistMixin<_Probe> {
  @override
  SubscriptionController get lazyController => widget.controller;
  @override
  Future<void> stageChanges() async => widget.onStage();
  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  testWidgets('markDirty sets configDirty + pending sync, stage стартует',
      (tester) async {
    final ctrl = SubscriptionController();
    var staged = 0;
    await tester.pumpWidget(MaterialApp(
      home: _Probe(controller: ctrl, onStage: () => staged++),
    ));
    final state = tester.state<_ProbeState>(find.byType(_Probe));
    expect(state.hasPendingChanges, false);
    expect(ctrl.configDirty, false);

    state.markDirty();
    expect(state.hasPendingChanges, true);
    expect(ctrl.configDirty, true, reason: 'configDirty sync на markDirty');



    await tester.pump(const Duration(milliseconds: 20));
    expect(staged, 1, reason: '§107: буфер staged в момент мутации');
  });

  testWidgets('§107: каждая мутация re-stage\'ит буфер', (tester) async {
    final ctrl = SubscriptionController();
    var staged = 0;
    await tester.pumpWidget(MaterialApp(
      home: _Probe(controller: ctrl, onStage: () => staged++),
    ));
    final state = tester.state<_ProbeState>(find.byType(_Probe));
    state.markDirty();
    state.markDirty();
    await tester.pump();
    expect(staged, 2, reason: 'два markDirty → два stage');
  });





  testWidgets('flush on dispose когда pending (stage safety-net)',
      (tester) async {
    final ctrl = SubscriptionController();
    var staged = 0;
    await tester.pumpWidget(MaterialApp(
      home: _Probe(controller: ctrl, onStage: () => staged++),
    ));
    tester.state<_ProbeState>(find.byType(_Probe)).markDirty();


    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();



    expect(staged, 1, reason: 'stage только на markDirty, dispose лишь ждёт');
  });

  testWidgets('§338: dispose-flush НЕ переподнимает configDirty после rebuild',
      (tester) async {
    final ctrl = SubscriptionController();
    ctrl.configDirty = false;
    var staged = 0;
    await tester.pumpWidget(MaterialApp(
      home: _Probe(
          controller: ctrl,

          onStage: () {
            staged++;
            SettingsStorage.markConfigDirty();
          }),
    ));
    tester.state<_ProbeState>(find.byType(_Probe)).markDirty();
    await tester.pump(const Duration(milliseconds: 20));
    expect(ctrl.configDirty, true);



    ctrl.configDirty = false;



    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(milliseconds: 20));
    expect(ctrl.configDirty, false,
        reason: 'dispose-flush не должен трогать флаг — rebuild уже всё съел');
    expect(staged, 1);
  });

  testWidgets('НЕ flush на dispose если нет pending', (tester) async {
    final ctrl = SubscriptionController();
    var staged = 0;
    await tester.pumpWidget(MaterialApp(
      home: _Probe(controller: ctrl, onStage: () => staged++),
    ));

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    expect(staged, 0, reason: 'idempotent: clean exit без write');
  });

  testWidgets('flush на AppLifecycleState.paused', (tester) async {
    final ctrl = SubscriptionController();
    var staged = 0;
    await tester.pumpWidget(MaterialApp(
      home: _Probe(controller: ctrl, onStage: () => staged++),
    ));
    final state = tester.state<_ProbeState>(find.byType(_Probe));
    state.markDirty();


    await tester.pump(const Duration(milliseconds: 20));
    expect(staged, 1);
    state.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 20));

    expect(staged, 1, reason: 'flush на paused не re-stage\'ит');

    state.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 20));
    expect(staged, 1, reason: 'idempotent — второй paused не пишет');
  });
}
