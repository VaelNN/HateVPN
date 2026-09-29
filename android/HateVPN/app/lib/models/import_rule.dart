import 'dart:convert';


























typedef JsonPath = String;

enum ImportRuleOperator {
  contains,
  equals,
  matches;

  static ImportRuleOperator fromName(String? s) => switch (s) {
        'equals' => ImportRuleOperator.equals,
        'matches' => ImportRuleOperator.matches,
        _ => ImportRuleOperator.contains,
      };
}

enum ImportRuleMatchMode {

  any,


  all;

  static ImportRuleMatchMode fromName(String? s) =>
      s == 'any' ? ImportRuleMatchMode.any : ImportRuleMatchMode.all;
}

enum ImportRuleAction {
  replace,
  disable,






  enable;

  static ImportRuleAction fromName(String? s) => switch (s) {
        'disable' => ImportRuleAction.disable,
        'enable' => ImportRuleAction.enable,
        _ => ImportRuleAction.replace,
      };
}


enum ImportRuleReplaceMode {

  set,


  substitute;

  static ImportRuleReplaceMode fromName(String? s) =>
      s == 'substitute' ? ImportRuleReplaceMode.substitute : ImportRuleReplaceMode.set;
}


class ImportRuleCondition {
  final JsonPath path;
  final ImportRuleOperator op;
  final String pattern;


  final bool negate;



  final bool caseSensitive;

  const ImportRuleCondition({
    this.path = '',
    this.op = ImportRuleOperator.contains,
    this.pattern = '',
    this.negate = false,
    this.caseSensitive = false,
  });



  RegExp? get compiledPattern {
    if (op != ImportRuleOperator.matches || pattern.isEmpty) return null;
    try {
      return RegExp(pattern, caseSensitive: caseSensitive);
    } catch (_) {
      return null;
    }
  }




  bool get isUsable {
    if (pattern.isEmpty) return false;
    if (op == ImportRuleOperator.matches) return compiledPattern != null;
    return true;
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'op': op.name,
        'pattern': pattern,
        if (negate) 'negate': true,
        if (caseSensitive) 'case_sensitive': true,
      };

  factory ImportRuleCondition.fromJson(Map<String, dynamic> j) =>
      ImportRuleCondition(
        path: (j['path'] as String?) ?? '',
        op: ImportRuleOperator.fromName(j['op'] as String?),
        pattern: (j['pattern'] as String?) ?? '',
        negate: (j['negate'] as bool?) ?? false,
        caseSensitive: (j['case_sensitive'] as bool?) ?? false,
      );

  ImportRuleCondition copyWith({
    JsonPath? path,
    ImportRuleOperator? op,
    String? pattern,
    bool? negate,
    bool? caseSensitive,
  }) =>
      ImportRuleCondition(
        path: path ?? this.path,
        op: op ?? this.op,
        pattern: pattern ?? this.pattern,
        negate: negate ?? this.negate,
        caseSensitive: caseSensitive ?? this.caseSensitive,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportRuleCondition &&
          path == other.path &&
          op == other.op &&
          pattern == other.pattern &&
          negate == other.negate &&
          caseSensitive == other.caseSensitive);

  @override
  int get hashCode => Object.hash(path, op, pattern, negate, caseSensitive);
}

class ImportRule {
  final List<ImportRuleCondition> conditions;


  final ImportRuleMatchMode matchMode;

  final ImportRuleAction action;


  final JsonPath targetPath;




  final String replacement;

  final ImportRuleReplaceMode replaceMode;



  final String substitutePattern;


  final bool enabled;

  const ImportRule({
    this.conditions = const [],
    this.matchMode = ImportRuleMatchMode.all,
    this.action = ImportRuleAction.replace,
    this.targetPath = '',
    this.replacement = '',
    this.replaceMode = ImportRuleReplaceMode.set,
    this.substitutePattern = '',
    this.enabled = true,
  });









  bool get isUsable {
    if (!enabled) return false;
    if (!conditions.any((c) => c.isUsable)) return false;
    if (action == ImportRuleAction.replace && targetPath.isEmpty) {
      if (replaceMode != ImportRuleReplaceMode.substitute) return false;
      final hasNeedle = substitutePattern.isNotEmpty ||
          conditions.any((c) => c.isUsable && c.path.isEmpty);
      if (!hasNeedle) return false;
    }
    return true;
  }


  List<ImportRuleCondition> get usableConditions =>
      conditions.where((c) => c.isUsable).toList();

  Map<String, dynamic> toJson() => {
        'conditions': [for (final c in conditions) c.toJson()],
        if (matchMode != ImportRuleMatchMode.all) 'match': matchMode.name,
        'action': action.name,
        if (targetPath.isNotEmpty) 'target_path': targetPath,
        if (replacement.isNotEmpty) 'replacement': replacement,
        if (replaceMode != ImportRuleReplaceMode.set)
          'replace_mode': replaceMode.name,
        if (substitutePattern.isNotEmpty) 'substitute': substitutePattern,
        if (!enabled) 'enabled': false,
      };

  factory ImportRule.fromJson(Map<String, dynamic> j) {




    if (j['conditions'] == null && j['pattern'] is String) {
      final legacyPattern = j['pattern'] as String;
      final isRegex = (j['is_regex'] as bool?) ?? false;
      final cs = (j['case_sensitive'] as bool?) ?? false;
      final action = ImportRuleAction.fromName(j['action'] as String?);
      return ImportRule(
        conditions: [
          ImportRuleCondition(
            path: 'tag',
            op: isRegex
                ? ImportRuleOperator.matches
                : ImportRuleOperator.contains,
            pattern: legacyPattern,
            caseSensitive: cs,
          ),
        ],
        action: action,
        targetPath: action == ImportRuleAction.replace ? 'tag' : '',
        replacement: (j['replacement'] as String?) ?? '',
        replaceMode: ImportRuleReplaceMode.substitute,
        substitutePattern: legacyPattern,
        enabled: (j['enabled'] as bool?) ?? true,
      );
    }

    return ImportRule(
      conditions: [
        for (final c in (j['conditions'] as List?) ?? const [])
          if (c is Map<String, dynamic>) ImportRuleCondition.fromJson(c),
      ],
      matchMode: ImportRuleMatchMode.fromName(j['match'] as String?),
      action: ImportRuleAction.fromName(j['action'] as String?),
      targetPath: (j['target_path'] as String?) ?? '',
      replacement: (j['replacement'] as String?) ?? '',
      replaceMode: ImportRuleReplaceMode.fromName(j['replace_mode'] as String?),
      substitutePattern: (j['substitute'] as String?) ?? '',
      enabled: (j['enabled'] as bool?) ?? true,
    );
  }

  ImportRule copyWith({
    List<ImportRuleCondition>? conditions,
    ImportRuleMatchMode? matchMode,
    ImportRuleAction? action,
    JsonPath? targetPath,
    String? replacement,
    ImportRuleReplaceMode? replaceMode,
    String? substitutePattern,
    bool? enabled,
  }) =>
      ImportRule(
        conditions: conditions ?? this.conditions,
        matchMode: matchMode ?? this.matchMode,
        action: action ?? this.action,
        targetPath: targetPath ?? this.targetPath,
        replacement: replacement ?? this.replacement,
        replaceMode: replaceMode ?? this.replaceMode,
        substitutePattern: substitutePattern ?? this.substitutePattern,
        enabled: enabled ?? this.enabled,
      );



  String get summary {
    final parts = [
      for (final c in conditions)

        '${c.path.isEmpty ? '*' : c.path} '
            '${c.negate ? 'not ' : ''}${c.op.name} ${c.pattern}',
    ];
    final cond = parts.isEmpty
        ? '(no conditions)'
        : parts.join(matchMode == ImportRuleMatchMode.all ? ' AND ' : ' OR ');
    final act = switch (action) {
      ImportRuleAction.disable => 'Disable',
      ImportRuleAction.enable => 'Enable',

      ImportRuleAction.replace =>
        '${targetPath.isEmpty ? '*' : targetPath} = $replacement',
    };
    return '$cond → $act';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportRule &&
          _listEq(conditions, other.conditions) &&
          matchMode == other.matchMode &&
          action == other.action &&
          targetPath == other.targetPath &&
          replacement == other.replacement &&
          replaceMode == other.replaceMode &&
          substitutePattern == other.substitutePattern &&
          enabled == other.enabled);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(conditions),
        matchMode,
        action,
        targetPath,
        replacement,
        replaceMode,
        substitutePattern,
        enabled,
      );

  static bool _listEq(List<ImportRuleCondition> a, List<ImportRuleCondition> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}






String? readJsonPath(Map<String, dynamic> map, JsonPath path) {


  if (path.isEmpty) return jsonEncode(map);
  Object? cur = map;
  for (final seg in path.split('.')) {
    if (seg.isEmpty) return null;
    if (cur is Map) {
      if (!cur.containsKey(seg)) return null;
      cur = cur[seg];
      continue;
    }
    if (cur is List) {
      final i = int.tryParse(seg);
      if (i == null || i < 0 || i >= cur.length) return null;
      cur = cur[i];
      continue;
    }
    return null;
  }
  if (cur == null) return null;
  if (cur is Map || cur is List) return jsonEncode(cur);
  return cur.toString();
}








bool writeJsonPath(Map<String, dynamic> map, JsonPath path, String value) {
  if (path.isEmpty) return false;
  final segs = path.split('.');



  if (segs.any((s) => s.isEmpty || s.startsWith('//'))) return false;
  Map<String, dynamic> cur = map;
  for (var i = 0; i < segs.length - 1; i++) {
    final seg = segs[i];
    final next = cur[seg];
    if (next is Map<String, dynamic>) {
      cur = next;
    } else if (next == null) {
      final created = <String, dynamic>{};
      cur[seg] = created;
      cur = created;
    } else {
      return false;
    }
  }
  final last = segs.last;
  cur[last] = coerceJsonLike(cur[last], value);
  return true;
}




Object? coerceJsonLike(Object? previous, String value) {
  if (previous is int) {
    final n = int.tryParse(value);
    if (n != null) return n;
  } else if (previous is double) {
    final n = double.tryParse(value);
    if (n != null) return n;
  } else if (previous is bool) {
    if (value == 'true') return true;
    if (value == 'false') return false;
  }
  return value;
}
