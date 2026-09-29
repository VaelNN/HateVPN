import '../models/custom_rule.dart';
import '../models/parser_config.dart';
import 'record_vars.dart';








CustomRulePreset selectableRuleToCustom(
  SelectableRule sr,
  WizardTemplate template, {
  String? overrideOutbound,
}) {
  final varsValues = <String, String>{};
  if (overrideOutbound != null) {


    RecordVarDecl? decl;
    for (final v in sr.vars) {
      if (v.name == kPresetOutboundVar && !v.isRef) {
        decl = RecordVarDecl(name: v.name, defaultValue: v.defaultValue);
        break;
      }
    }
    final stored = recordVarValueToStore(overrideOutbound, decl);
    if (stored != null) varsValues[kPresetOutboundVar] = stored;
  }

  return CustomRulePreset(
    name: sr.label.isEmpty ? sr.presetId : sr.label,
    presetId: sr.presetId,
    varsValues: varsValues,
  );
}
