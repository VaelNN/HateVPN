import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../controllers/subscription_controller.dart';
import '../../models/server_list.dart';
import '../app_log.dart';
import '../settings_storage.dart';



enum UpdateTrigger {
  appStart,
  vpnConnected,
  periodic,
  vpnStopped,
  manual,
  resumed,
}



















class AutoUpdater {
  AutoUpdater(this._subController);
  final SubscriptionController _subController;










  Future<void> Function({required bool reload})? _onUpdateReaction;

  void bindOnUpdateReaction(Future<void> Function({required bool reload}) fn) {
    _onUpdateReaction = fn;
  }

  static const Duration minRetryInterval = Duration(minutes: 15);
  static const int maxFailsPerSession = 5;
  static const Duration perSubscriptionDelay = Duration(seconds: 10);
  static const Duration postVpnConnectedDelay = Duration(minutes: 2);
  static const Duration periodicInterval = Duration(hours: 1);

  Timer? _periodicTimer;
  Timer? _postVpnTimer;
  bool _running = false;






  bool _halted = false;


  @visibleForTesting
  bool get runningForTesting => _running;


  final Map<String, int> _failCounts = {};


  final Set<String> _inFlight = {};



  void start() {
    _periodicTimer ??= Timer.periodic(periodicInterval, (_) {
      unawaited(maybeUpdateAll(UpdateTrigger.periodic));
    });
    unawaited(maybeUpdateAll(UpdateTrigger.appStart));
  }



  void onVpnConnected() {
    _postVpnTimer?.cancel();
    _postVpnTimer = Timer(postVpnConnectedDelay, () {
      unawaited(maybeUpdateAll(UpdateTrigger.vpnConnected));
    });
  }


  void onVpnStopped() {
    _postVpnTimer?.cancel();
    unawaited(maybeUpdateAll(UpdateTrigger.vpnStopped));
  }

  void dispose() {
    _halted = true;
    _periodicTimer?.cancel();
    _postVpnTimer?.cancel();
    _periodicTimer = null;
    _postVpnTimer = null;
  }










  void halt() {
    _halted = true;
    _periodicTimer?.cancel();
    _postVpnTimer?.cancel();
    _periodicTimer = null;
    _postVpnTimer = null;
    if (_running) {
      AppLog.I.info('AutoUpdater: halt requested — run will stop');
    }
  }



  void resetFailCount(String url) => _failCounts.remove(url);


  void resetAllFailCounts() => _failCounts.clear();



  Future<void> maybeUpdateAll(UpdateTrigger trigger,
      {bool force = false}) async {
    if (_running) {
      AppLog.I.debug('AutoUpdater: skip ${trigger.name} — already running');
      return;
    }



    if (_halted) {
      AppLog.I.debug('AutoUpdater: skip ${trigger.name} — halted');
      return;
    }



    if (trigger != UpdateTrigger.manual && !force) {
      final enabled = await SettingsStorage.getAutoUpdateSubs();
      if (!enabled) {
        AppLog.I.debug('AutoUpdater: skip ${trigger.name} — auto-update disabled');
        return;
      }
    }


    final updateDisabled = await SettingsStorage.getAutoUpdateDisabledSubs();


    final autoReload = await SettingsStorage.getAutoReloadOnChange();
    _running = true;
    AppLog.I.info('AutoUpdater: trigger=${trigger.name}${force ? ' force' : ''}');

    try {
      final candidates = <SubscriptionEntry>[];
      for (final entry in _subController.entries) {
        if (!_shouldUpdate(entry, force: force, updateDisabled: updateDisabled)) {
          continue;
        }
        candidates.add(entry);
      }
      if (candidates.isEmpty) {
        AppLog.I.debug('AutoUpdater: no candidates');
        return;
      }
      AppLog.I.info('AutoUpdater: ${candidates.length} to refresh');






      var needRebuild = false;
      var needReload = false;

      for (var i = 0; i < candidates.length; i++) {



        if (_halted) {
          AppLog.I.info('AutoUpdater: run halted after $i of '
              '${candidates.length} subscriptions');
          return;
        }
        final entry = candidates[i];
        final url = (entry.list as SubscriptionServers).url;
        if (_inFlight.contains(url)) continue;
        _inFlight.add(url);
        try {
          final compositionChanged =
              await _subController.refreshEntry(entry, trigger: trigger);
          final fresh = entry.list;
          if (fresh is SubscriptionServers &&
              fresh.lastUpdateStatus == UpdateStatus.ok) {
            _failCounts.remove(url);







            if (compositionChanged && fresh.enabled) {
              switch (effectiveOnUpdateAction(fresh, autoReload: autoReload)) {
                case SubscriptionOnUpdateAction.reload:
                  needReload = true;
                  needRebuild = true;
                case SubscriptionOnUpdateAction.rebuild:
                  needRebuild = true;
                case SubscriptionOnUpdateAction.none:
                  break;
              }
            }
          } else {
            _failCounts[url] = (_failCounts[url] ?? 0) + 1;
          }
        } catch (e) {
          _failCounts[url] = (_failCounts[url] ?? 0) + 1;
          AppLog.I.warning('AutoUpdater: ${entry.displayName} fail: $e');
        } finally {
          _inFlight.remove(url);
        }

        if (i < candidates.length - 1) {

          final jitter = Random().nextInt(4000) - 2000;
          await _sleepInterruptibly(
              perSubscriptionDelay + Duration(milliseconds: jitter));
        }
      }





      if (needRebuild) await applyReaction(reload: needReload);
    } finally {
      _running = false;
    }
  }





  static const Duration _sleepSlice = Duration(milliseconds: 250);

  Future<void> _sleepInterruptibly(Duration total) async {
    var left = total;
    while (left > Duration.zero && !_halted) {
      final slice = left < _sleepSlice ? left : _sleepSlice;
      await Future<void>.delayed(slice);
      left -= slice;
    }
  }








  Future<void> applyReaction({required bool reload}) async {
    final react = _onUpdateReaction;
    if (react == null) {
      AppLog.I.debug('AutoUpdater: no reaction bound — skip (acts as none)');
      return;
    }
    AppLog.I.info('AutoUpdater: reaction rebuild${reload ? ' + reload' : ''}');
    try {
      await react(reload: reload);
    } catch (e) {
      AppLog.I.warning('AutoUpdater: reaction failed: $e');
    }
  }








  static SubscriptionOnUpdateAction effectiveOnUpdateAction(
    SubscriptionServers list, {
    required bool autoReload,
  }) =>
      autoReload
          ? SubscriptionOnUpdateAction.reload
          : list.onUpdateAction;

  bool _shouldUpdate(SubscriptionEntry entry,
      {required bool force, bool updateDisabled = false}) {
    final list = entry.list;
    if (list is! SubscriptionServers) return false;
    return shouldUpdatePure(
      list: list,
      force: force,
      fails: _failCounts[list.url] ?? 0,
      now: DateTime.now(),
      updateDisabled: updateDisabled,
    );
  }




  static bool shouldUpdatePure({
    required SubscriptionServers list,
    required bool force,
    required int fails,
    required DateTime now,
    bool updateDisabled = false,
  }) {




    if (!list.enabled && !updateDisabled) return false;


    if (!force && fails >= maxFailsPerSession) return false;

    if (force) return true;




    if (list.updateIntervalHours <= 0) return false;



    final lastTry = list.lastUpdateAttempt;
    if (lastTry != null && now.difference(lastTry) < minRetryInterval) {
      return false;
    }


    final lastOk = list.lastUpdated;
    if (lastOk == null) return true;
    final interval = Duration(hours: list.updateIntervalHours);
    return now.difference(lastOk) >= interval;
  }
}
