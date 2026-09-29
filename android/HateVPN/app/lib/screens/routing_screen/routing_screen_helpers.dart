import '../../config/consts.dart' show kBlockOutboundTag, kDirectOutboundTag;
import '../../models/direction.dart';
import '../../models/custom_rule.dart';
import '../../models/parser_config.dart';
import '../../models/preset_rule_set.dart';
import '../../services/rule_display_names.dart';
import '../../services/rule_set_downloader.dart' show RuleSetDownloader;
import '../../services/l10n/locale_controller.dart';




export '../../models/preset_rule_set.dart';


class RoutingOutboundOption {
  const RoutingOutboundOption({
    required this.label,
    required this.tag,
    this.danger = false,
  });
  final String label;
  final String tag;


  final bool danger;
}





final SelectableRule kEmptySelectable =
    SelectableRule(label: '', presetId: '__empty_sentinel__');



class RoutingHelpers {
  const RoutingHelpers._();









  static List<RoutingOutboundOption> outboundOptions(List<Direction> directions) {
    final opts = <RoutingOutboundOption>[
      const RoutingOutboundOption(label: 'direct', tag: kDirectOutboundTag),
    ];
    for (final c in directions) {
      if (c.enabled || c.isRequired) {
        opts.add(RoutingOutboundOption(label: c.displayLabel, tag: c.tag));
      }
    }
    opts.add(const RoutingOutboundOption(
        label: 'block', tag: kBlockOutboundTag, danger: true));
    return opts;
  }












  static List<PresetRemoteRuleSet> remoteRuleSetsOf(
    SelectableRule preset, [
    CustomRulePreset? rule,
    Map<String, String> globalVars = const {},
  ]) =>
      remoteRuleSetsOfPreset(preset, rule, globalVars);



  static bool isRuleSetEnabled(
    Map<String, dynamic> rs,
    SelectableRule preset,
    CustomRulePreset rule, {
    Map<String, String> globalVars = const {},
  }) =>
      isRuleSetEnabledFor(rs, preset, rule, globalVars: globalVars);




  static String presetSrsKey(CustomRulePreset rule, String tag) =>
      '${rule.id}|$tag';









  static ({Set<String> keepCacheIds, List<PresetRemoteRuleSet> required})
      presetCachePlan(
    CustomRulePreset rule,
    SelectableRule preset, {
    Map<String, String> globalVars = const {},
  }) =>
          (
            keepCacheIds: {
              for (final rs in remoteRuleSetsOf(preset))
                RuleSetDownloader.presetCacheId(rule.presetId, rs.tag),
            },
            required: remoteRuleSetsOf(preset, rule, globalVars),
          );






  static bool presetNeedsDownload(
    CustomRulePreset rule,
    SelectableRule preset,
    Set<String> srsCached, {
    Map<String, String> globalVars = const {},
  }) {

    final remotes = remoteRuleSetsOf(preset, rule, globalVars);
    if (remotes.isEmpty) return false;
    for (final rs in remotes) {
      if (!srsCached.contains(presetSrsKey(rule, rs.tag))) return true;
    }
    return false;
  }

  static String presetOut(CustomRule rule, SelectableRule? preset) {
    final explicit = rule.varsValues['outbound'];
    if (explicit != null && explicit.isNotEmpty) return explicit;
    if (preset == null) return kDirectOutboundTag;
    for (final v in preset.vars) {
      if (v.name == 'outbound') return v.defaultValue;
    }


    final action = preset.terminalRule['action'];
    if (action is String && action.isNotEmpty) return action;
    final literal = preset.terminalRule['outbound'];
    if (literal is String && literal.isNotEmpty && !literal.startsWith('@')) {
      return literal;
    }
    return kDirectOutboundTag;
  }










  static bool showsOutboundPicker(CustomRule rule, SelectableRule? preset) =>
      switch (rule.kind) {
        CustomRuleKind.json => false,
        CustomRuleKind.preset => preset == null || preset.hasOutboundAffordance,
        CustomRuleKind.inline || CustomRuleKind.srs => true,
      };

  static String ruleSubtitle(CustomRule rule, SelectableRule? preset) {
    if (rule.kind == CustomRuleKind.preset) {
      if (preset == null) return getLocalText.s("Preset not found — tap to fix");

      final extras = <String>[];
      for (final v in preset.vars) {




        if (v.isRef) continue;

        if (v.wizardUI == 'hidden') continue;
        final value = rule.varsValues[v.name] ?? v.defaultValue;
        if (value.isEmpty || value == v.defaultValue) continue;
        extras.add('${v.name}: $value');
      }
      if (extras.isEmpty) return getLocalText.s("Tap to edit");
      return getLocalText.s("%s — tap to edit", extras.take(2).join(' · '));
    }
    final summary = rule.summary();
    return summary.isEmpty
        ? getLocalText.s("Tap to add match fields")
        : getLocalText.s("%s — tap to edit", summary);
  }






  static String uniqueCustomRuleName(
    String requested,
    String selfId,
    List<CustomRule> customRules,
    WizardTemplate? template,
  ) {
    final others =
        visibleRuleNames(customRules, template, excludeId: selfId);
    if (!others.contains(requested)) return requested;
    var i = 2;
    while (others.contains('$requested ($i)')) {
      i++;
    }
    return '$requested ($i)';
  }
}
