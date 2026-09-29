import 'dart:async';

import '../models/custom_rule.dart';
import '../models/parser_config.dart';
import '../models/preset_rule_set.dart';
import 'app_log.dart';
import 'rule_set_downloader.dart';
import 'settings_storage.dart';
import 'template_loader.dart';



enum RuleSetUpdateTrigger {

  appStart,


  vpnConnected,


  retry,
}


class _Candidate {
  const _Candidate({
    required this.cacheId,
    required this.url,
    required this.label,
    this.presetId,
    this.tag,
  });


  final String cacheId;
  final String url;


  final String label;

  final String? presetId;
  final String? tag;
}

























class RuleSetAutoUpdater {
  RuleSetAutoUpdater();


  static const Duration appStartDelay = Duration(seconds: 30);


  static const Duration postVpnConnectedDelay = Duration(seconds: 30);


  static const Duration retryDelay = Duration(seconds: 20);


  static const Duration perRuleSetDelay = Duration(seconds: 2);

  Timer? _timer;
  bool _running = false;



  bool _sessionDone = false;


  bool _foreground = true;





  Future<void> Function()? _onChanged;

  void bindOnChanged(Future<void> Function() fn) => _onChanged = fn;


  bool get sessionDone => _sessionDone;


  void start() => _schedule(RuleSetUpdateTrigger.appStart, appStartDelay);


  void onVpnConnected() =>
      _schedule(RuleSetUpdateTrigger.vpnConnected, postVpnConnectedDelay);


  void onAppPaused() {
    _foreground = false;
    _timer?.cancel();
    _timer = null;
  }

  void onAppResumed() => _foreground = true;

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  void _schedule(RuleSetUpdateTrigger trigger, Duration delay) {
    if (_sessionDone || _running || !_foreground) return;
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(_run(trigger)));
  }


  Future<void> _run(RuleSetUpdateTrigger trigger) async {
    if (_sessionDone || _running) return;


    if (!_foreground) return;
    _running = true;
    try {
      final candidates = await _collectCandidates();
      if (candidates.isEmpty) {

        _sessionDone = true;
        AppLog.I.debug('RuleSetAutoUpdater: ${trigger.name} — nothing stale');
        return;
      }
      AppLog.I.info(
          'RuleSetAutoUpdater: ${trigger.name} — ${candidates.length} stale');

      var failed = 0;
      var changed = false;
      for (var i = 0; i < candidates.length; i++) {


        if (!_foreground) {
          failed++;
          break;
        }
        final c = candidates[i];
        final res = await RuleSetDownloader.fetch(c.cacheId, c.url,
            conditional: true);
        switch (res.outcome) {
          case DownloadOutcome.downloaded:
            changed = true;
            AppLog.I.info('RuleSetAutoUpdater: updated ${c.label}');
          case DownloadOutcome.notModified:
            AppLog.I.debug('RuleSetAutoUpdater: ${c.label} up to date (304)');
          case DownloadOutcome.failed:
            failed++;
            AppLog.I.warning('RuleSetAutoUpdater: ${c.label} failed');
        }
        if (i < candidates.length - 1) {
          await Future<void>.delayed(perRuleSetDelay);
        }
      }

      if (changed) await _notifyChanged();

      if (failed == 0) {
        _sessionDone = true;
        AppLog.I.info('RuleSetAutoUpdater: pass complete — sleeping until restart');
      } else if (trigger != RuleSetUpdateTrigger.retry) {

        AppLog.I.info('RuleSetAutoUpdater: $failed failed — retry in 20s');
        _running = false;
        _schedule(RuleSetUpdateTrigger.retry, retryDelay);
        return;
      }
    } catch (e) {
      AppLog.I.warning('RuleSetAutoUpdater: pass error: $e');
    } finally {
      _running = false;
    }
  }


  Future<void> _notifyChanged() async {
    final fn = _onChanged;
    if (fn == null) {
      AppLog.I.debug('RuleSetAutoUpdater: no reaction bound — skip rebuild');
      return;
    }
    try {
      await fn();
    } catch (e) {
      AppLog.I.warning('RuleSetAutoUpdater: reaction failed: $e');
    }
  }




  Future<List<_Candidate>> _collectCandidates() async {
    final rules = await SettingsStorage.getCustomRules();
    final now = DateTime.now();
    final out = <_Candidate>[];

    WizardTemplate? template;


    Map<String, String>? userVars;
    for (final r in rules) {
      if (!r.enabled) continue;

      if (r is CustomRuleSrs) {


        for (var i = 0; i < r.srsUrls.length; i++) {
          final cacheId = CustomRuleSrs.cacheIdAt(r.id, i);
          final meta = await RuleSetDownloader.readMeta(cacheId);
          if (!shouldUpdatePure(
              meta: meta, intervalHours: r.updateIntervalHours, now: now)) {
            continue;
          }
          out.add(_Candidate(
            cacheId: cacheId,
            url: r.srsUrls[i],
            label: i == 0 ? r.name : '${r.name} #${i + 1}',
          ));
        }
        continue;
      }

      if (r is CustomRulePreset) {


        template ??= await TemplateLoader.load();
        userVars ??= await SettingsStorage.getAllVars();
        SelectableRule? preset;
        for (final sr in template.selectableRules) {
          if (sr.presetId == r.presetId) {
            preset = sr;
            break;
          }
        }
        if (preset == null) continue;



        for (final rs in remoteRuleSetsOfPreset(preset, r, userVars)) {
          final meta =
              await RuleSetDownloader.readMetaForPreset(r.presetId, rs.tag);
          if (!shouldUpdatePure(
              meta: meta,
              intervalHours: rs.updateIntervalHours,
              now: now)) {
            continue;
          }
          out.add(_Candidate(
            cacheId: RuleSetDownloader.presetCacheId(r.presetId, rs.tag),
            url: rs.url,
            label: '${r.name}/${rs.tag}',
            presetId: r.presetId,
            tag: rs.tag,
          ));
        }
      }
    }
    return out;
  }











  static bool shouldUpdatePure({
    required RuleSetMeta meta,
    required int intervalHours,
    required DateTime now,
  }) {
    if (intervalHours <= 0) return false;
    final last = meta.lastUpdated;
    if (last == null) return true;
    return now.difference(last) >= Duration(hours: intervalHours);
  }
}
