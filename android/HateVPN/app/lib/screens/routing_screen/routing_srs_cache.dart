part of '../routing_screen.dart';




mixin _RoutingSrsCacheMixin on State<RoutingScreen>, LazyPersistMixin<RoutingScreen> {


  Set<String> get _srsCached;
  Set<String> get _srsDownloading;
  List<CustomRule> get _customRules;
  List<Direction> get _directions;
  void _invalidateOutboundOptions();
  set _template(WizardTemplate? value);
  Map<String, String> get _userVars;
  set _userVars(Map<String, String> value);
  String get _routeFinal;
  set _routeFinal(String value);
  set _loading(bool value);
  void _markDirty();
  SelectableRule? _presetFor(String presetId);
  List<PresetRemoteRuleSet> _remoteRuleSetsOf(
    SelectableRule preset, [
    CustomRulePreset? rule,
  ]);
  String _presetSrsKey(CustomRulePreset rule, String tag);
  bool _presetNeedsDownload(CustomRulePreset rule, SelectableRule preset);

  Future<void> _load() async {
    final template = await TemplateLoader.load();
    final storedFinal = await SettingsStorage.getRouteFinal();




    final stored = await SettingsStorage.getDirections();
    if (stored.isEmpty) {
      await SettingsStorage.migrateDirectionsIfNeeded(
        template.groupTemplates,
        varDefaults: {
          for (final v in template.vars) v.name: v.defaultValue,
        },
      );
      _directions.addAll(await SettingsStorage.getDirections());
    } else {
      _directions.addAll(stored);
    }
    _invalidateOutboundOptions();

    _routeFinal = storedFinal.isNotEmpty ? storedFinal : 'vpn-1';

    await SettingsStorage.seedLateDefaultPresets(template);
    _customRules.addAll(await SettingsStorage.getCustomRules());





    _template = template;

    await _seedDefaultPresets(template);





    final stripped =
        stripRefVarsFromVarsValues(_customRules, template.selectableRules);
    final strippedChanged = !identical(stripped, _customRules);














    final needsMarking = stripped.any((r) => r.orderNum == null) ||
        requiredRuleNumsShifted(stripped, template.selectableRules);
    final normalized =
        normalizeRuleOrder(stripped, template.selectableRules, template);
    final orderChanged =
        needsMarking || !_sameRuleOrder(normalized, _customRules);
    if (strippedChanged || orderChanged) {
      _customRules
        ..clear()
        ..addAll(normalized);
      await SettingsStorage.saveCustomRules(_customRules);
    }

    await _refreshSrsCache();

    setState(() {
      _loading = false;
    });
  }



  @override
  Future<void> stageChanges() async {
    await DirectionMutations.bulkReplace(_directions, flush: false);
    await SettingsStorage.saveRouteFinal(_routeFinal, flush: false);
    await SettingsStorage.saveCustomRules(_customRules, flush: false);


  }















  Future<void> _refreshSrsCache() async {


    _userVars = await SettingsStorage.getAllVars();
    _srsCached.clear();
    var changed = false;




    final activeDiskIds = <String>{};
    for (var i = 0; i < _customRules.length; i++) {
      final r = _customRules[i];
      if (r is CustomRuleSrs) {


        activeDiskIds.add(r.id);

        activeDiskIds.addAll(r.cacheIds);
        var cached = r.cacheIds.isNotEmpty;
        for (final cacheId in r.cacheIds) {
          if (!await RuleSetDownloader.isCached(cacheId)) cached = false;
        }
        if (cached) _srsCached.add(r.id);
        if (!cached && r.enabled) {
          _customRules[i] = r.withEnabled(false);
          changed = true;
        }
      } else if (r is CustomRulePreset) {
        final preset = _presetFor(r.presetId);
        if (preset == null) continue;



        final plan = RoutingHelpers.presetCachePlan(r, preset,
            globalVars: _userVars);
        activeDiskIds.addAll(plan.keepCacheIds);
        final remotes = plan.required;
        var allCached = true;
        for (final rs in remotes) {
          final cached = await RuleSetDownloader.cachedPathForPreset(
                  r.presetId, rs.tag) !=
              null;
          if (cached) {
            _srsCached.add(_presetSrsKey(r, rs.tag));
          } else {
            allCached = false;
          }
        }
        if (remotes.isNotEmpty && !allCached && r.enabled) {
          _customRules[i] = r.withEnabled(false);
          changed = true;
        }
      }
    }


    unawaited(RuleSetDownloader.pruneOrphans(activeDiskIds));
    if (changed) _markDirty();
  }




  bool _sameRuleOrder(List<CustomRule> a, List<CustomRule> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }






  Future<void> _seedDefaultPresets(WizardTemplate template) async {
    if (await SettingsStorage.hasDefaultsSeeded()) return;

    for (final sr in template.selectableRules) {
      if (!sr.defaultEnabled) continue;
      _customRules.add(selectableRuleToCustom(sr, template));
    }

    await SettingsStorage.saveCustomRules(_customRules);
    await SettingsStorage.markDefaultsSeeded();
  }




  Future<void> _enableAfterDownload(CustomRule rule) async {
    await _downloadSrs(rule);
    if (!mounted) return;

    bool ok;
    if (rule is CustomRuleSrs) {
      ok = _srsCached.contains(rule.id);
    } else if (rule is CustomRulePreset) {
      final preset = _presetFor(rule.presetId);
      ok = preset != null && !_presetNeedsDownload(rule, preset);
    } else {
      ok = true;
    }
    if (!ok) return;
    final i = _customRules.indexWhere((r) => r.id == rule.id);
    if (i < 0) return;
    setState(() {
      _customRules[i] = _customRules[i].withEnabled(true);
      _markDirty();
    });
  }

  Future<void> _downloadSrs(CustomRule rule) async {
    if (rule is CustomRuleSrs) {
      await _downloadSrsForSrsRule(rule);
      return;
    }
    if (rule is CustomRulePreset) {
      await _downloadSrsForPresetRule(rule);
      return;
    }
  }

  Future<void> _downloadSrsForSrsRule(CustomRuleSrs rule) async {
    if (rule.srsUrl.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(getLocalText.s("SRS URL is empty"))),
      );
      return;
    }
    setState(() => _srsDownloading.add(rule.id));

    String? path;
    for (var i = 0; i < rule.srsUrls.length; i++) {
      path = await RuleSetDownloader.download(
          CustomRuleSrs.cacheIdAt(rule.id, i), rule.srsUrls[i]);
      if (path == null) break;
    }
    if (!mounted) return;
    setState(() {
      _srsDownloading.remove(rule.id);
      if (path != null) _srsCached.add(rule.id);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(path != null
            ? getLocalText.s("Downloaded \"%s\"", rule.name)
            : getLocalText.s("Failed to download \"%s\" — check URL/network", rule.name)),
      ),
    );
    if (path != null) _markDirty();
  }




  Future<void> _downloadSrsForPresetRule(CustomRulePreset rule) async {
    final preset = _presetFor(rule.presetId);
    if (preset == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(getLocalText.s("Preset \"%s\" not found", rule.presetId))),
      );
      return;
    }

    final remotes = _remoteRuleSetsOf(preset, rule);
    if (remotes.isEmpty) return;
    setState(() => _srsDownloading.add(rule.id));
    var ok = 0;
    var failed = 0;
    for (final rs in remotes) {
      final path = await RuleSetDownloader.downloadForPreset(
          rule.presetId, rs.tag, rs.url);
      if (!mounted) return;
      if (path != null) {
        _srsCached.add(_presetSrsKey(rule, rs.tag));
        ok++;
      } else {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() => _srsDownloading.remove(rule.id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(failed == 0
            ? getLocalText.plural("Downloaded \"%2\$s\" (%1\$d rule-sets)", ok, rule.name)
            : getLocalText.s("Partial: %1\$d ok, %2\$d failed for \"%3\$s\"", ok, failed, rule.name)),
      ),
    );
    if (ok > 0) _markDirty();
  }
}
