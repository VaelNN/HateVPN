import '../services/builder/preset_expand.dart'
    show fragmentGateSatisfied, presetVarsMap;
import 'custom_rule.dart' show CustomRulePreset, kDefaultSrsTtlHours;
import 'parser_config.dart' show SelectableRule;






class PresetRemoteRuleSet {
  const PresetRemoteRuleSet({
    required this.tag,
    required this.url,
    this.updateIntervalHours = kDefaultSrsTtlHours,
  });
  final String tag;
  final String url;



  final int updateIntervalHours;
}










int parseUpdateIntervalHours(dynamic raw) {
  if (raw is num) return raw <= 0 ? 0 : raw.ceil();
  if (raw is! String) return kDefaultSrsTtlHours;
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) return kDefaultSrsTtlHours;
  final m = RegExp(r'^(\d+)\s*(h|d|w|m|s)?$').firstMatch(s);
  if (m == null) return kDefaultSrsTtlHours;
  final n = int.tryParse(m.group(1)!);
  if (n == null) return kDefaultSrsTtlHours;
  if (n == 0) return 0;
  return switch (m.group(2)) {
    'd' => n * 24,
    'w' => n * 24 * 7,

    'm' => (n / 60).ceil(),
    's' => (n / 3600).ceil(),
    _ => n,
  };
}














List<PresetRemoteRuleSet> remoteRuleSetsOfPreset(
  SelectableRule preset, [
  CustomRulePreset? rule,
  Map<String, String> globalVars = const {},
]) {
  final out = <PresetRemoteRuleSet>[];
  for (final rs in preset.ruleSets) {
    final remote = _asRemote(rs);
    if (remote == null) continue;
    if (rule != null &&
        !isRuleSetEnabledFor(rs, preset, rule, globalVars: globalVars)) {
      continue;
    }
    out.add(remote);
  }
  return out;
}



PresetRemoteRuleSet? _asRemote(Map<String, dynamic> rs) {
  if (rs['type'] != 'remote') return null;
  final tag = rs['tag'];
  final url = rs['url'];
  if (tag is! String || tag.isEmpty) return null;
  if (url is! String || url.isEmpty) return null;
  return PresetRemoteRuleSet(
    tag: tag,
    url: url,
    updateIntervalHours: parseUpdateIntervalHours(rs['update_interval']),
  );
}












List<PresetRemoteRuleSet> ruleSetsEnabledByVar(
  SelectableRule preset,
  CustomRulePreset rule,
  String varName, {
  Map<String, String> globalVars = const {},
}) {
  CustomRulePreset withVar(String value) => CustomRulePreset(
        name: rule.name,
        presetId: rule.presetId,
        varsValues: {...rule.varsValues, varName: value},
      );
  final off = withVar('false');
  final on = withVar('true');
  final out = <PresetRemoteRuleSet>[];
  for (final rs in preset.ruleSets) {
    final remote = _asRemote(rs);
    if (remote == null) continue;
    if (isRuleSetEnabledFor(rs, preset, off, globalVars: globalVars)) continue;
    if (!isRuleSetEnabledFor(rs, preset, on, globalVars: globalVars)) continue;
    out.add(remote);
  }
  return out;
}


















bool isRuleSetEnabledFor(
  Map<String, dynamic> rs,
  SelectableRule preset,
  CustomRulePreset rule, {
  Map<String, String> globalVars = const {},
}) =>
    fragmentGateSatisfied(
      rs,
      presetVarsMap(rule, preset, globalVars: globalVars).vars,
    );
