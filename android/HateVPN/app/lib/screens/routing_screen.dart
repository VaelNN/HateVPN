import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io';

import 'package:file_picker/file_picker.dart' show FileType;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../controllers/home_controller.dart';
import '../controllers/subscription_controller.dart';
import '../models/direction.dart';
import '../models/custom_rule.dart';
import '../models/dns_ref.dart';
import '../models/parser_config.dart';
import '../services/builder/preset_expand.dart' show PresetNode;
import '../services/builder/rule_order.dart';
import '../services/direction_mutations.dart';
import '../services/error_format.dart';
import '../services/file_export.dart';
import '../services/file_import.dart';
import '../services/l10n/template_aware_state.dart';
import '../services/preset_nodes_view.dart';
import '../services/preset_on_change.dart';
import '../services/rule_display_names.dart';
import '../services/rule_set_downloader.dart';
import '../services/rule_transfer.dart';
import '../services/selectable_to_custom.dart';
import '../services/settings_storage.dart';
import '../services/template_loader.dart';
import '../services/ui_helpers.dart';
import '../services/url_launcher.dart';
import '../services/utf8_decode.dart';
import '../widgets/export_action_sheet.dart';
import '../widgets/outbound_picker.dart';
import 'direction_edit_screen.dart';
import 'custom_rule_edit_screen.dart';
import 'lazy_persist_mixin.dart';
import 'routing_screen/new_direction_dialog.dart';
import 'routing_screen/routing_screen_helpers.dart';
import 'routing_screen/routing_screen_menus.dart';
import 'routing_screen/rule_transfer_dialogs.dart';
import 'routing_screen/widgets/custom_rule_tile.dart';
import 'routing_screen/widgets/preset_catalog_tile.dart';
import 'routing_screen/widgets/route_final_tile.dart';
import 'routing_screen/widgets/routing_group_tile.dart';
import 'routing_screen/widgets/routing_tabs.dart';
import 'routing_screen/widgets/srs_status_button.dart';
import 'tun_apps_tab.dart';
import '../services/l10n/locale_controller.dart';

part 'routing_screen/routing_srs_cache.dart';

class RoutingScreen extends StatefulWidget {
  const RoutingScreen({
    super.key,
    required this.subController,
    required this.homeController,
    this.focusDirectionTag,
    this.initialPresetsTab = false,
  });

  final SubscriptionController subController;
  final HomeController homeController;



  final String? focusDirectionTag;



  final bool initialPresetsTab;

  @override
  State<RoutingScreen> createState() => _RoutingScreenState();
}

class _RoutingScreenState extends State<RoutingScreen>
    with
        WidgetsBindingObserver,
        LazyPersistMixin<RoutingScreen>,
        _RoutingSrsCacheMixin,
        TemplateAwareState<RoutingScreen>,
        SnackHelper<RoutingScreen> {
  @override
  WizardTemplate? _template;







  @override
  Map<String, String> _userVars = const {};
  @override
  final _directions = <Direction>[];



  List<RoutingOutboundOption>? _cachedOutboundOptions;
  @override
  String _routeFinal = '';
  @override
  final _customRules = <CustomRule>[];
  @override
  final _srsCached = <String>{};
  @override
  final _srsDownloading = <String>{};
  @override
  bool _loading = true;





  final _directionKeys = <String, GlobalKey>{};
  String? _highlightedDirectionTag;
  Timer? _directionHighlightTimer;

  @override
  SubscriptionController get lazyController => widget.subController;





  @override
  void onLocaleTemplateFetch({required bool first}) {
    if (first) {
      unawaited(_load().then((_) => _focusDirectionIfAny()));
    } else {
      unawaited(_refetchTemplate());
    }
  }

  Future<void> _refetchTemplate() async {
    final template = await TemplateLoader.load();
    if (!mounted) return;
    setState(() => _template = template);
  }

  @override
  void initState() {
    super.initState();


    widget.subController.addListener(_onSubControllerChanged);
  }

  @override
  void dispose() {
    widget.subController.removeListener(_onSubControllerChanged);
    _directionHighlightTimer?.cancel();
    super.dispose();
  }

  void _onSubControllerChanged() {
    if (!mounted || _loading) return;


    if (forEachNodeTypes(_template?.selectableRules ?? const []).isNotEmpty) {
      setState(() {});
    }
  }



  List<PresetNode> _presetViewNodes() => presetNodesForView(
        [for (final e in widget.subController.entries) e.list],
        nodeTypes: forEachNodeTypes(_template?.selectableRules ?? const []),
        lastEmittedTagMap: widget.subController.lastEmittedTagMap,
      );



  void _focusDirectionIfAny() {
    final tag = widget.focusDirectionTag;
    if (tag == null || !mounted) return;
    if (!_directions.any((c) => c.tag == tag)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _highlightedDirectionTag = tag);
      final ctx = _directionKeys[tag]?.currentContext;
      if (ctx != null) {
        unawaited(
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: 0.3,
          ),
        );
      }
      _directionHighlightTimer?.cancel();
      _directionHighlightTimer = Timer(const Duration(milliseconds: 2200), () {
        if (mounted) setState(() => _highlightedDirectionTag = null);
      });
    });
  }


  @override
  void _markDirty() => markDirty();


  @override
  List<PresetRemoteRuleSet> _remoteRuleSetsOf(
    SelectableRule preset, [
    CustomRulePreset? rule,
  ]) => RoutingHelpers.remoteRuleSetsOf(preset, rule, _userVars);


  @override
  String _presetSrsKey(CustomRulePreset rule, String tag) =>
      RoutingHelpers.presetSrsKey(rule, tag);


  @override
  bool _presetNeedsDownload(CustomRulePreset rule, SelectableRule preset) =>
      RoutingHelpers.presetNeedsDownload(rule, preset, _srsCached,
          globalVars: _userVars);


  @override
  void _invalidateOutboundOptions() => _cachedOutboundOptions = null;





  List<RoutingOutboundOption> _outboundOptions() =>
      _cachedOutboundOptions ??= RoutingHelpers.outboundOptions(_directions);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(getLocalText.s("Routing"))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final template = _template!;
    final bottomPad = MediaQuery.of(context).padding.bottom + 24;

    return DefaultTabController(
      length: 4,

      initialIndex: widget.initialPresetsTab ? 1 : 0,
      child: Builder(
        builder: (tabCtx) => Scaffold(
          appBar: AppBar(
            title: Text(getLocalText.s("Routing")),
            actions: [





              AnimatedBuilder(
                animation: DefaultTabController.of(tabCtx).animation!,
                builder: (_, _) {
                  final onRulesTab =
                      DefaultTabController.of(
                        tabCtx,
                      ).animation!.value.round() ==
                      2;
                  if (!onRulesTab) return const SizedBox.shrink();
                  return RulesMenuButton(




                  canExport: true,
                    onExport: _exportRules,
                    onImport: _importRules,
                  );
                },
              ),
            ],
            bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: getLocalText.s("Directions")),
                Tab(text: getLocalText.s("Presets")),
                Tab(text: getLocalText.s("Rules")),
                Tab(text: getLocalText.s("Tunnel apps")),
              ],
            ),
          ),
          body: TabBarView(
            children: [

              RoutingDirectionsTab(
                bottomPad: bottomPad,
                groupTiles: _directions.map(_buildDirectionTile).toList(),
                directionCount: _directions.length,


                onAddDirection: _addDirection,
                routeFinalTile: _buildRouteFinalTile(),
              ),


              RoutingPresetsTab(
                bottomPad: bottomPad,
                catalogTiles: template.selectableRules
                    .map(_buildPresetCatalogTile)
                    .toList(),
              ),


              RoutingRulesTab(
                bottomPad: bottomPad,
                itemCount: _customRules.length,
                onReorder: _onReorderCustomRule,
                itemKey: (i) => ValueKey(_customRules[i].id),
                itemBuilder: _buildCustomRuleTile,
                onAdd: _addCustomRule,
              ),


              TunAppsTab(
                homeController: widget.homeController,
                subController: widget.subController,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDirectionTile(Direction direction) {

    final cs = Theme.of(context).colorScheme;
    final highlighted = _highlightedDirectionTag == direction.tag;
    return AnimatedContainer(
      key: _directionKeys.putIfAbsent(direction.tag, GlobalKey.new),
      duration: const Duration(milliseconds: 200),
      decoration: highlighted
          ? BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.5),
              border: Border(left: BorderSide(color: cs.primary, width: 3)),
            )
          : null,
      child: RoutingDirectionTile(
        direction: direction,
        nodeCount: _nodeCountFor(direction),
        onToggle: (val) => unawaited(_toggleDirection(direction, val)),
        onTap: () => _editDirection(direction),
      ),
    );
  }






  Future<void> _toggleDirection(Direction direction, bool val) async {
    final next = direction.copyWith(enabled: val);
    final healed = await DirectionMutations.update(next, widget.subController);
    if (!mounted) return;
    await _resyncHealedRefs(healed);
    if (!mounted) return;
    setState(() {
      final i = _directions.indexWhere((c) => c.tag == direction.tag);
      if (i >= 0) _directions[i] = next;
      _invalidateOutboundOptions();
      _markDirty();
    });

    _notifyHealed(next, healed, ruleLead: getLocalText.s('disabled'));
  }








  Future<void> _resyncHealedRefs(DirectionHealResult healed) async {
    if (healed.rules == 0) return;
    final storedFinal = await SettingsStorage.getRouteFinal();
    _routeFinal = storedFinal.isNotEmpty ? storedFinal : 'vpn-1';
    _customRules
      ..clear()
      ..addAll(await SettingsStorage.getCustomRules());
  }





  void _notifyHealed(
    Direction direction,
    DirectionHealResult healed, {
    required String ruleLead,
  }) {
    if (healed.rules == 0 &&
        healed.detours == 0 &&
        healed.includes == 0 &&



        healed.chainPositions == 0 &&
        healed.dnsServers == 0) {
      return;
    }
    final label = direction.label.isNotEmpty ? direction.label : direction.tag;



    final lead = healed.rules > 0 ||
            healed.includes > 0 ||
            healed.chainPositions > 0 ||
            healed.dnsServers > 0
        ? getLocalText.s('Direction "%1\$s" %2\$s', label, ruleLead)
        : getLocalText.s('Direction "%s" is no longer a detour target', label);

    final parts = DirectionMutations.healMessageParts(healed);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$lead — ${parts.join(', ')}.')));
  }



  int _nodeCountFor(Direction direction) {
    final all = _allNodeTags();
    if (all.isEmpty) return -1;
    if (direction.nodeFilter.isEmpty) return all.length;
    try {

      final re = RegExp(direction.nodeFilter, caseSensitive: false);
      return all.where(re.hasMatch).length;
    } catch (_) {
      return all.length;
    }
  }



  List<String> _allNodeTags() {
    final groupTags = widget.homeController.state.ccGroups
        .map((g) => g.tag)
        .toSet();
    final seen = <String>{};
    final out = <String>[];
    for (final g in widget.homeController.state.ccGroups) {
      for (final item in g.items) {
        if (groupTags.contains(item.tag)) continue;
        if (seen.add(item.tag)) out.add(item.tag);
      }
    }
    return out;
  }

  Future<void> _addDirection() async {



    final req = await showNewDirectionDialog(
      context,
      existingTags: _directions.map((c) => c.tag).toList(),
    );
    if (req == null || !mounted) return;
    final Direction created;
    try {
      created = await DirectionMutations.add(
        tag: req.tag,
        label: req.label.isEmpty ? null : req.label,
      );
    } on StateError catch (e) {


      if (!mounted) return;
      showSnack(e.message);
      return;
    }
    if (!mounted) return;
    setState(() {
      _directions.add(created);
      _invalidateOutboundOptions();
    });
    _markDirty();
    _editDirection(created);
  }

  Future<void> _editDirection(Direction direction) async {



    final idx = _directions.indexWhere((c) => c.tag == direction.tag);
    final result = await openDirectionEditor(
      context,
      initial: direction,
      canDelete: !direction.isRequired,
      allNodeTags: _allNodeTags(),
      directionsAbove: idx <= 0 ? const [] : _directions.sublist(0, idx),

      foldCandidates: foldCandidatesOf([
        for (final e in widget.subController.entries)
          (name: e.displayName, replace: e.list.replace),
      ]),
    );
    if (result == null || !mounted) return;
    if (result.wasDeleted) {



      final healed = await DirectionMutations.delete(
        direction.tag,
        widget.subController,
      );
      if (!mounted) return;
      await _resyncHealedRefs(healed);
      if (!mounted) return;
      setState(() {
        _directions.removeWhere((c) => c.tag == direction.tag);




        if (healed.includes > 0) {
          final r = clearIncludeDirectionRefs(_directions, direction.tag);
          _directions
            ..clear()
            ..addAll(r.healed);
        }
        _invalidateOutboundOptions();
      });
      _markDirty();
      _notifyHealed(direction, healed, ruleLead: getLocalText.s('deleted'));
    } else if (result.saved != null) {
      final saved = result.saved!;



      final healed = await DirectionMutations.update(saved, widget.subController);
      if (!mounted) return;
      await _resyncHealedRefs(healed);
      if (!mounted) return;
      setState(() {
        final i = _directions.indexWhere((c) => c.tag == direction.tag);
        if (i >= 0) _directions[i] = saved;
        _invalidateOutboundOptions();
      });
      _markDirty();




      _notifyHealed(saved, healed, ruleLead: getLocalText.s('disabled'));
    }



    await DirectionMutations.bulkReplace(_directions, flush: true);
    await widget.homeController.refreshDirectionLabels();
  }




  Widget _buildPresetCatalogTile(SelectableRule rule) {
    final template = _template!;









    final existing =
        rule.presetId.isNotEmpty &&
        _customRules.any((c) => c.presetId == rule.presetId);
    return PresetCatalogTile(
      rule: rule,
      existing: existing,
      onCopy: () => _copyPreset(rule, template),
    );
  }

  void _copyPreset(SelectableRule rule, WizardTemplate template) {
    CustomRule cr = selectableRuleToCustom(rule, template);



    final needsSrs =
        cr is CustomRuleSrs ||
        (cr is CustomRulePreset && _remoteRuleSetsOf(rule, cr).isNotEmpty);
    if (needsSrs) cr = cr.withEnabled(false);



    cr.orderNum = rule.num;
    setState(() {
      _customRules.add(cr);
      final sorted = sortRulesByNum(_customRules);
      _customRules
        ..clear()
        ..addAll(sorted);
      _markDirty();
    });



    if (cr is CustomRulePreset) {
      unawaited(applyPresetOnChange(rule, cr));
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          needsSrs
              ? getLocalText.s(
                  "Added \"%s\" — tap ☁ to download, then enable",
                  rule.label,
                )
              : getLocalText.s("Added \"%s\" to Rules", rule.label),
        ),
      ),
    );
  }



  Future<void> _exportRules() async {
    final template = _template;
    if (template == null) return;



    final exportable = [
      for (final r in _customRules)
        if (r.kind != CustomRuleKind.preset) r,
    ];


    final dnsServers = [
      for (final s in await SettingsStorage.getDnsServers())
        if (s is! DnsServerPreset) s
    ];
    final dnsRules = [
      for (final r in await SettingsStorage.getDnsRulesList())
        if (r is DnsRuleInline || r is DnsRuleSrs) r
    ];
    if (!mounted) return;
    final selected = await showRuleExportPicker(
      context,
      rules: exportable,
      displayNames: ruleDisplayNames(exportable, _template),
      dnsServers: dnsServers,
      dnsRules: dnsRules,
      templateServerTags: {
        for (final s in template.dnsOptionsModel.servers) s.tag
      },
    );


    if (selected == null || !mounted) return;
    if (selected.rules.isEmpty &&
        selected.dnsServers.isEmpty &&
        selected.dnsRules.isEmpty) {
      return;
    }

    try {


      final availability = await Future.wait([
        UrlLauncher.hasRealFilePicker(),
        UrlLauncher.canSaveToDownloads(),
      ]);
      if (!mounted) return;
      final action = await showExportActionSheet(
        context,
        canSaveToFile: availability[0],
        canSaveToDownloads: availability[1],
      );
      if (action == null) return;

      String? appVersion;
      try {
        final info = await PackageInfo.fromPlatform();
        appVersion = '${info.version}+${info.buildNumber}';
      } catch (_) {

      }
      final json = buildRulesExport(
        selected.rules,
        appVersion: appVersion,
        dnsServers: selected.dnsServers,
        dnsRules: selected.dnsRules,
      );
      final filename = suggestedRulesFilename();


      final bytes = utf8.encode(json).length;

      final SaveOutcome outcome;
      switch (action) {
        case ExportAction.saveToFile:
          outcome = await saveFileSafely(fileName: filename, content: json);
        case ExportAction.saveToDownloads:
          outcome = await saveToDownloadsSafely(
            fileName: filename,
            content: json,
          );
        case ExportAction.share:


          final tmpDir = await getTemporaryDirectory();
          final path = '${tmpDir.path}/$filename';
          await File(path).writeAsString(json);
          await SharePlus.instance.share(ShareParams(
            files: [XFile(path, mimeType: 'application/json', name: filename)],
            subject: 'LxBox rules',
          ));
          showSnack(getLocalText.s("Rules exported"));
          return;
      }

      final problem = saveProblemText(outcome);
      if (problem != null) {
        showSnack(problem);
        return;
      }
      switch (outcome) {
        case SavedToFile(:final name):
          showSnack(getLocalText.s("Saved as %s (%d bytes)", name, bytes));
        case SavedToDownloads(:final name):
          showSnack(
            getLocalText.s("Saved to Downloads: %s (%d bytes)", name, bytes),
          );
        case SaveCancelled():
          break;
        case SaveNoTarget() || SaveFailed():
          break;
      }
    } catch (e) {
      showSnack(
        getLocalText.s("Export failed: %s", formatUserError(e).render()),
      );
    }
  }

  Future<void> _importRules() async {
    final template = _template;
    if (template == null) return;
    try {

      final outcome = await pickFileSafely(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (outcome is! PickedFiles) {
        final problem = pickProblemText(outcome);
        if (problem != null) showSnack(problem);
        return;
      }
      final file = outcome.single;
      final raw = utf8DecodeOrNull(file.bytes);
      if (raw == null) {
        showSnack(getLocalText.s("Could not read file."));
        return;
      }

      final RulesImportContents contents;
      try {
        contents = parseRulesImport(raw);
      } on FormatException catch (e) {
        showSnack(e.message);
        return;
      }




      final directionTags = {for (final c in _directions) c.tag};
      final existingServers = await SettingsStorage.getDnsServers();
      final existingServerTags = <String>{
        for (final s in existingServers)
          if (s.tag.isNotEmpty) s.tag,
      };
      final existingDnsRules = await SettingsStorage.getDnsRulesList();
      final templateServerTags = {
        for (final s in template.dnsOptionsModel.servers) s.tag,
      };


      final dnsServerItems = [
        for (final entry in contents.rawDnsServers)
          sanitizeImportedDnsServer(
            entry,
            existingTags: existingServerTags,
            templateServerTags: templateServerTags,
            format: contents.format,
          ),
      ];
      final dnsRuleItems = [
        for (final entry in contents.rawDnsRules)
          sanitizeImportedDnsRule(
            entry,
            existingRules: existingDnsRules,
            template: template,
            format: contents.format,
          ),
      ];



      final dnsServerTags = <String>{
        ...existingServerTags,
        ...templateServerTags,
        for (final it in dnsServerItems)
          if (it.item case final server?) server.tag,
      };




      final takenNames = visibleRuleNames(_customRules, template);
      final items = <SanitizedImportRule>[];
      for (final entry in contents.rawRules) {
        final item = sanitizeImportedRule(
          entry,
          directionTags: directionTags,
          dnsServerTags: dnsServerTags,
          template: template,
          existingNames: takenNames,
          format: contents.format,
        );
        if (item.importable) takenNames.add(item.rule!.name);
        items.add(item);
      }
      if (!mounted) return;
      final picked = await showRuleImportPreview(
        context,
        items: items,
        dnsServers: dnsServerItems,
        dnsRules: dnsRuleItems,
        createdAt: contents.createdAt,
        sourceAppVersion: contents.sourceAppVersion,
      );
      if (picked == null || !mounted) return;

      final inserted = <CustomRule>[];
      var needsSrs = false;
      for (final item in picked.rules) {
        final rule = item.rule;
        if (rule == null) continue;
        inserted.add(
          insertImportedRule(_customRules, rule, template: template),
        );
        needsSrs = needsSrs || item.needsSrsDownload;
      }
      final dnsCount = picked.dnsServers.length + picked.dnsRules.length;
      if (inserted.isEmpty && dnsCount == 0) return;



      if (picked.dnsServers.isNotEmpty) {
        await SettingsStorage.saveDnsServers(
            [...existingServers, ...picked.dnsServers]);
      }
      if (picked.dnsRules.isNotEmpty) {
        await SettingsStorage.saveDnsRulesList(
            [...existingDnsRules, ...picked.dnsRules]);
      }
      if (!mounted) return;

      if (inserted.isNotEmpty) {
        setState(() {
          final sorted = sortRulesByNum(_customRules);
          _customRules
            ..clear()
            ..addAll(sorted);
          _markDirty();
        });

        for (final cr in inserted) {
          if (cr is CustomRulePreset) {
            final preset = _presetFor(cr.presetId);
            if (preset != null) unawaited(applyPresetOnChange(preset, cr));
          }
        }
      }
      showSnack(switch ((inserted.length, dnsCount)) {
        (final n, 0) when needsSrs => getLocalText.plural(
            "Imported %d rules — tap ☁ to download rule-sets, then enable", n),
        (final n, 0) => getLocalText.plural("Imported %d rules", n),
        (0, final m) => getLocalText.s("Imported %d DNS entries", m),
        (final n, final m) => getLocalText.s(
            "Imported %1\$d rules and %2\$d DNS entries", n, m),
      });
    } catch (e) {
      showSnack(
        getLocalText.s("Import failed: %s", formatUserError(e).render()),
      );
    }
  }

  Widget _buildRouteFinalTile() {
    return RouteFinalTile(
      options: _outboundOptions(),
      routeFinal: _routeFinal,
      onChanged: (val) {
        setState(() {
          _routeFinal = val;
          _markDirty();
        });
      },
    );
  }







  void _onReorderCustomRule(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _customRules.length) return;
    if (newIndex < 0 || newIndex > _customRules.length - 1) return;
    final moved = _customRules[oldIndex];
    if (!_isSortable(moved)) return;
    setState(() {






      final rest = [..._customRules]..removeAt(oldIndex);
      final target = newIndex == 0 ? null : rest[newIndex - 1];
      placeRuleAfter(_customRules, moved, target, isSortable: _isSortable);
      final sorted = sortRulesByNum(_customRules);
      _customRules
        ..clear()
        ..addAll(sorted);
      _markDirty();
    });
  }





  bool _isSortable(CustomRule rule) {
    if (rule.kind != CustomRuleKind.preset) return true;
    return _presetFor(rule.presetId)?.isSortable ?? true;
  }

  Widget _buildCustomRuleTile(int index) {
    final rule = _customRules[index];
    final options = _outboundOptions();
    final preset = rule.kind == CustomRuleKind.preset
        ? _presetFor(rule.presetId)
        : null;

    final servedTags = rule is CustomRulePreset && preset != null
        ? presetServedTags(rule, preset, _presetViewNodes())
        : null;
    final subtitle = servedTags != null
        ? presetServedNodesLabel(servedTags)
        : _ruleSubtitle(rule, preset);
    final pickerValue = rule.kind == CustomRuleKind.preset
        ? _presetOut(rule, preset)
        : rule.outbound;
    final pickerDisabled = rule.kind == CustomRuleKind.preset && preset == null;

    final showOutbound = RoutingHelpers.showsOutboundPicker(rule, preset);




    final touchesDns = rule.kind == CustomRuleKind.preset
        ? (preset?.touchesDns ?? false)
        : (rule.dnsMirrorActive || rule.forceIpv4Active);

    Widget? statusButton;
    if (rule is CustomRuleSrs) {
      statusButton = _srsStatusButton(rule);
    } else if (rule is CustomRulePreset &&
        preset != null &&
        _remoteRuleSetsOf(preset, rule).isNotEmpty) {
      statusButton = _presetSrsStatusButton(rule, preset);
    }

    return CustomRuleTile(
      index: index,
      rule: rule,


      displayName: ruleDisplayName(rule, _customRules, _template),
      options: options,
      subtitle: subtitle,
      pickerValue: pickerValue,
      pickerDisabled: pickerDisabled,
      showOutbound: showOutbound,
      touchesDns: touchesDns,
      locked: preset?.locked ?? false,
      sortable: _isSortable(rule),
      statusButton: statusButton,
      onTap: () => _openCustomRuleEditor(index),
      onLongPressStart: (pos) => _showRuleContextMenu(index, pos),
      onSwitchChanged: (v) {
        if (v && rule is CustomRuleSrs && !_srsCached.contains(rule.id)) {
          unawaited(_enableAfterDownload(rule));
          return;
        }
        if (v &&
            rule is CustomRulePreset &&
            preset != null &&
            _presetNeedsDownload(rule, preset)) {
          unawaited(_enableAfterDownload(rule));
          return;
        }
        setState(() {
          _customRules[index] = rule.withEnabled(v);
          _markDirty();
        });


        final updated = _customRules[index];
        if (updated is CustomRulePreset && preset != null) {
          unawaited(applyPresetOnChange(preset, updated));
        }
      },
      onOutboundChanged: (val) {
        setState(() {
          _customRules[index] = rule.withOutbound(val);
          _markDirty();
        });
      },
    );
  }

  Widget _srsStatusButton(CustomRule rule) {
    return SrsStatusButton(
      rule: rule,
      downloading: _srsDownloading.contains(rule.id),
      cached: _srsCached.contains(rule.id),
      onPressed: () => unawaited(_downloadSrs(rule)),
    );
  }




  Widget _presetSrsStatusButton(CustomRulePreset rule, SelectableRule preset) {
    return PresetSrsStatusButton(
      rule: rule,
      preset: preset,
      downloading: _srsDownloading.contains(rule.id),
      cached: !_presetNeedsDownload(rule, preset),
      onTap: () => unawaited(_downloadSrsForPresetRule(rule)),
      onLongPress: () async {
        final pos = await _centerOf(context) ?? Offset.zero;
        if (!mounted) return;
        _showPresetCloudMenu(rule, preset, pos);
      },
    );
  }




  Future<Offset?> _centerOf(BuildContext ctx) async {
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }




  Future<void> _showPresetCloudMenu(
    CustomRulePreset rule,
    SelectableRule preset,
    Offset pos,
  ) async {
    final action = await showPresetCloudMenu(context, pos);
    if (!mounted) return;
    switch (action) {
      case 'refresh':
        unawaited(_downloadSrsForPresetRule(rule));
      case 'clear':
        for (final rs in _remoteRuleSetsOf(preset)) {
          await RuleSetDownloader.deleteForPreset(rule.presetId, rs.tag);
          _srsCached.remove(_presetSrsKey(rule, rs.tag));
        }
        if (!mounted) return;
        final i = _customRules.indexWhere((r) => r.id == rule.id);
        if (i >= 0) {
          setState(() {
            _customRules[i] = rule.withEnabled(false);
            _markDirty();
          });
        } else {
          setState(() {});
        }
    }
  }



  Future<void> _showRuleContextMenu(int index, Offset pos) async {
    if (index < 0 || index >= _customRules.length) return;
    final action = await showRuleContextMenu(context, pos);
    if (!mounted) return;
    if (action == 'delete') {
      unawaited(_confirmDeleteCustomRule(index));
    }
  }

  Future<void> _confirmDeleteCustomRule(int index) async {
    final rule = _customRules[index];
    final ok = await showDeleteCustomRuleDialog(
      context,
      rule,
      displayName: ruleDisplayName(rule, _customRules, _template),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _customRules.removeAt(index);
      _srsCached.remove(rule.id);
      _markDirty();
    });


    if (rule is CustomRuleSrs) {

      for (final cacheId in rule.cacheIds) {
        unawaited(RuleSetDownloader.delete(cacheId));
      }
    } else if (rule is CustomRulePreset) {
      final preset = _presetFor(rule.presetId);
      if (preset != null) {
        for (final rs in _remoteRuleSetsOf(preset)) {
          unawaited(RuleSetDownloader.deleteForPreset(rule.presetId, rs.tag));
          _srsCached.remove(_presetSrsKey(rule, rs.tag));
        }
      }
    }
  }

  void _addCustomRule() async {



    final fresh = CustomRuleInline(
      name: _uniqueCustomRuleName('Rule ${_customRules.length + 1}', ''),
    );
    final result = await openCustomRuleEditor(
      context,
      initial: fresh,
      outboundOptions: _outboundOptions()
          .map((o) => OutboundOption(value: o.tag, label: o.label))
          .toList(),


      existingNames: visibleRuleNames(_customRules, _template),
    );
    if (result == null) return;
    if (result.wasDeleted) return;
    if (result.saved != null && mounted) {
      final saved = result.saved!;


      saved.orderNum = nextUserRuleNum(_customRules);
      setState(() {
        _customRules.add(saved);
        final sorted = sortRulesByNum(_customRules);
        _customRules
          ..clear()
          ..addAll(sorted);
        _markDirty();
      });
    }
  }

  Future<void> _openCustomRuleEditor(int index) async {
    if (index < 0 || index >= _customRules.length) return;
    final current = _customRules[index];

    final existing = visibleRuleNames(
      _customRules,
      _template,
      excludeId: current.id,
    );
    final result = await openCustomRuleEditor(
      context,
      initial: current,
      outboundOptions: _outboundOptions()
          .map((o) => OutboundOption(value: o.tag, label: o.label))
          .toList(),
      existingNames: existing,
      preset: current.kind == CustomRuleKind.preset
          ? _presetFor(current.presetId)
          : null,

      presetNodes: current.kind == CustomRuleKind.preset
          ? _presetViewNodes()
          : const [],


      displayName: current.kind == CustomRuleKind.preset
          ? ruleDisplayName(current, _customRules, _template)
          : null,
    );
    if (result == null || !mounted) return;
    if (result.wasDeleted) {
      setState(() {
        _customRules.removeAt(index);
        _markDirty();
      });
    } else if (result.saved != null) {
      final saved = result.saved!;
      final urlChanged =
          current.kind == CustomRuleKind.srs &&
          current.srsUrls.join('\n') != saved.srsUrls.join('\n');
      final kindChanged = current.kind != saved.kind;
      setState(() {


        final next = (urlChanged || kindChanged)
            ? saved.withEnabled(false)
            : saved;
        _customRules[index] = next;
        if (urlChanged || kindChanged) _srsCached.remove(current.id);
        _markDirty();
      });
      if (urlChanged || kindChanged) {

        for (final cacheId in current is CustomRuleSrs
            ? current.cacheIds
            : <String>[current.id]) {
          unawaited(RuleSetDownloader.delete(cacheId));
        }
      }
    }
  }




  @override
  SelectableRule? _presetFor(String presetId) {
    if (presetId.isEmpty) return null;
    final template = _template;
    if (template == null) return null;
    for (final p in template.selectableRules) {
      if (p.presetId == presetId) return p;
    }
    return null;
  }

















  String _presetOut(CustomRule rule, SelectableRule? preset) =>
      RoutingHelpers.presetOut(rule, preset);

  String _ruleSubtitle(CustomRule rule, SelectableRule? preset) =>
      RoutingHelpers.ruleSubtitle(rule, preset);

  String _uniqueCustomRuleName(String requested, String selfId) =>
      RoutingHelpers.uniqueCustomRuleName(
        requested,
        selfId,
        _customRules,
        _template,
      );
}
