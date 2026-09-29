part of '../settings_storage.dart';











Future<String> _getRouteFinal() async {
  final data = await _load();
  return (data['route_final'] as String?) ?? '';
}

Future<void> _saveRouteFinal(String outbound, {bool flush = true}) async {
  final data = await _load();
  data['route_final'] = outbound;
  SettingsStorage._cache = data;
  SettingsStorage.markConfigDirty();
  if (flush) await _save();
}









Future<String> _getIdleSuspend() async {
  final data = await _load();
  return (data['route_idle_suspend'] as String?) ?? '30s';
}

Future<void> _saveIdleSuspend(String threshold, {bool flush = true}) async {
  final data = await _load();
  data['route_idle_suspend'] = threshold;
  SettingsStorage._cache = data;
  SettingsStorage.markConfigDirty();
  if (flush) await _save();
}
















Future<String> _getIdleSuspendReachable() async {
  final data = await _load();
  return (data['route_idle_suspend_reachable'] as String?) ?? '5m';
}

Future<void> _saveIdleSuspendReachable(String threshold,
    {bool flush = true}) async {
  final data = await _load();
  data['route_idle_suspend_reachable'] = threshold;
  SettingsStorage._cache = data;
  SettingsStorage.markConfigDirty();
  if (flush) await _save();
}















const int kWgBuildMaxDefault = 5;

Future<int> _getWgBuildMax() async {
  final data = await _load();
  final v = data['wg_build_max'];
  return (v is int && v >= 0) ? v : kWgBuildMaxDefault;
}

Future<void> _saveWgBuildMax(int value, {bool flush = true}) async {
  final data = await _load();
  data['wg_build_max'] = value;
  SettingsStorage._cache = data;
  SettingsStorage.markConfigDirty();
  if (flush) await _save();
}

Future<bool> _getWgLazyBuild() async {
  final data = await _load();
  return (data['wg_lazy_build'] as bool?) ?? true;
}

Future<void> _saveWgLazyBuild(bool enabled, {bool flush = true}) async {
  final data = await _load();
  data['wg_lazy_build'] = enabled;
  SettingsStorage._cache = data;
  SettingsStorage.markConfigDirty();
  if (flush) await _save();
}











Future<bool> _getPassiveCheck() async {
  final data = await _load();
  return (data['urltest_passive_check'] as bool?) ?? true;
}

Future<void> _savePassiveCheck(bool enabled, {bool flush = true}) async {
  final data = await _load();
  data['urltest_passive_check'] = enabled;
  SettingsStorage._cache = data;
  SettingsStorage.markConfigDirty();
  if (flush) await _save();
}
















List<dynamic> _dnsList(Map<String, dynamic> data, String key) {
  final dns = data[kDnsKey];
  if (dns is! Map) return const [];
  final list = dns[key];
  return list is List ? list : const [];
}

List<T> _parseDnsEntries<T>(
  List<dynamic> stored,
  T? Function(Map<String, dynamic>) parse,
) =>
    [
      for (final e in stored)
        if (e is Map)
          if (parse(e.cast<String, dynamic>()) case final T m) m,
    ];


List<dynamic> _mergeDnsEntries<T>(
  List<dynamic> stored,
  List<T> models,
  T? Function(Map<String, dynamic>) parse,
  Map<String, dynamic> Function(T) encode,
) {
  final parsed = [
    for (final e in stored) e is Map ? parse(e.cast<String, dynamic>()) : null,
  ];
  final used = List<bool>.filled(stored.length, false);
  final out = <dynamic>[];
  for (final m in models) {
    var reuse = -1;
    for (var i = 0; i < stored.length; i++) {
      if (!used[i] && parsed[i] != null && parsed[i] == m) {
        reuse = i;
        break;
      }
    }
    if (reuse >= 0) {
      used[reuse] = true;
      out.add(stored[reuse]);
    } else {
      out.add(encode(m));
    }
  }
  for (var i = 0; i < stored.length; i++) {
    if (parsed[i] != null) continue;
    out.insert(i < out.length ? i : out.length, stored[i]);
  }
  return out;
}

Future<void> _putDnsList(String key, List<dynamic> list,
    {required bool flush}) async {
  final data = await _load();
  final dns = data[kDnsKey];
  data[kDnsKey] = <String, dynamic>{
    if (dns is Map) ...dns.cast<String, dynamic>(),
    key: list,
  };
  SettingsStorage._cache = data;
  SettingsStorage.markConfigDirty();
  if (flush) await _save();
}

DnsServerRef? _dnsServerOf(Map<String, dynamic> j) =>
    dnsServerFromRecord(j).value;

DnsRuleRef? _dnsRuleOf(Map<String, dynamic> j) => dnsRuleFromRecord(j).value;

Future<List<DnsServerRef>> _getDnsServers() async =>
    _parseDnsEntries(_dnsList(await _load(), kDnsServersKey), _dnsServerOf);





Future<void> _saveDnsServers(List<DnsServerRef> servers,
    {bool flush = true}) async {
  final normalized =
      normalizeDnsServersVars(servers, await loadRecordVarDecls());
  final stored = _dnsList(await _load(), kDnsServersKey);
  await _putDnsList(
    kDnsServersKey,
    _mergeDnsEntries(stored, normalized, _dnsServerOf, dnsServerToRecord),
    flush: flush,
  );
}

Future<List<DnsRuleRef>> _getDnsRulesList() async =>
    _parseDnsEntries(_dnsList(await _load(), kDnsRulesKey), _dnsRuleOf);

Future<void> _saveDnsRulesList(List<DnsRuleRef> rules,
    {bool flush = true}) async {
  final stored = _dnsList(await _load(), kDnsRulesKey);
  await _putDnsList(
    kDnsRulesKey,
    _mergeDnsEntries(stored, rules, _dnsRuleOf, dnsRuleToRecord),
    flush: flush,
  );
}










Future<Map<String, dynamic>> _getPingOptions() async {
  final data = await _load();
  final raw = data['ping_options'];
  if (raw is Map<String, dynamic>) {
    return Map<String, dynamic>.from(raw);
  }
  return <String, dynamic>{};
}

Future<void> _savePingOptions(Map<String, dynamic> options) async {
  final data = await _load();
  data['ping_options'] = options;
  SettingsStorage._cache = data;
  await _save();
}

Future<void> _setGlobalPingUrl(String url) async {
  final opts = await SettingsStorage.getPingOptions();
  opts['url'] = url;
  await SettingsStorage.savePingOptions(opts);
}

Future<void> _setGlobalPingTimeout(int timeoutMs) async {
  final opts = await SettingsStorage.getPingOptions();
  opts['timeout_ms'] = timeoutMs;
  await SettingsStorage.savePingOptions(opts);
}

Future<void> _setGroupPing(
  String groupTag, {
  String? url,
  int? timeoutMs,
}) async {
  if (groupTag.isEmpty) return;
  final opts = await SettingsStorage.getPingOptions();
  final groups = (opts['groups'] is Map<String, dynamic>)
      ? Map<String, dynamic>.from(opts['groups'] as Map<String, dynamic>)
      : <String, dynamic>{};
  final existing = (groups[groupTag] is Map<String, dynamic>)
      ? Map<String, dynamic>.from(groups[groupTag] as Map<String, dynamic>)
      : <String, dynamic>{};
  if (url != null) existing['url'] = url;
  if (timeoutMs != null) existing['timeout_ms'] = timeoutMs;
  groups[groupTag] = existing;
  opts['groups'] = groups;
  await SettingsStorage.savePingOptions(opts);
}

Future<void> _clearGroupPing(String groupTag) async {
  if (groupTag.isEmpty) return;
  final opts = await SettingsStorage.getPingOptions();
  if (!_dropPingGroupKeys(opts, (t) => t == groupTag)) return;
  await SettingsStorage.savePingOptions(opts);
}










bool _dropPingGroupKeys(
  Map<String, dynamic> opts,
  bool Function(String tag) doomed,
) {
  final groups = opts['groups'];
  if (groups is! Map<String, dynamic>) return false;
  final doomedKeys = groups.keys.where(doomed).toList();
  if (doomedKeys.isEmpty) return false;
  for (final k in doomedKeys) {
    groups.remove(k);
  }
  if (groups.isEmpty) {
    opts.remove('groups');
  } else {
    opts['groups'] = groups;
  }
  return true;
}
