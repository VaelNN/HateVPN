import 'dart:collection';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../config/consts.dart';
import '../models/parser_config.dart';
import 'app_log.dart';
import 'builder/if_engine.dart' show TemplateIfError, validateCondNode, validateIfConstructs;
import 'l10n/locale_controller.dart';
import 'l10n/template_overlay.dart';








class TemplateLoader {
  TemplateLoader._();

  static final Map<String, WizardTemplate> _cache = {};

  static WizardTemplate? cachedOrNull([String? tag]) =>
      _cache[tag ?? LocaleController.I.effectiveTag];

  static Future<WizardTemplate> load() {


    final tag = LocaleController.I.effectiveTag;
    final hit = _cache[tag];
    if (hit != null) return Future.value(hit);
    return _loadFor(tag);
  }



  static Future<void> reload(String tag) async {
    if (_cache.containsKey(tag)) return;
    await _loadFor(tag);
  }


  static void invalidate() => _cache.clear();

  static Future<WizardTemplate> _loadFor(String tag) async {
    final raw = await rootBundle.loadString('assets/wizard_template.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;





    if (tag != 'en') {
      try {
        final ovRaw =
            await rootBundle.loadString('assets/l10n/$tag/template.json');
        final overlay = TemplateOverlay.parseLocaleFile(
            jsonDecode(ovRaw) as Map<String, dynamic>);
        TemplateOverlay.apply(json, overlay);
      } catch (e) {
        AppLog.I.error('l10n: template overlay "$tag" failed to load: $e');
        assert(false, 'l10n: template overlay "$tag" failed to load: $e');
      }
    }

    var template = WizardTemplate.fromJson(json);










    final dropped = validateTemplateConstructs(json, template);
    if (dropped.isNotEmpty) {


      template = WizardTemplate.fromJson(json);
    }




    assertMagicNodeMirrors(template.groupTemplates);

    _cache[tag] = template;
    return template;
  }
}




























List<String> validateTemplateConstructs(
  Map<String, dynamic> raw,
  WizardTemplate template,
) {
  final globals = <String, WizardVar>{
    for (final v in template.vars) v.name: v,
  };

  validateIfConstructs(raw['config'], globals, path: 'config');



  for (final s in (raw['sections'] as List? ?? const [])
      .whereType<Map<String, dynamic>>()) {
    final name = s['name'] as String? ?? '';
    for (final v in (s['vars'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()) {
      _validateOnChange(v, globals, 'sections[$name].vars[${v['name']}]');
    }
  }

  _validateDnsServerPlaceholders(raw);

  final rules = raw['selectable_rules'] as List? ?? const [];
  final dropped = <String>[];
  final toRemove = <Map<String, dynamic>>[];
  for (var i = 0; i < rules.length; i++) {
    final r = rules[i];
    if (r is! Map<String, dynamic>) continue;
    final id = (r['preset_id'] as String?) ?? '$i';
    var scope = _presetScope(r, globals);


    if (r.containsKey('for_each')) {
      final fe = PresetForEach.fromJson(r['for_each']);
      if (fe == null) {



        AppLog.I.warning(
            'template: selectable_rules[$id].for_each missing required '
            '`node_type`/`as` — preset dropped, rest of the template loads');
        dropped.add(id);
        toRemove.add(r);
        continue;
      }
      scope = _ForEachScope(scope, fe.as);
      final filter = fe.filter;
      if (filter != null) {
        validateCondNode(filter, scope, 'selectable_rules[$id].for_each.filter');
      }
    }
    for (final key in const ['rule', 'rules', 'rule_set', 'dns_rules']) {
      if (!r.containsKey(key)) continue;
      validateIfConstructs(r[key], scope,
          path: 'selectable_rules[$id].$key');
    }
    for (final v in (r['vars'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()) {
      _validateOnChange(
          v, scope, 'selectable_rules[$id].vars[${v['name'] ?? v['ref']}]');
    }
  }
  for (final r in toRemove) {
    rules.remove(r);
  }
  return dropped;
}














void _validateDnsServerPlaceholders(Map<String, dynamic> raw) {
  final dnsOptions = raw['dns_options'];
  if (dnsOptions is! Map<String, dynamic>) return;
  final servers = dnsOptions['servers'] as List? ?? const [];
  for (var i = 0; i < servers.length; i++) {
    final entry = servers[i];
    if (entry is! Map<String, dynamic>) continue;
    final server = entry['server'];
    if (server is! Map<String, dynamic>) continue;
    final tag = server['tag'] as String? ?? '$i';
    final scope = <String, WizardVar>{
      for (final v in (entry['vars'] as List? ?? const [])
          .whereType<Map<String, dynamic>>())
        if ((v['name'] as String? ?? '').isNotEmpty)
          v['name'] as String: WizardVar.fromJson(v),
    };
    final path = 'dns_options.servers[$tag].server';
    validateIfConstructs(server, scope, path: path);
    for (final name in _placeholderNames(server)) {
      if (!scope.containsKey(name)) {
        throw TemplateIfError('$path: `@$name` is not declared in the vars of '
            'DNS server "$tag" (SPEC 129 Н11)');
      }
    }
  }
}



Set<String> _placeholderNames(dynamic node, [Set<String>? out]) {
  final names = out ?? <String>{};
  if (node is String) {
    if (node.startsWith('@')) {
      final name = node.substring(1);
      if (name.isNotEmpty && !name.contains('@')) names.add(name);
    }
  } else if (node is Map) {
    for (final v in node.values) {
      _placeholderNames(v, names);
    }
  } else if (node is List) {
    for (final v in node) {
      _placeholderNames(v, names);
    }
  }
  return names;
}




Map<String, WizardVar> _presetScope(
  Map<String, dynamic> rule,
  Map<String, WizardVar> globals,
) {
  final scope = Map<String, WizardVar>.from(globals);
  for (final v in (rule['vars'] as List? ?? const [])
      .whereType<Map<String, dynamic>>()) {
    final ref = v['ref'] as String? ?? '';
    if (ref.isNotEmpty) continue;
    final name = v['name'] as String? ?? '';
    if (name.isEmpty) continue;
    scope[name] = WizardVar.fromJson(v);
  }
  return scope;
}





class _ForEachScope extends MapBase<String, WizardVar> {
  _ForEachScope(this._base, this._as);

  final Map<String, WizardVar> _base;
  final String _as;

  @override
  WizardVar? operator [](Object? key) {
    final own = _base[key];
    if (own != null || key is! String) return own;
    if (key == _as || key.startsWith('$_as.body.')) {
      return WizardVar(name: key, type: 'text', defaultValue: '');
    }
    if (key == '$_as.skip_presets') {
      return WizardVar(name: key, type: 'bool', defaultValue: '');
    }
    return null;
  }

  @override
  void operator []=(String key, WizardVar value) => _base[key] = value;

  @override
  void clear() => _base.clear();

  @override
  Iterable<String> get keys => _base.keys;

  @override
  WizardVar? remove(Object? key) => _base.remove(key);
}



void _validateOnChange(
  Map<String, dynamic> varJson,
  Map<String, WizardVar> scope,
  String path,
) {
  final oc = varJson['#on_change'] ?? varJson['on_change'];
  if (oc is! Map<String, dynamic>) return;
  final set = oc['#set'] ?? oc['set'];
  if (set is! Map<String, dynamic>) return;
  set.forEach((target, node) {
    validateIfConstructs(node, scope, path: '$path.#on_change.#set[$target]');
  });
}









void assertMagicNodeMirrors(GroupTemplates gt) {
  final direct = gt.magicNodes['direct']?.tag;
  final block = gt.magicNodes['block']?.tag;
  if (direct != kDirectOutboundTag || block != kBlockOutboundTag) {
    throw StateError(
        'magic_nodes tag mismatch with consts.dart mirror — update consts.dart');
  }
}
