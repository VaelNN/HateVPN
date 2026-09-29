import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../../app_log.dart';
import '../../settings_storage.dart';
import '../context.dart';
import '../contract/errors.dart';
import '../handlers/action.dart';
import '../handlers/backup.dart';
import '../handlers/chains.dart';
import '../handlers/directions.dart';
import '../handlers/config.dart';
import '../handlers/core_reject.dart';
import '../handlers/device.dart';
import '../handlers/diag.dart';
import '../handlers/files.dart';
import '../handlers/folders.dart';
import '../handlers/logs.dart';
import '../handlers/help.dart';
import '../handlers/nodes.dart';
import '../handlers/ping.dart';
import '../handlers/pool.dart';
import '../handlers/profiler.dart';
import '../handlers/support.dart';
import '../handlers/rules.dart';
import '../handlers/settings.dart';
import '../handlers/state.dart';
import '../handlers/subs.dart';
import '../handlers/warp.dart';
import '../handlers/wifi_history.dart';
import 'config.dart';
import 'middleware/access_log.dart';
import 'middleware/auth.dart';
import 'middleware/error_mapper.dart';
import 'middleware/host_check.dart';
import 'middleware/timeout.dart';
import 'pipeline.dart';
import 'request.dart';
import 'response.dart';
import 'router.dart';












class DebugServer {
  DebugServer._();
  static final DebugServer I = DebugServer._();

  HttpServer? _server;
  DebugServerConfig? _config;
  DebugContext? _context;
  Router? _router;
  List<Middleware>? _pipeline;

  bool get running => _server != null;
  int get port => _config?.port ?? 0;



  Future<void> start(DebugServerConfig config, DebugContext context) async {
    await stop();

    if (config.token.isEmpty) {
      AppLog.I.warning('Debug API: token empty — refusing to start');
      return;
    }

    final router = buildDebugRouter();
    final pipeline = _buildPipeline(config);

    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      config.port,
    );

    _server = server;
    _config = config;



    _context = context.withConfig(config);
    _router = router;
    _pipeline = pipeline;

    AppLog.I.info('Debug API: listening on 127.0.0.1:${config.port}');

    server.listen(
      _onRequest,
      onError: (Object e, StackTrace st) {
        AppLog.I.error('Debug API listen: $e');
      },
      cancelOnError: false,
    );
  }

  Future<void> stop() async {
    final s = _server;
    if (s == null) return;
    _server = null;
    _config = null;
    _context = null;
    _router = null;
    _pipeline = null;
    try {
      await s.close(force: true);
      AppLog.I.info('Debug API: stopped');
    } catch (e) {
      AppLog.I.warning('Debug API: stop error: $e');
    }
  }




  Future<void> restartFromSettings(DebugContext context) async {
    final enabled = await SettingsStorage.getDebugEnabled();
    if (!enabled) {
      await stop();
      return;
    }
    final port = await SettingsStorage.getDebugPort();
    final token = await SettingsStorage.getDebugToken();
    try {
      await start(
        DebugServerConfig(port: port, token: token),
        context,
      );
    } on SocketException catch (e) {
      AppLog.I.error('Debug API: bind failed on :$port — ${e.message}');
    } catch (e) {
      AppLog.I.error('Debug API: start failed — $e');
    }
  }


  static String generateToken() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  List<Middleware> _buildPipeline(DebugServerConfig config) {






    return [
      errorMapper,
      accessLog(),
      hostCheck,
      auth(
        token: config.token,
        unauthenticatedPaths: config.unauthenticatedPaths,
      ),
      timeoutMiddleware(config.requestTimeout),
    ];
  }

  Future<void> _onRequest(HttpRequest raw) async {
    final cfg = _config;
    final ctx = _context;
    final router = _router;
    final pipeline = _pipeline;
    if (cfg == null || ctx == null || router == null || pipeline == null) {

      await raw.response.close().catchError((_) {});
      return;
    }

    DebugResponse resp;
    try {
      final req = await DebugRequest.from(raw, maxBodyBytes: cfg.maxBodyBytes);
      resp = await runPipeline(req, ctx, pipeline, router.handle);
    } on DebugError catch (e) {




      AppLog.I.warning(
        '[debug-api] ${raw.method} ${raw.uri.path} → ${e.status} (pre-pipeline)',
      );
      resp = ErrorResponse(e);
    } catch (e, st) {
      AppLog.I.error(
        '[debug-api] ${raw.method} ${raw.uri.path} → 500 (pre-pipeline): $e\n$st',
      );
      resp = ErrorResponse(InternalError('$e'));
    }

    try {
      await resp.writeTo(raw.response);
    } catch (e) {

      AppLog.I.debug('Debug API: write failed — $e');
    }
  }
}


Router buildDebugRouter() {
  return Router()
    ..mount('/ping', pingHandler)
    ..mount('/help', helpHandler)
    ..mount('/state', stateHandler)
    ..mount('/device', deviceHandler)
    ..mount('/config', configHandler)
    ..mount('/pool', poolHandler)
    ..mount('/logs', logsHandler)
    ..mount('/action', actionHandler)
    ..mount('/files', filesHandler)
    ..mount('/diag', diagHandler)
    ..mount('/backup', backupHandler)
    ..mount('/rules', rulesHandler)
    ..mount('/subs', subsHandler)

    ..mount('/nodes', nodesHandler)
    ..mount('/directions', directionsHandler)
    ..mount('/chains', chainsHandler)
    ..mount('/folders', foldersHandler)


    ..mount('/core_reject', coreRejectHandler)
    ..mount('/warp', warpHandler)
    ..mount('/settings', settingsHandler)
    ..mount('/wifi_history', wifiHistoryHandler)
    ..mount('/profiler', profilerHandler)
    ..mount('/support', supportHandler);
}

