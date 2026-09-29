import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/server_list.dart';
import 'package:lxbox/services/subscription/auto_updater.dart';







SubscriptionServers _sub(SubscriptionOnUpdateAction action) =>
    SubscriptionServers(
      id: 'x',
      name: 'x',
      enabled: true,
      tagPrefix: '',
      detourPolicy: DetourPolicy.defaults,
      url: 'https://example.com/sub',
      onUpdateAction: action,
    );


bool _shouldAutoReload({
  required bool autoReload,
  required bool tunnelUp,
  required bool needRestart,
  required bool rebuildOk,
  bool canReload = true,
}) {
  if (!rebuildOk) return false;
  if (!autoReload) return false;
  if (!tunnelUp) return false;
  if (!needRestart) return false;


  if (!canReload) return false;
  return true;
}

void main() {
  group('§338 effectiveOnUpdateAction — перекрытие per-subscription выбора', () {
    test('галка вкл → reload при ЛЮБОМ сохранённом значении', () {
      for (final a in SubscriptionOnUpdateAction.values) {
        expect(
          AutoUpdater.effectiveOnUpdateAction(_sub(a), autoReload: true),
          SubscriptionOnUpdateAction.reload,
          reason: 'сохранённое $a должно быть перекрыто',
        );
      }
    });

    test('галка выкл → значение поля подписки', () {
      for (final a in SubscriptionOnUpdateAction.values) {
        expect(
          AutoUpdater.effectiveOnUpdateAction(_sub(a), autoReload: false),
          a,
        );
      }
    });

    test('перекрытие НЕ мутирует поле — выключение вернёт выбор юзера', () {
      final list = _sub(SubscriptionOnUpdateAction.none);
      AutoUpdater.effectiveOnUpdateAction(list, autoReload: true);
      expect(list.onUpdateAction, SubscriptionOnUpdateAction.none);
      expect(
        AutoUpdater.effectiveOnUpdateAction(list, autoReload: false),
        SubscriptionOnUpdateAction.none,
      );
    });
  });

  group('§338 гейт автоперезапуска', () {
    test('все условия выполнены → reload', () {
      expect(
        _shouldAutoReload(
            autoReload: true,
            tunnelUp: true,
            needRestart: true,
            rebuildOk: true),
        isTrue,
      );
    });

    test('галка выкл → нет (дефолтное поведение сохранено)', () {
      expect(
        _shouldAutoReload(
            autoReload: false,
            tunnelUp: true,
            needRestart: true,
            rebuildOk: true),
        isFalse,
      );
    });

    test('туннель лежит → нет: «перезапуск» ≠ «запуск»', () {
      expect(
        _shouldAutoReload(
            autoReload: true,
            tunnelUp: false,
            needRestart: true,
            rebuildOk: true),
        isFalse,
      );
    });

    test('§324 вердикт fresh (needRestart=false) → нет: ядро уже на этом конфиге',
        () {
      expect(
        _shouldAutoReload(
            autoReload: true,
            tunnelUp: true,
            needRestart: false,
            rebuildOk: true),
        isFalse,
      );
    });

    test('пересборка не удалась → нет: на диске старый конфиг', () {
      expect(
        _shouldAutoReload(
            autoReload: true,
            tunnelUp: true,
            needRestart: true,
            rebuildOk: false),
        isFalse,
      );
    });

    test('cooldown (canReload=false) → скип, плашка остаётся fallback\'ом', () {
      expect(
        _shouldAutoReload(
            autoReload: true,
            tunnelUp: true,
            needRestart: true,
            rebuildOk: true,
            canReload: false),
        isFalse,
      );
    });
  });
}
