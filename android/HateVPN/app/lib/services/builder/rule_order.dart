














library;

import '../../models/custom_rule.dart';
import '../../models/parser_config.dart';
import '../selectable_to_custom.dart';















bool markRuleOrder(
  List<CustomRule> customRules,
  List<SelectableRule> selectableRules,
) {
  final numByPresetId = {
    for (final sr in selectableRules) sr.presetId: sr.num,
  };

  var changed = false;
  var nextUserNum = kUserRuleNumStart;
  for (final cr in customRules) {
    if (cr.orderNum != null) continue;
    final fromTemplate =
        cr.kind == CustomRuleKind.preset ? numByPresetId[cr.presetId] : null;
    cr.orderNum = fromTemplate ?? nextUserNum++;
    changed = true;
  }
  return changed;
}















bool pinRequiredRuleNums(
  List<CustomRule> customRules,
  List<SelectableRule> selectableRules,
) {
  final pinned = {
    for (final sr in selectableRules)
      if (!sr.isSortable) sr.presetId: sr.num,
  };
  if (pinned.isEmpty) return false;
  var changed = false;
  for (final cr in customRules) {
    if (cr.kind != CustomRuleKind.preset) continue;
    final n = pinned[cr.presetId];
    if (n == null || cr.orderNum == n) continue;
    cr.orderNum = n;
    changed = true;
  }
  return changed;
}




bool requiredRuleNumsShifted(
  List<CustomRule> customRules,
  List<SelectableRule> selectableRules,
) {
  final pinned = {
    for (final sr in selectableRules)
      if (!sr.isSortable) sr.presetId: sr.num,
  };
  return customRules.any((cr) =>
      cr.kind == CustomRuleKind.preset &&
      pinned.containsKey(cr.presetId) &&
      cr.orderNum != pinned[cr.presetId]);
}







List<CustomRule> sortRulesByNum(List<CustomRule> customRules) {
  final indexed = [
    for (var i = 0; i < customRules.length; i++) (i, customRules[i]),
  ];
  indexed.sort((a, b) {
    final byNum = (a.$2.orderNum ?? kDefaultRuleNum)
        .compareTo(b.$2.orderNum ?? kDefaultRuleNum);
    return byNum != 0 ? byNum : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}











List<CustomRule> seedRequiredPresets(
  List<CustomRule> customRules,
  List<SelectableRule> selectableRules,
  WizardTemplate template,
) {
  final required = selectableRules.where((r) => !r.isSortable).toList();
  if (required.isEmpty) return customRules;

  final present = {
    for (final cr in customRules)
      if (cr.kind == CustomRuleKind.preset) cr.presetId,
  };
  final missing = required.where((r) => !present.contains(r.presetId));
  if (missing.isEmpty) return customRules;

  final out = [...customRules];
  for (final spec in missing) {
    final seeded = selectableRuleToCustom(spec, template);
    out.add(CustomRulePreset(
      name: seeded.name,
      presetId: seeded.presetId,
      enabled: spec.defaultEnabled,
      varsValues: seeded.varsValues,
      orderNum: spec.num,
    ));
  }
  return out;
}













List<CustomRule> dedupePresetRules(List<CustomRule> customRules) {
  final lastIndexByPresetId = <String, int>{};
  for (var i = 0; i < customRules.length; i++) {
    final cr = customRules[i];
    if (cr.kind != CustomRuleKind.preset) continue;
    lastIndexByPresetId[cr.presetId] = i;
  }
  if (lastIndexByPresetId.length == customRules.where((c) => c.kind == CustomRuleKind.preset).length) {
    return customRules;
  }
  return [
    for (var i = 0; i < customRules.length; i++)
      if (customRules[i].kind != CustomRuleKind.preset ||
          lastIndexByPresetId[customRules[i].presetId] == i)
        customRules[i],
  ];
}







List<CustomRule> normalizeRuleOrder(
  List<CustomRule> customRules,
  List<SelectableRule> selectableRules,
  WizardTemplate template,
) {


  final deduped = dedupePresetRules(customRules);
  final seeded = seedRequiredPresets(deduped, selectableRules, template);


  pinRequiredRuleNums(seeded, selectableRules);
  markRuleOrder(seeded, selectableRules);
  return sortRulesByNum(seeded);
}







int nextUserRuleNum(List<CustomRule> customRules) {
  var maxInZone = kUserRuleNumStart - 1;
  for (final cr in customRules) {
    final n = cr.orderNum;
    if (n == null || n < kUserRuleNumStart || n > kUserRuleNumEnd) continue;
    if (n > maxInZone) maxInZone = n;
  }
  final next = maxInZone + 1;
  return next > kUserRuleNumEnd ? kUserRuleNumEnd : next;
}


























void placeRuleAfter(
  List<CustomRule> customRules,
  CustomRule moved,
  CustomRule? target, {
  required bool Function(CustomRule) isSortable,
}) {
  if (!isSortable(moved)) return;

  final want = target == null
      ? kUserRuleNumStart
      : (target.orderNum ?? kDefaultRuleNum) + 1;



  final occupied = <int, List<CustomRule>>{};
  for (final cr in customRules) {
    if (identical(cr, moved) || !isSortable(cr)) continue;
    final n = cr.orderNum;
    if (n != null && n >= want) (occupied[n] ??= []).add(cr);
  }



  final block = <CustomRule>[];
  for (var n = want; occupied.containsKey(n); n++) {
    block.addAll(occupied[n]!);
  }

  for (final cr in block.reversed) {
    cr.orderNum = cr.orderNum! + 1;
  }
  moved.orderNum = want;
}













List<CustomRule> stripRefVarsFromVarsValues(
  List<CustomRule> customRules,
  List<SelectableRule> selectableRules,
) {

  final refNamesByPreset = <String, Set<String>>{};
  for (final sr in selectableRules) {
    final refs = {for (final v in sr.vars) if (v.isRef) v.ref};
    if (refs.isNotEmpty) refNamesByPreset[sr.presetId] = refs;
  }
  if (refNamesByPreset.isEmpty) return customRules;

  var changed = false;
  final out = <CustomRule>[];
  for (final cr in customRules) {
    if (cr is CustomRulePreset) {
      final refs = refNamesByPreset[cr.presetId];
      if (refs != null && cr.varsValues.keys.any(refs.contains)) {
        final cleaned = {
          for (final e in cr.varsValues.entries)
            if (!refs.contains(e.key)) e.key: e.value,
        };
        out.add(cr.copyWith(varsValues: cleaned));
        changed = true;
        continue;
      }
    }
    out.add(cr);
  }
  return changed ? out : customRules;
}
