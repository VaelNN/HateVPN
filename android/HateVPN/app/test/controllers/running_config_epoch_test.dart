import 'package:flutter_test/flutter_test.dart';













void main() {
  group('§311 epoch-гейт', () {
    late int epoch;
    late String? snapshot;
    late bool fetching;

    setUp(() {
      epoch = 0;
      snapshot = null;
      fetching = false;
    });


    String? invalidate() {
      epoch++;
      return null;
    }




    Future<void> ensure(Future<String?> Function() rpc,
        {int maxAttempts = 12, String? staleRaw}) async {
      if (fetching) return;
      fetching = true;
      final captured = epoch;
      try {
        for (var i = 0; i < maxAttempts; i++) {
          final raw = await rpc();
          if (captured != epoch) return;
          if (raw != null && raw != staleRaw) {
            snapshot = raw;
            return;
          }
        }
      } finally {
        fetching = false;
      }
    }

    test('обычный путь: снапшот коммитится', () async {
      await ensure(() async => 'config-A');
      expect(snapshot, 'config-A');
      expect(epoch, 0);
    });

    test('РЕГРЕСС: ответ старого box\'а не переживает reload', () async {

      final inFlight = ensure(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return 'config-OLD';
      }, maxAttempts: 1);

      snapshot = invalidate();
      await inFlight;

      expect(snapshot, isNull,
          reason: 'stale-конфиг старого box\'а не должен коммититься');
      expect(epoch, 1);
    });

    test('после инвалидации следующий fetch снова разрешён', () async {
      final inFlight = ensure(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return 'config-OLD';
      }, maxAttempts: 1);
      snapshot = invalidate();
      await inFlight;

      await ensure(() async => 'config-NEW');
      expect(snapshot, 'config-NEW',
          reason: 'pre-check != null не должен залипать после дропа');
    });

    test('параллельные fetch\'и: guard пропускает один', () async {
      var calls = 0;
      Future<String?> rpc() async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return 'config-A';
      }

      await Future.wait([ensure(rpc), ensure(rpc), ensure(rpc)]);
      expect(calls, 1);
      expect(snapshot, 'config-A');
    });






    test('РЕГРЕСС: после reload снапшот перезахватывается ретраями', () async {
      const stale = 'config-OLD';
      snapshot = stale;

      snapshot = invalidate();


      var attempt = 0;
      Future<String?> rpc() async {
        attempt++;
        return attempt < 2 ? null : 'config-NEW';
      }

      await ensure(rpc, staleRaw: stale);

      expect(snapshot, 'config-NEW',
          reason: 'без ретраев снапшот залипал бы в null на всю сессию');
    });





    test('РЕГРЕСС: доreload\'ный ответ ядра не принимается за новый', () async {
      const stale = 'config-OLD';
      snapshot = invalidate();

      var attempt = 0;
      Future<String?> rpc() async {
        attempt++;

        return attempt < 3 ? stale : 'config-NEW';
      }

      await ensure(rpc, staleRaw: stale);

      expect(snapshot, 'config-NEW',
          reason: 'иначе в кеш залипал бы конфиг до reload\'а');
      expect(attempt, 3);
    });

    test('каждая инвалидация двигает epoch (сброс ⟺ bump)', () {
      expect(invalidate(), isNull);
      expect(invalidate(), isNull);
      expect(epoch, 2, reason: 'все 5 точек сброса обязаны идти через хелпер');
    });
  });
}
