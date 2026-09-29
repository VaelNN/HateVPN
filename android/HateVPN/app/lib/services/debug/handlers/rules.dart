import '../../../config/consts.dart' show kDirectOutboundTag;
import '../../../models/custom_rule.dart';
import '../../../models/parser_config.dart' show kUserRuleNumStart;
import '../../builder/rule_order.dart';
import '../../settings_storage.dart';
import '../../template_loader.dart';
import '../context.dart';
import '../contract/errors.dart';
import '../serializers/rules.dart';
import '../transport/request.dart';
import '../transport/response.dart';
import '_shared.dart';




CustomRule ruleFromJsonStrictForTest(Map<String, dynamic> j) =>
    _ruleFromJsonStrict(j);


















Future<DebugResponse> rulesHandler(DebugRequest req, DebugContext ctx) async {
  final path = req.path;

  if (path == '/rules') {
    return switch (req.method) {
      'GET' => _list(),
      'POST' => _create(req, ctx),
      _ => throw BadRequest('method ${req.method} not allowed on /rules'),
    };
  }

  if (path == '/rules/reorder') {
    if (req.method != 'POST') {
      throw BadRequest('reorder requires POST, got ${req.method}');
    }
    return _reorder(req);
  }


  if (path == '/rules/move') {
    if (req.method != 'POST') {
      throw BadRequest('move requires POST, got ${req.method}');
    }
    return _move(req);
  }

  if (path.startsWith('/rules/')) {
    final id = path.substring('/rules/'.length);
    if (id.isEmpty || id.contains('/')) {
      throw NotFound('rule path: $path');
    }
    return switch (req.method) {
      'GET' => _single(id),
      'PATCH' => _update(id, req, ctx),
      'DELETE' => _delete(id, req, ctx),
      _ => throw BadRequest('method ${req.method} not allowed on /rules/{id}'),
    };
  }

  throw NotFound('rules path: $path');
}

Future<DebugResponse> _list() async {
  final rules = await SettingsStorage.getCustomRules();
  final serialized = await Future.wait(rules.map(serializeCustomRule));
  return JsonResponse(serialized);
}

Future<DebugResponse> _single(String id) async {
  final rules = await SettingsStorage.getCustomRules();
  for (final r in rules) {
    if (r.id == id) {
      return JsonResponse(await serializeCustomRule(r));
    }
  }
  throw NotFound('rule: $id');
}

Future<DebugResponse> _create(DebugRequest req, DebugContext ctx) async {
  final body = req.jsonBodyAsMap();

  final stripped = Map<String, dynamic>.from(body)..remove('id');
  final rule = _ruleFromJsonStrict(stripped);
  final rules = await SettingsStorage.getCustomRules();



  rule.orderNum ??= rule.kind == CustomRuleKind.preset
      ? (await _templateNumFor(rule.presetId)) ?? nextUserRuleNum(rules)
      : nextUserRuleNum(rules);
  rules.add(rule);
  await SettingsStorage.saveCustomRules(sortRulesByNum(rules));
  final extras = await maybeRebuild(req, ctx);
  final serialized = await serializeCustomRule(rule);
  return JsonResponse({...serialized, ...extras}, status: 201);
}

Future<DebugResponse> _update(
  String id,
  DebugRequest req,
  DebugContext ctx,
) async {
  final body = req.jsonBodyAsMap();
  final rules = await SettingsStorage.getCustomRules();
  final idx = rules.indexWhere((r) => r.id == id);
  if (idx < 0) throw NotFound('rule: $id');
  final updated = _patchRule(rules[idx], body);
  rules[idx] = updated;
  await SettingsStorage.saveCustomRules(rules);
  final extras = await maybeRebuild(req, ctx);
  final serialized = await serializeCustomRule(updated);
  return JsonResponse({...serialized, ...extras});
}











CustomRule _patchRule(CustomRule current, Map<String, dynamic> body) {
  final name = fieldString(body, 'name');
  final enabled = fieldBool(body, 'enabled');
  final kind = _fieldKind(body, 'kind') ?? current.kind;
  final domains = fieldStringList(body, 'domains');
  final domainSuffixes = fieldStringList(body, 'domain_suffixes');
  final domainKeywords = fieldStringList(body, 'domain_keywords');
  final ipCidrs = fieldStringList(body, 'ip_cidrs');
  final ports = fieldStringList(body, 'ports');
  final portRanges = fieldStringList(body, 'port_ranges');
  final packages = fieldStringList(body, 'packages');
  final protocols = fieldStringList(body, 'protocols');

  final network = fieldStringList(body, 'network');
  final ipIsPrivate = fieldBool(body, 'ip_is_private');

  final sourceIpCidrs = fieldStringList(body, 'source_ip_cidrs');
  final sourceIpIsPrivate = fieldBool(body, 'source_ip_is_private');
  final inbounds = fieldStringList(body, 'inbounds');


  final wifiSsids = fieldStringList(body, 'wifi_ssids');
  final rawBssids = fieldStringList(body, 'wifi_bssids');
  final wifiBssids = rawBssids == null ? null : _validateBssids(rawBssids);


  final srsUrlList = fieldStringList(body, 'srs_urls');
  final srsUrl = fieldString(body, 'srs_url');
  final srsUrls = srsUrlList ?? (srsUrl == null ? null : [srsUrl]);
  final outbound = fieldString(body, 'outbound');

  final presetId = fieldString(body, 'preset_id');
  final varsValues = fieldStringMap(body, 'vars_values');

  final clearDns = body.containsKey('dns') && body['dns'] == null;
  final dns = clearDns ? null : _fieldRuleDns(body, 'dns');

  final clearResolve = body.containsKey('resolve') && body['resolve'] == null;
  final resolve = clearResolve ? null : _fieldRuleResolve(body, 'resolve');

  return switch (_retype(current, kind)) {
    final CustomRuleInline r => r.copyWith(
        name: name,
        enabled: enabled,
        domains: domains,
        domainSuffixes: domainSuffixes,
        domainKeywords: domainKeywords,
        ipCidrs: ipCidrs,
        ports: ports,
        portRanges: portRanges,
        packages: packages,
        protocols: protocols,
        network: network,
        ipIsPrivate: ipIsPrivate,
        sourceIpCidrs: sourceIpCidrs,
        sourceIpIsPrivate: sourceIpIsPrivate,
        inbounds: inbounds,
        wifiSsids: wifiSsids,
        wifiBssids: wifiBssids,
        outbound: outbound,
        dns: dns,
        clearDns: clearDns,
        resolve: resolve,
        clearResolve: clearResolve,
      ),
    final CustomRuleSrs r => r.copyWith(
        name: name,
        enabled: enabled,
        srsUrls: srsUrls,
        ports: ports,
        portRanges: portRanges,
        packages: packages,
        protocols: protocols,
        network: network,
        ipIsPrivate: ipIsPrivate,
        sourceIpCidrs: sourceIpCidrs,
        sourceIpIsPrivate: sourceIpIsPrivate,
        inbounds: inbounds,
        wifiSsids: wifiSsids,
        wifiBssids: wifiBssids,
        outbound: outbound,
        dns: dns,
        clearDns: clearDns,
        resolve: resolve,
        clearResolve: clearResolve,
      ),
    final CustomRulePreset r => r.copyWith(
        name: name,
        enabled: enabled,
        presetId: presetId,
        varsValues: varsValues,
      ),
    final CustomRuleJson r => r.copyWith(name: name, enabled: enabled),
  };
}







CustomRule _retype(CustomRule r, CustomRuleKind kind) {
  if (r.kind == kind) return r;
  final outbound = switch (r) {
    CustomRuleInline(:final outbound) || CustomRuleSrs(:final outbound) =>
      outbound,
    _ => kDirectOutboundTag,
  };
  return switch (kind) {
    CustomRuleKind.inline => CustomRuleInline(
        id: r.id,
        name: r.name,
        enabled: r.enabled,
        orderNum: r.orderNum,
        domains: r.domains,
        domainSuffixes: r.domainSuffixes,
        domainKeywords: r.domainKeywords,
        ipCidrs: r.ipCidrs,
        ports: r.ports,
        portRanges: r.portRanges,
        packages: r.packages,
        protocols: r.protocols,
        network: r.network,
        ipIsPrivate: r.ipIsPrivate,
        sourceIpCidrs: r.sourceIpCidrs,
        sourceIpIsPrivate: r.sourceIpIsPrivate,
        inbounds: r.inbounds,
        wifiSsids: r.wifiSsids,
        wifiBssids: r.wifiBssids,
        outbound: outbound,
        dns: r.dns,
        resolve: r.resolve,
      ),
    CustomRuleKind.srs => CustomRuleSrs(
        id: r.id,
        name: r.name,
        enabled: r.enabled,
        orderNum: r.orderNum,
        srsUrls: r.srsUrls,
        ports: r.ports,
        portRanges: r.portRanges,
        packages: r.packages,
        protocols: r.protocols,
        network: r.network,
        ipIsPrivate: r.ipIsPrivate,
        sourceIpCidrs: r.sourceIpCidrs,
        sourceIpIsPrivate: r.sourceIpIsPrivate,
        inbounds: r.inbounds,
        wifiSsids: r.wifiSsids,
        wifiBssids: r.wifiBssids,
        outbound: outbound,
        dns: r.dns,
        resolve: r.resolve,
      ),
    CustomRuleKind.preset => CustomRulePreset(
        id: r.id,
        name: r.name,
        enabled: r.enabled,
        orderNum: r.orderNum,
        presetId: r.presetId,
        varsValues: r.varsValues,
      ),
    CustomRuleKind.json => CustomRuleJson(
        id: r.id,
        name: r.name,
        enabled: r.enabled,
        orderNum: r.orderNum,
        json: r.json,
      ),
  };
}

Future<DebugResponse> _delete(
  String id,
  DebugRequest req,
  DebugContext ctx,
) async {
  final rules = await SettingsStorage.getCustomRules();
  final idx = rules.indexWhere((r) => r.id == id);
  if (idx < 0) throw NotFound('rule: $id');
  rules.removeAt(idx);
  await SettingsStorage.saveCustomRules(rules);
  final extras = await maybeRebuild(req, ctx);
  return JsonResponse({
    'ok': true,
    'action': 'rules-delete',
    'id': id,
    ...extras,
  });
}

Future<DebugResponse> _reorder(DebugRequest req) async {
  final body = req.jsonBodyAsMap();
  final order = fieldStringList(body, 'order');
  if (order == null) {
    throw const BadRequest('body must contain "order": [id, ...]');
  }
  final rules = await SettingsStorage.getCustomRules();
  if (order.length != rules.length) {
    throw BadRequest(
      'order length ${order.length} != current rule count ${rules.length}',
    );
  }
  final byId = {for (final r in rules) r.id: r};
  final missing = byId.keys.toSet().difference(order.toSet());
  final extra = order.toSet().difference(byId.keys.toSet());
  if (missing.isNotEmpty || extra.isNotEmpty) {
    throw BadRequest(
      'order must contain exactly the current rule IDs '
      '(missing: $missing, extra: $extra)',
    );
  }
  final reordered = order.map((id) => byId[id]!).toList();




  final sortable = await _sortablePredicate();
  var cursor = kUserRuleNumStart;
  for (final r in reordered) {
    if (!sortable(r)) continue;
    cursor++;
    r.orderNum = cursor;
  }
  final result = sortRulesByNum(reordered);
  if (!_sameIds(result, reordered)) {
    throw const BadRequest(
      'requested order conflicts with pinned rules (isSortable:false must '
      'keep their template position)',
    );
  }
  await SettingsStorage.saveCustomRules(result);
  return JsonResponse({
    'ok': true,
    'action': 'rules-reorder',
    'count': result.length,
    'nums': {for (final r in result) r.id: r.orderNum},
  });
}









Future<DebugResponse> _move(DebugRequest req) async {
  final body = req.jsonBodyAsMap();
  final id = fieldString(body, 'id');
  if (id == null || id.isEmpty) {
    throw const BadRequest('body must contain "id": "<rule uuid>"');
  }
  if (!body.containsKey('after')) {
    throw const BadRequest('body must contain "after": "<rule uuid>" or null');
  }
  final afterRaw = body['after'];
  if (afterRaw != null && afterRaw is! String) {
    throw const BadRequest('field "after" must be string or null');
  }

  final rules = await SettingsStorage.getCustomRules();
  final moved = rules.where((r) => r.id == id).firstOrNull;
  if (moved == null) throw NotFound('rule: $id');

  CustomRule? target;
  if (afterRaw is String) {
    target = rules.where((r) => r.id == afterRaw).firstOrNull;
    if (target == null) throw NotFound('rule (after): $afterRaw');
    if (identical(target, moved)) {
      throw const BadRequest('"after" must differ from "id"');
    }
  }

  final sortable = await _sortablePredicate();
  if (!sortable(moved)) {
    throw const BadRequest('rule is not sortable (isSortable:false)');
  }


  final template = await TemplateLoader.load();
  markRuleOrder(rules, template.selectableRules);

  placeRuleAfter(rules, moved, target, isSortable: sortable);
  final result = sortRulesByNum(rules);
  await SettingsStorage.saveCustomRules(result);
  return JsonResponse({
    'ok': true,
    'action': 'rules-move',
    'id': id,
    'after': afterRaw,
    'num': moved.orderNum,
    'order': [
      for (final r in result)
        {'id': r.id, 'name': r.name, 'preset_id': r.presetId, 'num': r.orderNum}
    ],
  });
}



Future<bool Function(CustomRule)> _sortablePredicate() async {
  final template = await TemplateLoader.load();
  final byId = {for (final sr in template.selectableRules) sr.presetId: sr};
  return (CustomRule r) {
    if (r.kind != CustomRuleKind.preset) return true;
    return byId[r.presetId]?.isSortable ?? true;
  };
}


Future<int?> _templateNumFor(String presetId) async {
  if (presetId.isEmpty) return null;
  final template = await TemplateLoader.load();
  for (final sr in template.selectableRules) {
    if (sr.presetId == presetId) return sr.num;
  }
  return null;
}

bool _sameIds(List<CustomRule> a, List<CustomRule> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].id != b[i].id) return false;
  }
  return true;
}

CustomRuleKind? _fieldKind(Map<String, dynamic> m, String key) {
  if (!m.containsKey(key)) return null;
  final v = m[key];
  if (v is! String) throw BadRequest('field "$key" must be string');
  for (final k in CustomRuleKind.values) {
    if (k.name == v) return k;
  }
  throw BadRequest('unknown kind: $v (expected inline|srs|preset|json)');
}



CustomRule _ruleFromJsonStrict(Map<String, dynamic> j) {
  final name = fieldString(j, 'name') ?? '';
  if (name.trim().isEmpty) throw const BadRequest('field "name" required');
  final kind = _fieldKind(j, 'kind') ?? CustomRuleKind.inline;
  final enabled = fieldBool(j, 'enabled') ?? true;
  final outbound = fieldString(j, 'outbound') ?? kDirectOutboundTag;



  final wifiSsids = fieldStringList(j, 'wifi_ssids') ?? const [];
  final wifiBssidsRaw = fieldStringList(j, 'wifi_bssids') ?? const [];
  final wifiBssids = _validateBssids(wifiBssidsRaw);

  final sourceIpCidrs = fieldStringList(j, 'source_ip_cidrs') ?? const [];
  final sourceIpIsPrivate = fieldBool(j, 'source_ip_is_private') ?? false;
  final inbounds = fieldStringList(j, 'inbounds') ?? const [];

  final dns = _fieldRuleDns(j, 'dns');

  final resolve = _fieldRuleResolve(j, 'resolve');

  switch (kind) {
    case CustomRuleKind.inline:
      return CustomRuleInline(
        name: name,
        enabled: enabled,
        domains: fieldStringList(j, 'domains') ?? const [],
        domainSuffixes: fieldStringList(j, 'domain_suffixes') ?? const [],
        domainKeywords: fieldStringList(j, 'domain_keywords') ?? const [],
        ipCidrs: fieldStringList(j, 'ip_cidrs') ?? const [],
        ports: fieldStringList(j, 'ports') ?? const [],
        portRanges: fieldStringList(j, 'port_ranges') ?? const [],
        packages: fieldStringList(j, 'packages') ?? const [],
        protocols: fieldStringList(j, 'protocols') ?? const [],
        network: fieldStringList(j, 'network') ?? const [],
        ipIsPrivate: fieldBool(j, 'ip_is_private') ?? false,
        sourceIpCidrs: sourceIpCidrs,
        sourceIpIsPrivate: sourceIpIsPrivate,
        inbounds: inbounds,
        wifiSsids: wifiSsids,
        wifiBssids: wifiBssids,
        outbound: outbound,
        dns: dns,
        resolve: resolve,
      );
    case CustomRuleKind.srs:
      return CustomRuleSrs(
        name: name,
        enabled: enabled,
        srsUrl: fieldString(j, 'srs_url') ?? '',
        srsUrls: fieldStringList(j, 'srs_urls') ?? const [],
        ports: fieldStringList(j, 'ports') ?? const [],
        portRanges: fieldStringList(j, 'port_ranges') ?? const [],
        packages: fieldStringList(j, 'packages') ?? const [],
        protocols: fieldStringList(j, 'protocols') ?? const [],
        network: fieldStringList(j, 'network') ?? const [],
        ipIsPrivate: fieldBool(j, 'ip_is_private') ?? false,
        sourceIpCidrs: sourceIpCidrs,
        sourceIpIsPrivate: sourceIpIsPrivate,
        inbounds: inbounds,
        wifiSsids: wifiSsids,
        wifiBssids: wifiBssids,
        outbound: outbound,
        dns: dns,
        resolve: resolve,
      );
    case CustomRuleKind.preset:
      final presetId = fieldString(j, 'preset_id') ?? '';
      if (presetId.isEmpty) {
        throw const BadRequest('field "preset_id" required for preset rules');
      }
      return CustomRulePreset(
        name: name,
        enabled: enabled,
        presetId: presetId,
        varsValues: fieldStringMap(j, 'vars_values'),
      );
    case CustomRuleKind.json:

      final body = fieldString(j, 'json') ?? '';
      if (body.trim().isEmpty) {
        throw const BadRequest('field "json" required for json rules');
      }
      return CustomRuleJson(name: name, enabled: enabled, json: body);
  }
}










RuleDns? _fieldRuleDns(Map<String, dynamic> m, String key) {
  if (!m.containsKey(key)) return null;
  final v = m[key];
  if (v is! Map) throw BadRequest('field "$key" must be object');
  final enabledRaw = v['enabled'];
  if (enabledRaw != null && enabledRaw is! bool) {
    throw BadRequest('field "$key.enabled" must be bool');
  }
  final enabled = enabledRaw == true;
  final forceRaw = v['force_ipv4'];
  if (forceRaw != null && forceRaw is! bool) {
    throw BadRequest('field "$key.force_ipv4" must be bool');
  }
  final forceIpv4 = forceRaw == true;
  final tagRaw = v['server_tag'];
  if (tagRaw != null && tagRaw is! String) {
    throw BadRequest('field "$key.server_tag" must be string');
  }
  final tag = (tagRaw as String?) ?? '';
  if (enabled && tag.isEmpty) {
    throw BadRequest(
        'field "$key.server_tag" must be non-empty when enabled is true');
  }
  return RuleDns(enabled: enabled, serverTag: tag, forceIpv4: forceIpv4);
}






RuleResolve? _fieldRuleResolve(Map<String, dynamic> m, String key) {
  if (!m.containsKey(key)) return null;
  final v = m[key];
  if (v is! Map) throw BadRequest('field "$key" must be object');
  const strategies = {'prefer_ipv4', 'prefer_ipv6', 'ipv4_only', 'ipv6_only'};
  final strategy = v['strategy']?.toString() ?? '';
  if (strategy.isNotEmpty && !strategies.contains(strategy)) {
    throw BadRequest(
        'field "$key.strategy" must be one of ${strategies.join('/')}');
  }


  bool strictBool(String name) {
    final raw = v[name];
    if (raw == null) return false;
    if (raw is! bool) throw BadRequest('field "$key.$name" must be bool');
    return raw;
  }



  final ttlRaw = v['rewrite_ttl'];
  final int? ttl;
  switch (ttlRaw) {
    case null:
      ttl = null;
    case final int n when n >= 0:
      ttl = n;
    case final String s when int.tryParse(s) != null && int.parse(s) >= 0:
      ttl = int.parse(s);
    default:
      throw BadRequest(
          'field "$key.rewrite_ttl" must be non-negative integer');
  }

  final timeout = v['timeout']?.toString() ?? '';
  if (timeout.isNotEmpty && !RegExp(r'^\d+(ms|s|m|h)$').hasMatch(timeout)) {
    throw BadRequest('field "$key.timeout" must be duration (e.g. "5s")');
  }


  final subnet = v['client_subnet']?.toString() ?? '';
  if (subnet.isNotEmpty && !_clientSubnetPattern.hasMatch(subnet)) {
    throw BadRequest(
        'field "$key.client_subnet" must be IP or CIDR (e.g. "1.2.3.0/24")');
  }
  return RuleResolve(
    only: strictBool('only'),
    strategy: strategy,
    serverTag: v['server_tag']?.toString() ?? '',
    disableCache: strictBool('disable_cache'),
    disableOptimisticCache: strictBool('disable_optimistic_cache'),
    rewriteTtl: ttl,
    timeout: timeout,
    clientSubnet: subnet,
  );
}



final RegExp _clientSubnetPattern = RegExp(
    r'^([0-9]{1,3}(\.[0-9]{1,3}){3}|[0-9A-Fa-f:]+:[0-9A-Fa-f:]*)(/\d{1,3})?$');




final RegExp _bssidPattern =
    RegExp(r'^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$');

List<String> _validateBssids(List<String> raw) {
  final out = <String>[];
  for (final b in raw) {
    final trimmed = b.trim();
    if (!_bssidPattern.hasMatch(trimmed)) {
      throw BadRequest(
        'invalid wifi_bssid "$b" (expected xx:xx:xx:xx:xx:xx)',
      );
    }
    out.add(trimmed.toLowerCase());
  }
  return out;
}
