import '../models/custom_rule.dart';
import '../models/parser_config.dart';
import 'rule_display_names.dart';













class RuleNameResolver {
  RuleNameResolver._();
  static final RuleNameResolver I = RuleNameResolver._();



  final Map<String, String> _cache = {};



  final List<({String norm, String title})> _rules = [];



  List<CustomRule> _sourceRules = const [];





  final Map<String, String> _ruleSetTagTitles = {};








  void setRules(List<CustomRule> rules, {WizardTemplate? template}) {
    _sourceRules = List.of(rules);
    _rebuild(template);
  }


  void clear() {
    _cache.clear();
    _rules.clear();
    _ruleSetTagTitles.clear();
    _sourceRules = const [];
  }






  void relocalize(WizardTemplate? template) {
    _rebuild(template);
  }




  void _rebuild(WizardTemplate? template) {
    _rules.clear();
    _ruleSetTagTitles.clear();
    final titles = ruleDisplayNames(_sourceRules, template);
    for (var i = 0; i < _sourceRules.length; i++) {
      final r = _sourceRules[i];
      if (r.kind == CustomRuleKind.preset) {


        final preset = _presetOf(template, r.presetId);
        if (preset != null) {
          for (final rs in preset.ruleSets) {
            final tag = rs['tag'];
            if (tag is String && tag.isNotEmpty) {
              _ruleSetTagTitles.putIfAbsent(tag, () => titles[i]);
            }
          }
        }
        continue;
      }
      final s = _ruleConditionString(r);
      if (s.isEmpty) continue;
      _rules.add((norm: _norm(s), title: titles[i]));
    }
    _cache.clear();
  }

  static SelectableRule? _presetOf(WizardTemplate? template, String presetId) {
    if (template == null || presetId.isEmpty) return null;
    for (final p in template.selectableRules) {
      if (p.presetId == presetId) return p;
    }
    return null;
  }


  String resolve(String coreRule) {
    final cached = _cache[coreRule];
    if (cached != null) return cached;
    final result = _resolve(coreRule);
    _cache[coreRule] = result;
    return result;
  }

  String _resolve(String coreRule) {
    final r = coreRule.trim();
    if (r.isEmpty) return 'final';

    var core = r;
    final arrow = core.indexOf('=>');
    if (arrow >= 0) core = core.substring(0, arrow).trim();
    if (core.isEmpty) return 'final';

    final normCore = _norm(core);

    final probe = _stripTruncation(normCore);

    for (final rule in _rules) {

      if (rule.norm.contains(probe) || normCore.contains(rule.norm)) {
        return rule.title;
      }
    }

    return _fallback(core);
  }




  String _fallback(String core) {
    final rsValue = _kvValue(core, 'rule_set=');
    if (rsValue != null && rsValue.isNotEmpty) {
      String tag;
      if (rsValue.startsWith('[')) {
        var v = rsValue.substring(1);
        if (v.endsWith(']')) v = v.substring(0, v.length - 1);
        tag = _firstToken(v.trim());
      } else {
        tag = rsValue;
      }
      return _ruleSetTagTitles[tag] ?? tag;
    }
    final eq = core.indexOf('=');
    if (eq < 0) return core.isEmpty ? 'final' : _firstToken(core);
    var val = core.substring(eq + 1).trim();
    if (val.startsWith('[')) val = val.substring(1).trim();
    if (val.endsWith(']')) val = val.substring(0, val.length - 1).trim();
    return val.isEmpty ? 'final' : _firstToken(val);
  }






  static String _norm(String s) {
    final out = StringBuffer();
    var prevSpace = false;
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);

      final isWs = c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;
      if (isWs) {
        if (!prevSpace) out.writeCharCode(0x20);
        prevSpace = true;
      } else {
        out.writeCharCode(c);
        prevSpace = false;
      }
    }
    return out.toString().trim();
  }


  static String _stripTruncation(String s) {
    final i = s.indexOf('...');
    return i < 0 ? s : s.substring(0, i).trim();
  }


  static String? _kvValue(String s, String key) {
    final i = s.indexOf(key);
    if (i < 0) return null;
    final rest = s.substring(i + key.length);

    var j = 0;
    while (j < rest.length) {
      if (rest.codeUnitAt(j) == 0x20) {

        var k = j + 1;
        while (k < rest.length && _isIdent(rest.codeUnitAt(k))) {
          k++;
        }
        if (k > j + 1 && k < rest.length && rest.codeUnitAt(k) == 0x3D) {
          return rest.substring(0, j).trim();
        }
      }
      j++;
    }
    return rest.trim();
  }

  static bool _isIdent(int c) =>
      (c >= 0x61 && c <= 0x7A) ||
      (c >= 0x41 && c <= 0x5A) ||
      c == 0x5F;


  static String _firstToken(String s) {
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c == 0x20 || c == 0x2C) return s.substring(0, i);
    }
    return s;
  }





  static String _ruleConditionString(CustomRule r) {
    final parts = <String>[];
    void add(String key, List<String> vals) {
      if (vals.isEmpty) return;
      parts.add(vals.length == 1 ? '$key=${vals.first}' : '$key=[${vals.join(' ')}]');
    }

    add('domain', r.domains);
    add('domain_suffix', r.domainSuffixes);
    add('domain_keyword', r.domainKeywords);
    add('ip_cidr', r.ipCidrs);
    add('package_name', r.packages);
    add('protocol', r.protocols);
    add('wifi_ssid', r.wifiSsids);
    add('wifi_bssid', r.wifiBssids);
    return parts.join(' ');
  }
}
