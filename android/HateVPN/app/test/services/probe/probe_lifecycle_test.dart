

import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/services/probe/probe_lifecycle.dart';


void main() {
  tearDown(() {

    ProbeLifecycle.I.haltAll();
  });

  test('register → isProbing; haltAll дёргает cancel и очищает', () {
    var cancelled = 0;
    ProbeLifecycle.I.register(() => cancelled++);
    expect(ProbeLifecycle.I.isProbing, isTrue);

    ProbeLifecycle.I.haltAll();

    expect(cancelled, 1);
    expect(ProbeLifecycle.I.isProbing, isFalse);
  });

  test('haltAll дёргает ВСЕ зарегистрированные отменители', () {
    var a = 0, b = 0;
    ProbeLifecycle.I.register(() => a++);
    ProbeLifecycle.I.register(() => b++);

    ProbeLifecycle.I.haltAll();

    expect(a, 1);
    expect(b, 1);
    expect(ProbeLifecycle.I.isProbing, isFalse);
  });

  test('deregister снимает отменитель — haltAll его не трогает', () {
    var cancelled = 0;
    final canceller = ProbeLifecycle.I.register(() => cancelled++);
    ProbeLifecycle.I.deregister(canceller);
    expect(ProbeLifecycle.I.isProbing, isFalse);

    ProbeLifecycle.I.haltAll();

    expect(cancelled, 0);
  });

  test('haltAll на пустом реестре — no-op (идемпотентно)', () {
    expect(ProbeLifecycle.I.isProbing, isFalse);
    ProbeLifecycle.I.haltAll();
    expect(ProbeLifecycle.I.isProbing, isFalse);
  });

  test('cancel, синхронно снимающий себя через deregister, не ломает обход', () {



    var cancelled = 0;
    late final void Function() self;
    self = () {
      cancelled++;
      ProbeLifecycle.I.deregister(self);
    };
    ProbeLifecycle.I.register(self);

    ProbeLifecycle.I.haltAll();

    expect(cancelled, 1);
    expect(ProbeLifecycle.I.isProbing, isFalse);
  });
}
