import 'dart:async';

import '../../warp/masquerade_params.dart';
import '../../warp/warp_account.dart';
import '../context.dart';
import '../contract/errors.dart';
import '../transport/request.dart';
import '../transport/response.dart';
import '_shared.dart';




























Future<DebugResponse> warpHandler(DebugRequest req, DebugContext ctx) async {
  if (req.path != '/warp') throw NotFound('warp path: ${req.path}');
  if (req.method != 'POST') {
    throw BadRequest('method ${req.method} not allowed on /warp (use POST)');
  }

  final body = req.jsonBodyAsMap();
  final sub = ctx.requireSub();

  final licenseKey = fieldString(body, 'licenseKey');
  final obfuscate = fieldBool(body, 'obfuscate') ?? false;
  final forceNew = fieldBool(body, 'forceNew') ?? false;
  final includeReserved = fieldBool(body, 'includeReserved');
  final endpoint = fieldString(body, 'endpoint');
  final quicParams = _parseQuicParams(body);

  final account = await sub.addWarp(
    licenseKey: (licenseKey == null || licenseKey.trim().isEmpty)
        ? null
        : licenseKey,
    endpoint: (endpoint == null || endpoint.trim().isEmpty)
        ? WarpAccount.defaultEndpoint
        : endpoint.trim(),
    forceNew: forceNew,
    obfuscate: obfuscate,
    quicParams: quicParams,
    includeReserved: includeReserved,
  );

  if (account == null) {
    throw BadRequest('addWarp failed: ${sub.lastError?.renderEn() ?? ''}');
  }

  final extras = await maybeRebuild(req, ctx);
  return JsonResponse({
    'ok': true,
    'action': 'warp-add',
    'warp_plus': account.warpPlus,
    'obfuscated': account.awg != null,
    'endpoint': account.endpoint,
    'address': account.clientV4,
    ...extras,
  }, status: 201);
}




QuicParams _parseQuicParams(Map<String, dynamic> body) {
  if (!body.containsKey('quicParams')) return const QuicParams();
  final v = body['quicParams'];
  if (v is! Map) {
    throw BadRequest('field "quicParams" must be object, got ${v.runtimeType}');
  }
  final q = v.cast<String, dynamic>();
  const def = QuicParams();
  return QuicParams(
    sni: fieldString(q, 'sni') ?? def.sni,
    ip: fieldString(q, 'ip') ?? def.ip,
    ib: fieldString(q, 'ib') ?? def.ib,
    jc: fieldInt(q, 'jc') ?? def.jc,
    jmin: fieldInt(q, 'jmin') ?? def.jmin,
    jmax: fieldInt(q, 'jmax') ?? def.jmax,
  );
}
