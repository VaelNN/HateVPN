import '../models/custom_rule.dart';
import '../models/parser_config.dart';

















String ruleDisplayName(
  CustomRule rule,
  List<CustomRule> allRules,
  WizardTemplate? template,
) {
  if (rule.kind != CustomRuleKind.preset) return rule.name;
  final live = _liveLabel(rule.presetId, template);
  if (live == null) return rule.name;

  var ordinal = 0;
  for (final r in allRules) {
    if (r.kind != CustomRuleKind.preset || r.presetId != rule.presetId) {
      continue;
    }
    ordinal++;
    if (r.id == rule.id) return ordinal <= 1 ? live : '$live ($ordinal)';
  }

  return live;
}


List<String> ruleDisplayNames(
  List<CustomRule> rules,
  WizardTemplate? template,
) {
  final out = <String>[];
  final ordinalByPresetId = <String, int>{};
  for (final r in rules) {
    if (r.kind != CustomRuleKind.preset) {
      out.add(r.name);
      continue;
    }
    final n = (ordinalByPresetId[r.presetId] ?? 0) + 1;
    ordinalByPresetId[r.presetId] = n;
    final live = _liveLabel(r.presetId, template);
    if (live == null) {
      out.add(r.name);
    } else {
      out.add(n <= 1 ? live : '$live ($n)');
    }
  }
  return out;
}





Set<String> visibleRuleNames(
  List<CustomRule> rules,
  WizardTemplate? template, {
  String excludeId = '',
}) {
  final names = ruleDisplayNames(rules, template);
  final out = <String>{};
  for (var i = 0; i < rules.length; i++) {
    if (rules[i].id == excludeId) continue;
    out.add(names[i]);
    out.add(rules[i].name);
  }
  return out;
}

String? _liveLabel(String presetId, WizardTemplate? template) {
  if (presetId.isEmpty || template == null) return null;
  for (final p in template.selectableRules) {
    if (p.presetId == presetId) return p.label.isEmpty ? null : p.label;
  }
  return null;
}
