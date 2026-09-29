import '../../models/import_rule.dart';
import '../../models/node_spec.dart';
import '../../models/template_vars.dart';














class NodeRuleOutcome {



  final bool? disabled;


  final Map<String, dynamic>? patchedJson;



  final List<String> replacements;

  const NodeRuleOutcome({
    this.disabled,
    this.patchedJson,
    this.replacements = const [],
  });

  bool get changed => disabled != null || patchedJson != null;
}


class ImportRulesResult {

  final Set<int> disabledIndexes;



  final Set<int> enabledIndexes;



  final Map<int, NodeRuleOutcome> outcomes;

  const ImportRulesResult({
    this.disabledIndexes = const {},
    this.enabledIndexes = const {},
    this.outcomes = const {},
  });

  bool get isEmpty =>
      disabledIndexes.isEmpty && enabledIndexes.isEmpty && outcomes.isEmpty;
}





ImportRulesResult applyImportRules(List<NodeSpec> nodes, List<ImportRule> rules,
    {TemplateVars vars = TemplateVars.empty}) {
  final usable = rules.where((r) => r.isUsable).toList();
  if (usable.isEmpty || nodes.isEmpty) return const ImportRulesResult();

  final disabled = <int>{};
  final enabled = <int>{};
  final outcomes = <int, NodeRuleOutcome>{};

  for (var i = 0; i < nodes.length; i++) {
    final outcome = applyRulesToNode(nodes[i], usable, vars: vars);
    if (!outcome.changed) continue;
    outcomes[i] = outcome;
    if (outcome.disabled == true) disabled.add(i);
    if (outcome.disabled == false) enabled.add(i);
  }

  return ImportRulesResult(
    disabledIndexes: disabled,
    enabledIndexes: enabled,
    outcomes: outcomes,
  );
}



NodeRuleOutcome applyRulesToNode(NodeSpec node, List<ImportRule> rules,
    {TemplateVars vars = TemplateVars.empty}) {





  final json = node.emitRaw(vars).map;
  var patched = false;


  bool? disabled;
  final trail = <String>[];

  for (final rule in rules) {
    final match = _evaluate(rule, json);
    if (!match.matched) continue;

    if (rule.action == ImportRuleAction.disable) {
      disabled = true;
      continue;
    }
    if (rule.action == ImportRuleAction.enable) {
      disabled = false;
      continue;
    }




    if (rule.targetPath.isEmpty) {
      final changes = _substituteWholeNode(json, rule);
      if (changes.isNotEmpty) {
        patched = true;
        trail.addAll(changes);
      }
      continue;
    }

    final before = readJsonPath(json, rule.targetPath);
    final next = _buildReplacement(rule, match, before);
    if (next == null || next == before) continue;
    if (!writeJsonPath(json, rule.targetPath, next)) continue;
    patched = true;
    trail.add('${rule.targetPath}: ${before ?? '(none)'} → $next');
  }

  return NodeRuleOutcome(
    disabled: disabled,
    patchedJson: patched ? json : null,
    replacements: trail,
  );
}


class _MatchResult {
  final bool matched;



  final Map<JsonPath, List<String>> groups;

  const _MatchResult(this.matched, [this.groups = const {}]);
}

_MatchResult _evaluate(ImportRule rule, Map<String, dynamic> json) {
  final conds = rule.usableConditions;
  if (conds.isEmpty) return const _MatchResult(false);

  final groups = <JsonPath, List<String>>{};
  var anyTrue = false;
  var allTrue = true;

  for (final c in conds) {
    final value = readJsonPath(json, c.path);
    final hit = _test(c, value, groups);
    if (hit) {
      anyTrue = true;
    } else {
      allTrue = false;
    }
  }

  final matched =
      rule.matchMode == ImportRuleMatchMode.all ? allTrue : anyTrue;
  return _MatchResult(matched, groups);
}


bool _test(ImportRuleCondition c, String? value,
    Map<JsonPath, List<String>> groups) {


  if (value == null) return c.negate;

  var hit = false;
  switch (c.op) {
    case ImportRuleOperator.contains:
      hit = c.caseSensitive
          ? value.contains(c.pattern)
          : value.toLowerCase().contains(c.pattern.toLowerCase());
    case ImportRuleOperator.equals:
      hit = c.caseSensitive
          ? value == c.pattern
          : value.toLowerCase() == c.pattern.toLowerCase();
    case ImportRuleOperator.matches:
      final re = c.compiledPattern;
      if (re == null) return c.negate;
      final m = re.firstMatch(value);
      hit = m != null;
      if (m != null) {
        groups[c.path] = [
          for (var g = 1; g <= m.groupCount; g++) m.group(g) ?? '',
        ];
      }
  }
  return c.negate ? !hit : hit;
}


String? _buildReplacement(
    ImportRule rule, _MatchResult match, String? currentValue) {
  final pockets = match.groups[rule.targetPath] ??



      (match.groups.isEmpty ? const <String>[] : match.groups.values.first);

  final expanded = _expandPockets(rule.replacement, pockets);

  switch (rule.replaceMode) {
    case ImportRuleReplaceMode.set:
      return expanded;

    case ImportRuleReplaceMode.substitute:
      if (currentValue == null) return null;


      final needle = rule.substitutePattern.isNotEmpty
          ? rule.substitutePattern
          : _patternForPath(rule, rule.targetPath);
      if (needle == null || needle.isEmpty) return null;

      final cond = _conditionForPath(rule, rule.targetPath);
      final useRegex = rule.substitutePattern.isEmpty &&
          cond?.op == ImportRuleOperator.matches;
      final caseSensitive = cond?.caseSensitive ?? false;
      try {
        final re = useRegex
            ? RegExp(needle, caseSensitive: caseSensitive)
            : RegExp(RegExp.escape(needle), caseSensitive: caseSensitive);
        return currentValue.replaceAllMapped(
          re,
          (m) => _expandPockets(
            rule.replacement,
            [for (var g = 1; g <= m.groupCount; g++) m.group(g) ?? ''],
          ),
        );
      } catch (_) {
        return null;
      }
  }
}










List<String> _substituteWholeNode(Map<String, dynamic> json, ImportRule rule) {
  if (rule.replaceMode != ImportRuleReplaceMode.substitute) return const [];

  final needle = rule.substitutePattern.isNotEmpty
      ? rule.substitutePattern
      : _patternForPath(rule, '');
  if (needle == null || needle.isEmpty) return const [];

  final cond = _conditionForPath(rule, '');
  final useRegex = rule.substitutePattern.isEmpty &&
      cond?.op == ImportRuleOperator.matches;
  final caseSensitive = cond?.caseSensitive ?? false;
  final RegExp re;
  try {
    re = useRegex
        ? RegExp(needle, caseSensitive: caseSensitive)
        : RegExp(RegExp.escape(needle), caseSensitive: caseSensitive);
  } catch (_) {
    return const [];
  }

  final trail = <String>[];



  Object? replaceLeaf(Object value) {
    final before = value.toString();
    final after = before.replaceAllMapped(
      re,
      (m) => _expandPockets(
        rule.replacement,
        [for (var g = 1; g <= m.groupCount; g++) m.group(g) ?? ''],
      ),
    );
    return after == before ? null : coerceJsonLike(value, after);
  }

  void visit(Object? node, String prefix,
      void Function(Object coerced) write) {
    if (node is Map<String, dynamic>) {

      for (final key in node.keys.toList()) {
        final path = prefix.isEmpty ? key : '$prefix.$key';
        visit(node[key], path, (v) => node[key] = v);
      }
      return;
    }
    if (node is List) {
      for (var i = 0; i < node.length; i++) {
        visit(node[i], '$prefix.$i', (v) => node[i] = v);
      }
      return;
    }
    if (node == null) return;
    final next = replaceLeaf(node);
    if (next == null) return;
    write(next);
    trail.add('$prefix: $node → $next');
  }

  visit(json, '', (_) {});
  return trail;
}

ImportRuleCondition? _conditionForPath(ImportRule rule, JsonPath path) {
  for (final c in rule.usableConditions) {
    if (c.path == path) return c;
  }
  return null;
}

String? _patternForPath(ImportRule rule, JsonPath path) =>
    _conditionForPath(rule, path)?.pattern;


String _expandPockets(String template, List<String> pockets) {
  if (!template.contains(r'$')) return template;
  final out = StringBuffer();
  for (var i = 0; i < template.length; i++) {
    final ch = template[i];
    if (ch != r'$' || i + 1 >= template.length) {
      out.write(ch);
      continue;
    }
    final next = template[i + 1];
    if (next == r'$') {
      out.write(r'$');
      i++;
      continue;
    }
    final idx = int.tryParse(next);
    if (idx == null || idx < 1) {
      out.write(ch);
      continue;
    }
    out.write(idx <= pockets.length ? pockets[idx - 1] : '');
    i++;
  }
  return out.toString();
}
