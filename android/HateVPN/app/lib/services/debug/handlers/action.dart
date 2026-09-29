import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../../models/custom_rule.dart';
import '../../app_log.dart';
import '../../automation/handlers.dart' as automation;
import '../../core_reject/core_reject_runner.dart';
import '../../core_reject/core_reject_state.dart';
import '../../error_humanize.dart';
import '../../platform_channels.dart';
import '../../../vpn/box_vpn_client.dart';
import '../../rule_set_downloader.dart';
import '../../settings_storage.dart';
import '../../update_checker.dart';
import '../../version_info.dart';
import '../context.dart';
import '../contract/errors.dart';
import '../transport/request.dart';
import '../transport/response.dart';












Future<DebugResponse> actionHandler(
  DebugRequest req,
  DebugContext ctx,
) async {
  if (req.method != 'POST') {
    throw const BadRequest('actions require POST');
  }
  return switch (req.path) {
    '/action/urltest' => _urltest(req, ctx),
    '/action/switch-node' => _switchNode(req, ctx),
    '/action/set-group' => _setGroup(req, ctx),
    '/action/start-vpn' => _startVpn(ctx),
    '/action/start-vpn-headless' => _startVpnHeadless(req, ctx),
    '/action/check-config' => _checkConfig(req, ctx),
    '/action/stop-vpn' => _stopVpn(ctx),
    '/action/reconnect' => _reconnect(ctx),
    '/action/reload-vpn' => _reloadVpn(ctx),
    '/action/clear-error' => _clearError(ctx),
    '/action/force-stop-vpn' => _forceStopVpn(ctx),
    '/action/set-transient-timeout' => _setTransientTimeout(req, ctx),
    '/action/reset-network' => _resetNetwork(ctx),
    '/action/quic-knobs' => _quicKnobs(req),
    '/action/rebuild-config' => _rebuildConfig(ctx),
    '/action/refresh-subs' => _refreshSubs(req, ctx),
    '/action/download-srs' => _downloadSrs(req, ctx),
    '/action/clear-srs' => _clearSrs(req, ctx),
    '/action/toast' => _toast(req, ctx),
    '/action/emulate-error' => _emulateError(req, ctx),
    '/action/check-updates' => _checkUpdates(req, ctx),
    '/action/preview-empty-state' => _previewEmptyState(req, ctx),
    _ => throw NotFound('action: ${req.path}'),
  };
}









Future<DebugResponse> _previewEmptyState(
  DebugRequest req,
  DebugContext ctx,
) async {
  final home = ctx.home;
  if (home == null) throw const Conflict('home controller not ready');
  final on = (req.query['on'] ?? 'true').toLowerCase() == 'true';
  home.setPreviewEmpty(on);
  return JsonResponse({
    'ok': true,
    'action': 'preview-empty-state',
    'on': on,
  });
}








Future<DebugResponse> _checkUpdates(DebugRequest req, DebugContext ctx) async {
  final result = await UpdateChecker.I.forceCheck(
    localVersion: VersionInfo.I.version,
  );
  final body = <String, Object?>{
    'ok': true,
    'action': 'check-updates',
    'kind': result.kind.name,
  };
  final info = result.info;
  if (info != null) {
    body['tag'] = info.tag;
    body['name'] = info.name;
    body['html_url'] = info.htmlUrl;
    body['published_at'] = info.publishedAt?.toUtc().toIso8601String();
    body['dismissed'] = result.dismissed;
  }
  if (result.localVersion != null) body['local_version'] = result.localVersion;
  if (result.message != null) body['message'] = result.message;
  return JsonResponse(body);
}








Future<DebugResponse> _emulateError(
  DebugRequest req,
  DebugContext ctx,
) async {
  final kind = req.requiredQuery('kind');

  Exception buildException(String k) => switch (k) {
        'socket' => const SocketException('emulated: host lookup failed'),
        'timeout' => TimeoutException('emulated: request timeout'),
        'http-401' =>
          const HttpException('HTTP 401 for https://provider.example/sub/***'),
        'http-404' =>
          const HttpException('HTTP 404 for https://provider.example/sub/***'),
        'http-410' =>
          const HttpException('HTTP 410 for https://provider.example/sub/***'),
        'http-429' =>
          const HttpException('HTTP 429 for https://provider.example/sub/***'),
        'http-503' =>
          const HttpException('HTTP 503 for https://provider.example/sub/***'),
        'format' => const FormatException('emulated: not valid JSON'),
        'fs' => const FileSystemException('emulated: permission denied'),
        'plain' => Exception('emulated plain exception text'),
        _ => throw BadRequest(
            'kind must be one of socket|timeout|http-401|http-404|'
            'http-410|http-429|http-503|format|fs|plain|all, got "$k"'),
      };

  final kinds = kind == 'all'
      ? [
          'socket',
          'timeout',
          'http-401',
          'http-404',
          'http-410',
          'http-429',
          'http-503',
          'format',
          'fs',
          'plain',
        ]
      : [kind];

  final samples = <Map<String, String>>[];
  for (final k in kinds) {
    final e = buildException(k);
    final humanized = humanizeError(e).renderEn();
    samples.add({'kind': k, 'humanized': humanized});
    AppLog.I.error('emulate-error [kind=$k]: $humanized');
  }

  return _ok('emulate-error', {'samples': samples});
}


JsonResponse _ok(String action, [Map<String, Object?> extras = const {}]) {
  return JsonResponse({
    'ok': true,
    'action': action,
    ...extras,
  });
}







Future<DebugResponse> _urltest(DebugRequest req, DebugContext ctx) async {
  final home = ctx.requireHome();


  if (req.query['cancel'] != null) {
    home.cancelMassPing();
    return _ok('urltest', {'scope': 'cancel'});
  }
  final tag = req.query['tag'];
  final group = req.query['group'];
  final all = req.query['all'];
  final scopes = [
    if (tag != null) 'tag',
    if (group != null) 'group',
    if (all != null) 'all',
  ];
  if (scopes.isEmpty) {
    throw const BadRequest('one of "tag" / "group" / "all" required');
  }
  if (scopes.length > 1) {
    throw BadRequest('exactly one of "tag" / "group" / "all" — got ${scopes.join("+")}');
  }
  if (tag != null) {
    if (tag.isEmpty) throw const BadRequest('"tag" empty');
    unawaited(home.runNodeUrltest(tag));
    return _ok('urltest', {'scope': 'node', 'tag': tag});
  }
  if (group != null) {



    await automation.actionUrltestGroup(group, ctx);
    return _ok('urltest', {'scope': 'group', 'group': group});
  }

  unawaited(home.runMassUrltest());
  return _ok('urltest', {'scope': 'mass'});
}

Future<DebugResponse> _switchNode(DebugRequest req, DebugContext ctx) async {
  final tag = req.requiredQuery('tag');
  await automation.actionSwitchNode(tag, ctx);
  return _ok('switch-node', {'tag': tag});
}

Future<DebugResponse> _setGroup(DebugRequest req, DebugContext ctx) async {
  final group = req.requiredQuery('group');
  await automation.actionSetGroup(group, ctx);
  return _ok('set-group', {'group': group});
}

Future<DebugResponse> _startVpn(DebugContext ctx) async {
  await automation.actionStartVpn(ctx);
  return _ok('start-vpn');
}

Future<DebugResponse> _stopVpn(DebugContext ctx) async {
  await automation.actionStopVpn(ctx);
  return _ok('stop-vpn');
}




















Future<DebugResponse> _startVpnHeadless(
  DebugRequest req,
  DebugContext ctx,
) async {
  if (!req.qBool('guard')) {
    final r = await BoxVpnClient().startVpnHeadless();
    return _ok('start-vpn-headless', {
      'started': r.started,
      'needs_consent': r.needsConsent,
      'guard': false,
    });
  }
  if (CoreRejectState.I.guardActive) {
    throw const Conflict('guard already running');
  }
  final home = ctx.requireHome();
  final sub = ctx.requireSub();



  unawaited(() async {
    try {
      await runCoreRejectGuard(home: home, sub: sub, headless: true);
    } catch (e) {
      AppLog.I.warning('core reject guard (async): $e');
    }
  }());
  return _ok('start-vpn-headless', {
    'guard': true,
    'started': true,
    'async': true,
  });
}












Future<DebugResponse> _checkConfig(DebugRequest req, DebugContext ctx) async {
  final home = ctx.requireHome();

  final String config;
  if (req.body.isEmpty) {
    config = home.state.configRaw;
  } else {
    try {
      config = utf8.decode(req.body, allowMalformed: false);
    } on FormatException {
      throw const BadRequest('body is not valid UTF-8');
    }
  }
  if (config.isEmpty) {
    throw const Conflict('no config built yet');
  }
  final capMs = ctx.config.requestTimeout.inMilliseconds;
  var timeoutMs = int.tryParse(req.query['timeout_ms'] ?? '') ?? 10000;
  if (timeoutMs <= 0 || (capMs > 0 && timeoutMs > capMs)) {
    timeoutMs = capMs > 0 ? capMs : 10000;
  }
  final started = DateTime.now();
  CoreCheck? r;
  try {
    r = await BoxVpnClient()
        .checkConfig(config)
        .timeout(Duration(milliseconds: timeoutMs));
  } on TimeoutException {
    throw Conflict('checkConfig did not answer in ${timeoutMs}ms');
  }
  final ms = DateTime.now().difference(started).inMilliseconds;


  if (r == null) throw const Conflict('checkConfig bridge unavailable');
  return _ok('check-config', {
    'config_ok': r.ok,
    'error': r.error,
    'ms': ms,
    'bytes': config.length,
  });
}











Future<DebugResponse> _forceStopVpn(DebugContext ctx) async {
  final home = ctx.requireHome();
  final ok = await home.debugForceStopVpn();
  return _ok('force-stop-vpn', {'native_ok': ok});
}





Future<DebugResponse> _reconnect(DebugContext ctx) async {
  final home = ctx.requireHome();
  await home.reconnect();
  return _ok('reconnect');
}





Future<DebugResponse> _reloadVpn(DebugContext ctx) async {
  final home = ctx.requireHome();
  final canReload = home.canReload;
  if (canReload) await home.reloadVpn();
  return _ok('reload-vpn', {'applied': canReload});
}




Future<DebugResponse> _clearError(DebugContext ctx) async {
  final home = ctx.requireHome();
  home.clearError();
  return _ok('clear-error');
}











Future<DebugResponse> _setTransientTimeout(
  DebugRequest req,
  DebugContext ctx,
) async {
  final home = ctx.requireHome();
  final connectingRaw = req.q('connecting');
  final stoppingRaw = req.q('stopping');
  if (connectingRaw == null && stoppingRaw == null) {
    throw const BadRequest(
        'at least one of connecting/stopping (ms) required');
  }
  final connectingMs = _parsePositiveMs(connectingRaw, 'connecting');
  final stoppingMs = _parsePositiveMs(stoppingRaw, 'stopping');
  final applied = home.debugSetTransientTimeouts(
    connectingMs: connectingMs,
    stoppingMs: stoppingMs,
  );
  return _ok('set-transient-timeout', {
    'connecting_ms': applied.connectingMs,
    'stopping_ms': applied.stoppingMs,
  });
}


int? _parsePositiveMs(String? raw, String name) {
  if (raw == null) return null;
  final v = int.tryParse(raw);
  if (v == null || v <= 0) {
    throw BadRequest('$name must be a positive integer (ms), got "$raw"');
  }
  return v;
}














Future<DebugResponse> _resetNetwork(DebugContext ctx) async {
  final ok = await automation.actionResetNetwork(ctx);
  return _ok('reset-network', {'native_ok': ok});
}









Future<DebugResponse> _quicKnobs(DebugRequest req) async {
  final applied = <String, Object?>{};
  var any = false;
  for (final knob in const ['gso', 'ecn']) {
    final raw = req.query[knob];
    if (raw == null) continue;
    final disabled = switch (raw) {
      'off' => true,
      'on' => false,
      _ => throw BadRequest('$knob must be "on" or "off", got "$raw"'),
    };
    any = true;
    final ok = await BoxVpnClient().setQuicKnob(knob, disabled: disabled);
    applied[knob] = {'disabled': disabled, 'native_ok': ok};
  }
  if (!any) {
    throw const BadRequest('pass at least one of gso=on|off, ecn=on|off');
  }
  return _ok('quic-knobs', applied);
}

Future<DebugResponse> _rebuildConfig(DebugContext ctx) async {


  final bytes = await automation.actionRebuildConfig(ctx);
  return _ok('rebuild-config', {'bytes': bytes});
}

Future<DebugResponse> _refreshSubs(DebugRequest req, DebugContext ctx) async {
  final force = req.qBool('force');
  await automation.actionRefreshSubs(force, ctx);
  return _ok('refresh-subs', {'force': force});
}

Future<DebugResponse> _downloadSrs(DebugRequest req, DebugContext ctx) async {
  final id = req.requiredQuery('ruleId');
  final rules = await SettingsStorage.getCustomRules();
  CustomRule? rule;
  for (final r in rules) {
    if (r.id == id) {
      rule = r;
      break;
    }
  }
  if (rule == null) throw NotFound('rule: $id');
  if (rule.srsUrls.isEmpty) throw const Conflict('rule has no srsUrl');

  final paths = <String>[];
  for (var i = 0; i < rule.srsUrls.length; i++) {
    final path = await RuleSetDownloader.download(
        CustomRuleSrs.cacheIdAt(id, i), rule.srsUrls[i]);
    if (path == null) throw const UpstreamError('srs download failed');
    paths.add(path);
  }
  return _ok('download-srs', {'rule_id': id, 'path': paths.first, 'paths': paths});
}

Future<DebugResponse> _clearSrs(DebugRequest req, DebugContext ctx) async {
  final id = req.requiredQuery('ruleId');
  await RuleSetDownloader.delete(id);
  return _ok('clear-srs', {'rule_id': id});
}





const _methodChannel = MethodChannel(PlatformChannels.methods);

Future<DebugResponse> _toast(DebugRequest req, DebugContext ctx) async {
  final msg = req.requiredQuery('msg');
  final duration = req.q('duration') ?? 'short';
  if (duration != 'short' && duration != 'long') {
    throw BadRequest('duration must be "short" or "long", got "$duration"');
  }
  final trimmed = msg.length > 200 ? msg.substring(0, 200) : msg;
  try {
    await _methodChannel.invokeMethod('showToast', {
      'msg': trimmed,
      'duration': duration,
    });
  } on PlatformException catch (e) {
    throw UpstreamError('toast failed: ${e.message}');
  } on MissingPluginException {
    throw const Conflict('showToast not implemented in native plugin');
  }
  return _ok('toast', {'msg': trimmed, 'duration': duration});
}
