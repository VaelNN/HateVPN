import '../models/custom_rule.dart';
import '../models/parser_config.dart';
import 'builder/if_engine.dart';
import 'builder/post_steps.dart' show presetDnsEnableVar;
import 'settings_storage.dart';
























Future<void> applyPresetOnChange(
  SelectableRule preset,
  CustomRulePreset cr,
) async {


  final targets = <String, Map<String, dynamic>>{};
  for (final v in preset.vars) {

    final oc = v.onChange?['#set'] ?? v.onChange?['set'];
    if (oc is! Map<String, dynamic>) continue;
    oc.forEach((target, ifNode) {
      if (ifNode is Map<String, dynamic>) {
        final tName = target.startsWith('@') ? target.substring(1) : target;
        targets[tName] = ifNode;
      }
    });
  }
  if (targets.isEmpty) return;



  final userVars = await SettingsStorage.getAllVars();
  final ns = <String, String>{
    ...userVars,
    'rule_enable': cr.enabled ? 'true' : 'false',

    'dns_enable': presetDnsEnableVar(cr, preset) ? 'true' : 'false',
  };



  final byName = <String, WizardVar>{
    for (final v in preset.vars) v.name: v,
  };
  final resolve = makeResolver(ns, byName);

  for (final entry in targets.entries) {
    final resolved = evalIfScalar(entry.value, resolve);
    if (resolved == null) continue;
    await SettingsStorage.setVar(entry.key, resolved);
  }
}

