import '../../../models/background_mode.dart';
import '../../../models/dns_ref.dart';
import '../../../models/record_codec.dart';
import '../../l10n/locale_controller.dart';
import '../../vpn_settings/vpn_settings_facade.dart';
import '../../settings_storage.dart';
import '../context.dart';
import '../contract/errors.dart';
import '../transport/request.dart';
import '../transport/response.dart';
import '_shared.dart';





















Future<DebugResponse> settingsHandler(DebugRequest req, DebugContext ctx) async {
  final path = req.path;

  switch (path) {
    case '/settings/route_final':
      if (req.method != 'PUT') throw _methodNotAllowed(req.method, path);
      return _putRouteFinal(req, ctx);

    case '/settings/interrupt_on_switch':
      if (req.method == 'GET') return _getInterruptOnSwitch();
      if (req.method == 'PUT') return _putInterruptOnSwitch(req);
      throw _methodNotAllowed(req.method, path);

    case '/settings/node_sort':
      if (req.method == 'GET') return _getNodeSort();
      if (req.method == 'PUT') return _putNodeSort(req);
      throw _methodNotAllowed(req.method, path);

    case '/settings/enabled_groups':
      if (req.method == 'GET') return _getEnabledGroups();
      if (req.method == 'PUT') return _putEnabledGroups(req, ctx);
      throw _methodNotAllowed(req.method, path);

    case '/settings/vpn_mode':
      if (req.method == 'GET') return _getVpnMode();
      if (req.method == 'PUT') return _putVpnMode(req, ctx);
      throw _methodNotAllowed(req.method, path);

    case '/settings/dns_options/servers':
      if (req.method != 'PUT') throw _methodNotAllowed(req.method, path);
      return _putDnsServers(req, ctx);

    case '/settings/dns_options/rules':
      if (req.method != 'PUT') throw _methodNotAllowed(req.method, path);
      return _putDnsRules(req, ctx);

    case '/settings/rebuild-config':
      if (req.method != 'POST') throw _methodNotAllowed(req.method, path);
      return _rebuildConfig(ctx);

    case '/settings/config_locked':
      if (req.method != 'PUT') throw _methodNotAllowed(req.method, path);
      return _putConfigLocked(req);

    case '/settings/core_logs_enabled':
      if (req.method == 'GET') return _getCoreLogsEnabled();
      if (req.method == 'PUT') return _putCoreLogsEnabled(req);
      throw _methodNotAllowed(req.method, path);

    case '/settings/core_logs_verbose':
      if (req.method == 'GET') return _getCoreLogsVerbose();
      if (req.method == 'PUT') return _putCoreLogsVerbose(req);
      throw _methodNotAllowed(req.method, path);

    case '/settings/ping_options':
      if (req.method == 'GET') return _getPingOptions();
      if (req.method == 'PUT') return _putPingOptions(req, ctx);
      throw _methodNotAllowed(req.method, path);

    case '/settings/tun_apps':
      if (req.method == 'GET') return _getTunApps();
      if (req.method == 'PUT') return _putTunApps(req, ctx);
      throw _methodNotAllowed(req.method, path);

    case '/settings/vpn/allow_bypass':
      if (req.method == 'GET') return _getAllowBypass();
      if (req.method == 'PUT') return _putAllowBypass(req);
      throw _methodNotAllowed(req.method, path);

    case '/settings/vpn/keep_on_exit':
      if (req.method == 'GET') return _getKeepOnExit();
      if (req.method == 'PUT') return _putKeepOnExit(req);
      throw _methodNotAllowed(req.method, path);

    case '/settings/vpn/background_mode':
      if (req.method == 'GET') return _getBackgroundMode();
      if (req.method == 'PUT') return _putBackgroundMode(req);
      throw _methodNotAllowed(req.method, path);
  }


  if (path.startsWith('/settings/ping_options/groups/')) {
    final tag =
        path.substring('/settings/ping_options/groups/'.length);
    if (tag.isEmpty || tag.contains('/')) {
      throw NotFound('settings path: $path');
    }
    return switch (req.method) {
      'GET' => _getGroupPing(tag),
      'PUT' => _putGroupPing(tag, req, ctx),
      'DELETE' => _deleteGroupPing(tag, ctx),
      _ => throw _methodNotAllowed(req.method, path),
    };
  }


  if (path.startsWith('/settings/vars/')) {
    final key = path.substring('/settings/vars/'.length);
    if (key.isEmpty || key.contains('/')) {
      throw NotFound('settings path: $path');
    }
    return switch (req.method) {
      'PUT' => _putVar(key, req, ctx),
      'DELETE' => _deleteVar(key, req, ctx),
      _ => throw _methodNotAllowed(req.method, path),
    };
  }

  throw NotFound('settings path: $path');
}

BadRequest _methodNotAllowed(String method, String path) =>
    BadRequest('method $method not allowed on $path');





Future<DebugResponse> _putRouteFinal(DebugRequest req, DebugContext ctx) async {
  final body = req.jsonBodyAsMap();
  final outbound = fieldString(body, 'outbound');
  if (outbound == null) {
    throw const BadRequest('field "outbound" required (empty string allowed)');
  }
  await SettingsStorage.saveRouteFinal(outbound);
  final extras = await maybeRebuild(req, ctx);
  return JsonResponse({
    'ok': true,
    'action': 'settings-route-final',
    'outbound': outbound,
    ...extras,
  });
}






Future<DebugResponse> _getInterruptOnSwitch() async {
  final v = await SettingsStorage.getInterruptOnSwitch();
  return JsonResponse({'ok': true, 'enabled': v});
}



Future<DebugResponse> _putInterruptOnSwitch(DebugRequest req) async {
  final body = req.jsonBodyAsMap();
  final enabled = fieldBool(body, 'enabled');
  if (enabled == null) throw const BadRequest('field "enabled" (bool) required');
  await SettingsStorage.setInterruptOnSwitch(enabled);
  return JsonResponse({'ok': true, 'action': 'settings-interrupt-on-switch', 'enabled': enabled});
}


Future<DebugResponse> _getNodeSort() async {
  final s = await SettingsStorage.getNodeSort();
  return JsonResponse({'ok': true, 'mode': s.mode, 'order': s.order});
}




Future<DebugResponse> _putNodeSort(DebugRequest req) async {
  final body = req.jsonBodyAsMap();
  final mode = fieldString(body, 'mode');
  if (mode == null) throw const BadRequest('field "mode" (string) required');
  final order = fieldStringList(body, 'order') ?? const <String>[];
  await SettingsStorage.setNodeSort(mode, order);
  return JsonResponse({'ok': true, 'action': 'settings-node-sort', 'mode': mode, 'order_count': order.length});
}


Future<DebugResponse> _getEnabledGroups() async {
  final g = await SettingsStorage.getEnabledGroups();
  return JsonResponse({'ok': true, 'groups': g.toList()});
}



Future<DebugResponse> _putEnabledGroups(DebugRequest req, DebugContext ctx) async {
  final body = req.jsonBodyAsMap();
  final groups = fieldStringList(body, 'groups');
  if (groups == null) throw const BadRequest('field "groups" (string array) required');
  await SettingsStorage.saveEnabledGroups(groups.toSet());
  final extras = await maybeRebuild(req, ctx);
  return JsonResponse({'ok': true, 'action': 'settings-enabled-groups', 'count': groups.length, ...extras});
}


Future<DebugResponse> _getVpnMode() async {
  final m = await SettingsStorage.getVpnMode();
  return JsonResponse({'ok': true, 'vpn_mode': m.toJson()});
}




Future<DebugResponse> _putVpnMode(DebugRequest req, DebugContext ctx) async {
  final body = req.jsonBodyAsMap();
  final cur = await SettingsStorage.getVpnMode();
  final listen = fieldString(body, 'proxy_listen');
  if (listen != null && !VpnModeConfig.isValidListenAddr(listen)) {
    throw BadRequest('invalid "proxy_listen" (IPv4 required): $listen');
  }


  final port = fieldInt(body, 'proxy_port');
  if (port != null && !VpnModeConfig.isValidPort(port)) {
    throw BadRequest('invalid "proxy_port" (1024..65535 required): $port');
  }
  final protocol = fieldString(body, 'proxy_protocol');
  if (protocol != null && !VpnModeConfig.isValidProtocol(protocol)) {
    throw BadRequest(
        'invalid "proxy_protocol" (mixed|http|socks required): $protocol');
  }
  final requested = cur.copyWith(
    mode: fieldString(body, 'mode'),
    proxyProtocol: protocol,
    proxyPort: port,
    proxyListen: listen,
    proxyAuthEnabled: fieldBool(body, 'proxy_auth'),
    proxyUsername: fieldString(body, 'proxy_user'),
    proxyPassword: fieldString(body, 'proxy_pass'),
  );




  final next = await VpnSettingsFacade.applyVpnMode(requested);
  final extras = await maybeRebuild(req, ctx);
  return JsonResponse({'ok': true, 'action': 'settings-vpn-mode', 'vpn_mode': next.toJson(), ...extras});
}







const Set<String> _varBlocklist = {
  'debug_token',
  'debug_enabled',
  'debug_port',
};





final _varPutHooks = <String, Future<void> Function(String value)>{
  'app_language': (value) async {
    if (!SettingsStorage.appLanguageValues.contains(value)) {
      throw const BadRequest('app_language must be "system", "en" or "ru"');
    }
    await LocaleController.I.set(value);
  },
};

final _varDeleteHooks = <String, Future<void> Function()>{

  'app_language': () => LocaleController.I.set('system'),
};

Future<DebugResponse> _putVar(String key, DebugRequest req, DebugContext ctx) async {
  if (_varBlocklist.contains(key)) {
    throw Conflict('var "$key" is managed via App Settings UI only');
  }
  final body = req.jsonBodyAsMap();
  final value = fieldString(body, 'value');
  if (value == null) {
    throw const BadRequest('field "value" required (string)');
  }
  final hook = _varPutHooks[key];
  if (hook != null) {
    await hook(value);
  } else {
    await SettingsStorage.setVar(key, value);
  }
  final extras = await maybeRebuild(req, ctx);
  return JsonResponse({
    'ok': true,
    'action': 'settings-var-put',
    'key': key,
    'value': value,
    ...extras,
  });
}

Future<DebugResponse> _deleteVar(String key, DebugRequest req, DebugContext ctx) async {
  if (_varBlocklist.contains(key)) {
    throw Conflict('var "$key" is managed via App Settings UI only');
  }
  final hook = _varDeleteHooks[key];
  if (hook != null) {
    await hook();
  } else {
    await SettingsStorage.removeVar(key);
  }
  final extras = await maybeRebuild(req, ctx);
  return JsonResponse({
    'ok': true,
    'action': 'settings-var-delete',
    'key': key,
    ...extras,
  });
}






const String _dnsServerRecordSample =
    '{"kind":"user","tag":"my-dns","enabled":true,"body":{"type":"udp","server":"1.1.1.1"}}';


const String _dnsRuleRecordSample =
    '{"kind":"user","name":"corp","enabled":true,"body":{"domain_suffix":[".corp"],"server":"my-dns"}}';





void _rejectLegacyDnsKeys(
  Map<dynamic, dynamic> record,
  List<String> legacyKeys,
  String sample,
  String kinds,
) {
  for (final key in legacyKeys) {
    if (record.containsKey(key)) {
      throw BadRequest('"$key" is the 2.23.2 storage form; expected a record '
          'like $sample ($kinds)');
    }
  }
}






Future<DebugResponse> _putDnsServers(DebugRequest req, DebugContext ctx) async {
  final body = req.jsonBodyAsMap();
  if (!body.containsKey('servers')) {
    throw const BadRequest('field "servers" required (list of dns-server objects)');
  }
  final raw = body['servers'];
  if (raw is! List) {
    throw const BadRequest('field "servers" must be array');
  }
  final servers = <DnsServerRef>[];
  for (final s in raw) {
    if (s is! Map) {
      throw const BadRequest('each servers[i] must be an object');
    }

    _rejectLegacyDnsKeys(s, const ['varValues'], _dnsServerRecordSample,
        'kind user|preset|template');
    final read = dnsServerFromRecord(s.cast<String, dynamic>());
    final server = read.value;
    if (server == null) {
      throw BadRequest('${read.dropped}; expected a record like '
          '$_dnsServerRecordSample (kind user|preset|template)');
    }
    servers.add(server);
  }
  await SettingsStorage.saveDnsServers(servers);
  final extras = await maybeRebuild(req, ctx);
  return JsonResponse({
    'ok': true,
    'action': 'settings-dns-servers',
    'count': servers.length,
    ...extras,
  });
}

Future<DebugResponse> _putDnsRules(DebugRequest req, DebugContext ctx) async {
  final body = req.jsonBodyAsMap();



  final arr = body['rules'];
  if (arr is! List) {
    throw const BadRequest('field "rules" required (array of dns rule records)');
  }
  final rules = <DnsRuleRef>[];
  for (final r in arr) {
    if (r is! Map) {
      throw const BadRequest('each rules[i] must be an object');
    }

    _rejectLegacyDnsKeys(r, const ['presetId'], _dnsRuleRecordSample,
        'kind user|preset|srs|template');
    final read = dnsRuleFromRecord(r.cast<String, dynamic>());
    final rule = read.value;
    if (rule == null) {
      throw BadRequest('${read.dropped}; expected a record like '
          '$_dnsRuleRecordSample (kind user|preset|srs|template)');
    }
    rules.add(rule);
  }
  await SettingsStorage.saveDnsRulesList(rules);
  final extras = await maybeRebuild(req, ctx);
  return JsonResponse({
    'ok': true,
    'action': 'settings-dns-rules',
    'count': rules.length,
    ...extras,
  });
}









Future<DebugResponse> _putConfigLocked(DebugRequest req) async {
  final body = req.jsonBodyAsMap();
  final value = body['locked'];
  if (value is! bool) {
    throw const BadRequest('body must be {"locked": true|false}');
  }
  await SettingsStorage.setConfigLockedForDebug(value);
  return JsonResponse({
    'ok': true,
    'action': 'settings-config-locked',
    'locked': value,
  });
}















Future<DebugResponse> _getCoreLogsEnabled() async {

  final enabled =
      await SettingsStorage.getNativeBool(NativePrefsKeys.coreLogsEnabled);
  return JsonResponse({'enabled': enabled});
}

Future<DebugResponse> _putCoreLogsEnabled(DebugRequest req) async {
  final body = req.jsonBodyAsMap();
  final value = body['enabled'];
  if (value is! bool) {
    throw const BadRequest('body must be {"enabled": true|false}');
  }

  await SettingsStorage.setNativeBool(NativePrefsKeys.coreLogsEnabled, value);
  return JsonResponse({
    'ok': true,
    'action': 'settings-core-logs-enabled',
    'enabled': value,
    'note':
        'saved; force-stop & reopen the app to apply (Libbox.setup is '
        'one-shot per process — stop/start VPN does NOT re-apply)',
  });
}







Future<DebugResponse> _getCoreLogsVerbose() async {
  final enabled =
      await SettingsStorage.getNativeBool(NativePrefsKeys.coreLogsVerbose);
  return JsonResponse({'enabled': enabled});
}

Future<DebugResponse> _putCoreLogsVerbose(DebugRequest req) async {
  final body = req.jsonBodyAsMap();
  final value = body['enabled'];
  if (value is! bool) {
    throw const BadRequest('body must be {"enabled": true|false}');
  }
  await SettingsStorage.setNativeBool(NativePrefsKeys.coreLogsVerbose, value);
  return JsonResponse({
    'ok': true,
    'action': 'settings-core-logs-verbose',
    'enabled': value,
    'note': 'applies immediately (no VPN restart); '
        'no effect while core_logs_enabled is off',
  });
}







Future<DebugResponse> _getPingOptions() async {
  final opts = await SettingsStorage.getPingOptions();
  return JsonResponse(opts);
}



Future<DebugResponse> _putPingOptions(
    DebugRequest req, DebugContext ctx) async {
  final body = req.jsonBodyAsMap();


  if (body.containsKey('url') && body['url'] is! String) {
    throw const BadRequest('field "url" must be string if present');
  }
  if (body.containsKey('timeout_ms') && body['timeout_ms'] is! num) {
    throw const BadRequest('field "timeout_ms" must be number if present');
  }
  if (body.containsKey('groups') && body['groups'] is! Map) {
    throw const BadRequest('field "groups" must be object if present');
  }



  const allowedPingKeys = {'url', 'timeout_ms', 'presets', 'groups'};
  final clean = <String, dynamic>{
    for (final e in body.entries)
      if (allowedPingKeys.contains(e.key)) e.key: e.value,
  };
  await SettingsStorage.savePingOptions(clean);
  await _reloadHomePingOptions(ctx);
  return JsonResponse({
    'ok': true,
    'action': 'settings-ping-options',
    'url': body['url'],
    'timeout_ms': body['timeout_ms'],
    'groups_count': (body['groups'] is Map) ? (body['groups'] as Map).length : 0,
  });
}


Future<DebugResponse> _getGroupPing(String tag) async {
  final opts = await SettingsStorage.getPingOptions();
  final groups = opts['groups'];
  if (groups is! Map<String, dynamic> || !groups.containsKey(tag)) {
    throw NotFound('group_ping: $tag');
  }
  return JsonResponse(groups[tag] as Map<String, dynamic>);
}



Future<DebugResponse> _putGroupPing(
    String tag, DebugRequest req, DebugContext ctx) async {
  final body = req.jsonBodyAsMap();
  String? url;
  int? timeoutMs;
  if (body.containsKey('url')) {
    final v = body['url'];
    if (v is! String) throw const BadRequest('field "url" must be string');
    url = v;
  }
  if (body.containsKey('timeout_ms')) {
    final v = body['timeout_ms'];
    if (v is! num) throw const BadRequest('field "timeout_ms" must be number');
    timeoutMs = v.toInt();
  }
  if (url == null && timeoutMs == null) {
    throw const BadRequest('at least one of "url" / "timeout_ms" required');
  }
  await SettingsStorage.setGroupPing(tag, url: url, timeoutMs: timeoutMs);
  await _reloadHomePingOptions(ctx);
  return JsonResponse({
    'ok': true,
    'action': 'settings-ping-options-group-put',
    'group': tag,
    'url': ?url,
    'timeout_ms': ?timeoutMs,
  });
}


Future<DebugResponse> _deleteGroupPing(String tag, DebugContext ctx) async {
  await SettingsStorage.clearGroupPing(tag);
  await _reloadHomePingOptions(ctx);
  return JsonResponse({
    'ok': true,
    'action': 'settings-ping-options-group-delete',
    'group': tag,
  });
}




Future<void> _reloadHomePingOptions(DebugContext ctx) async {
  try {
    final home = ctx.registry.home;
    if (home != null) await home.reloadPingOptions();
  } catch (_) {

  }
}





Future<DebugResponse> _rebuildConfig(DebugContext ctx) async {

  if (await SettingsStorage.getConfigLockedForDebug()) {
    throw const Conflict(
      'config_locked_for_debug=true — rebuild blocked. '
      'PUT /settings/config_locked {"locked":false} to unlock first.',
    );
  }
  final sub = ctx.requireSub();
  final home = ctx.requireHome();
  final json = await sub.generateConfig();
  if (json == null) {
    throw UpstreamError(
        'generate failed: ${sub.lastError?.renderEn() ?? ''}');
  }
  final saved = await home.saveParsedConfig(json);
  if (!saved) {
    throw const UpstreamError('saveParsedConfig returned false');
  }
  return JsonResponse({
    'ok': true,
    'action': 'settings-rebuild-config',
    'config_bytes': json.length,
  });
}



Future<DebugResponse> _getTunApps() async {
  final cfg = await SettingsStorage.getTunApps();
  return JsonResponse(cfg.toJson());
}








Future<DebugResponse> _putTunApps(DebugRequest req, DebugContext ctx) async {
  final body = req.jsonBodyAsMap();

  final mode = body['mode'];

  if (mode is! String || !TunAppsConfig.isValidMode(mode)) {
    throw const BadRequest('field "mode" must be one of: off|allow|deny');
  }

  final pkgsRaw = body['packages'];
  if (pkgsRaw is! List) {
    throw const BadRequest('field "packages" must be array of strings');
  }
  final pkgs = <String>[];



  final pkgRe = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)*$');
  for (final p in pkgsRaw) {
    if (p is! String) {
      throw BadRequest('packages[] must be strings; got ${p.runtimeType}');
    }
    final t = p.trim();
    if (t.isEmpty) continue;
    if (!pkgRe.hasMatch(t)) {
      throw BadRequest('invalid package name: $t');
    }
    pkgs.add(t);
  }

  final cfg = TunAppsConfig(mode: mode, packages: pkgs);
  await SettingsStorage.setTunApps(cfg);

  final extras = await maybeRebuild(req, ctx);
  return JsonResponse({
    'ok': true,
    'action': 'settings-tun-apps',
    'mode': mode,
    'count': pkgs.length,
    'rebuild_needed': true,
    ...extras,
  });
}






Future<DebugResponse> _getAllowBypass() async {
  final v = await SettingsStorage.getNativeBool(NativePrefsKeys.allowBypass);
  return JsonResponse({'enabled': v});
}

Future<DebugResponse> _putAllowBypass(DebugRequest req) async {
  final body = req.jsonBodyAsMap();
  final value = body['enabled'];
  if (value is! bool) {
    throw const BadRequest('body must be {"enabled": true|false}');
  }
  await SettingsStorage.setNativeBool(NativePrefsKeys.allowBypass, value);
  return JsonResponse({
    'ok': true,
    'action': 'settings-vpn-allow-bypass',
    'enabled': value,
    'note': 'reload VPN to apply (allowBypass set at next establish())',
  });
}

Future<DebugResponse> _getKeepOnExit() async {
  final v = await SettingsStorage.getNativeBool(NativePrefsKeys.keepOnExit);
  return JsonResponse({'enabled': v});
}

Future<DebugResponse> _putKeepOnExit(DebugRequest req) async {
  final body = req.jsonBodyAsMap();
  final value = body['enabled'];
  if (value is! bool) {
    throw const BadRequest('body must be {"enabled": true|false}');
  }
  await SettingsStorage.setNativeBool(NativePrefsKeys.keepOnExit, value);
  return JsonResponse({
    'ok': true,
    'action': 'settings-vpn-keep-on-exit',
    'enabled': value,
  });
}

Future<DebugResponse> _getBackgroundMode() async {
  final m = await SettingsStorage.getNativeBackgroundMode();
  return JsonResponse({'mode': BackgroundMode.fromNative(m).wireValue});
}

Future<DebugResponse> _putBackgroundMode(DebugRequest req) async {
  final body = req.jsonBodyAsMap();
  final raw = body['mode'];
  if (raw is! String) {
    throw const BadRequest('body must be {"mode": "never"|"lazy"|"always"}');
  }


  if (!BackgroundMode.isValid(raw)) {
    throw BadRequest('mode must be one of: never|lazy|always (got "$raw")');
  }
  final mode = BackgroundMode.fromNative(raw);
  await SettingsStorage.setNativeBackgroundMode(mode.wireValue);
  return JsonResponse({
    'ok': true,
    'action': 'settings-vpn-background-mode',
    'mode': mode.wireValue,
    'note': 'applied on next VPN connect',
  });
}
