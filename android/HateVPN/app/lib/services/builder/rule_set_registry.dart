import '../json_clone.dart';












class RuleSetRegistry {
  RuleSetRegistry({
    List<dynamic> initialRuleSets = const [],
    List<dynamic> initialRules = const [],
  }) {
    for (final e in initialRuleSets) {
      if (e is Map<String, dynamic>) _addExisting(e);
    }
    for (final r in initialRules) {
      if (r is Map<String, dynamic>) _rules.add(r);
    }
  }

  final List<Map<String, dynamic>> _ruleSets = [];
  final Set<String> _takenTags = {};
  final List<Map<String, dynamic>> _rules = [];




  String addRuleSet(Map<String, dynamic> entry) {
    final copy = Map<String, dynamic>.from(entry);
    final requested = (copy['tag'] as String?)?.trim() ?? '';
    final base = requested.isEmpty ? 'unnamed' : requested;
    final tag = _allocateTag(base);
    copy['tag'] = tag;
    _ruleSets.add(copy);
    _takenTags.add(tag);
    return tag;
  }











  bool tryRegisterRuleSet(Map<String, dynamic> entry) {
    final copy = Map<String, dynamic>.from(entry);
    final tag = (copy['tag'] as String?)?.trim() ?? '';
    if (tag.isEmpty) {
      _ruleSets.add(copy);
      return false;
    }
    if (!_takenTags.contains(tag)) {
      _ruleSets.add(copy);
      _takenTags.add(tag);
      return false;
    }
    final existing = _ruleSets.firstWhere(
      (r) => r['tag'] == tag,
      orElse: () => const <String, dynamic>{},
    );
    return !deepEqualsJson(existing, copy);
  }



  void addRule(Map<String, dynamic> rule) {
    _rules.add(Map<String, dynamic>.from(rule));
  }


  List<Map<String, dynamic>> getRuleSets() => List.unmodifiable(_ruleSets);


  List<Map<String, dynamic>> getRules() => List.unmodifiable(_rules);






  void _addExisting(Map<String, dynamic> e) {
    final copy = Map<String, dynamic>.from(e);
    final requested = (copy['tag'] as String?)?.trim() ?? '';
    final base = requested.isEmpty ? 'unnamed' : requested;
    final tag = _allocateTag(base);
    copy['tag'] = tag;
    _ruleSets.add(copy);
    _takenTags.add(tag);
  }

  String _allocateTag(String base) {
    if (!_takenTags.contains(base)) return base;
    var i = 2;
    while (_takenTags.contains('$base ($i)')) {
      i++;
    }
    return '$base ($i)';
  }
}

