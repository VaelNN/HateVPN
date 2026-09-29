import '../../../controllers/subscription_controller.dart';
import '../../../models/config_node.dart';
import '../../../models/source_chain.dart';
import '../../../screens/chain_edit/chain_form_validation.dart';
import '../../../screens/chain_edit/chain_hop_candidate.dart';
import '../../../screens/chain_edit/chain_hop_targets.dart';
import '../../builder/node_link_pool.dart';
import '../../contract/chain_strip.dart' show chainStripKeyKnown, chainStripKeys;
import '../../probe/chain_layer_probe.dart';
import '../../settings_storage.dart';
import '../context.dart';
import '../contract/errors.dart';
import '../serializers/chains.dart';
import '../transport/request.dart';
import '../transport/response.dart';
import '_shared.dart';






































Future<DebugResponse> chainsHandler(DebugRequest req, DebugContext ctx) async {
  final path = req.path;

  if (path == '/chains') {
    return switch (req.method) {
      'GET' => _list(),
      'POST' => _create(req, ctx),
      _ => throw BadRequest('method ${req.method} not allowed on /chains'),
    };
  }

  if (path.startsWith('/chains/')) {
    var tag = path.substring('/chains/'.length);



    if (tag.endsWith('/probe')) {
      tag = tag.substring(0, tag.length - '/probe'.length);
      if (tag.isEmpty || tag.contains('/')) {
        throw NotFound('chains path: $path');
      }
      if (req.method != 'GET') {
        throw BadRequest(
            'method ${req.method} not allowed on /chains/{tag}/probe');
      }
      return _probe(tag, req, ctx);
    }
    if (tag.isEmpty || tag.contains('/')) {
      throw NotFound('chains path: $path');
    }
    return switch (req.method) {
      'GET' => _single(tag),
      'PATCH' => _update(tag, req, ctx),
      'DELETE' => _delete(tag, req, ctx),
      _ => throw BadRequest('method ${req.method} not allowed on /chains/{tag}'),
    };
  }

  throw NotFound('chains path: $path');
}




ChainLayerProbe Function() chainProbeFactory = ChainLayerProbe.new;


















Future<DebugResponse> _probe(
    String tag, DebugRequest req, DebugContext ctx) async {
  final chains = await SettingsStorage.getChains();
  if (!chains.any((c) => c.tag == tag)) throw NotFound('chain: $tag');

  final config = ctx.home?.state.configModel ?? const ParsedConfig.empty();
  final hops = chainHopsFromConfig(config[tag]?.raw);
  if (hops == null) {




    throw Conflict('chain "$tag" is not in the built config — '
        'it is disabled, degraded at build time, or the config was never '
        'built; there is nothing running to probe');
  }
  if (hops.isEmpty) throw Conflict('chain "$tag" has no positions');




  final url = req.q('url');
  final timeoutMs = req.qInt('timeout_ms');
  if (timeoutMs != null && timeoutMs <= 0) {
    throw const BadRequest('query param "timeout_ms" must be > 0');
  }

  final ChainProbeReport report;
  try {
    report = await chainProbeFactory().run(tag, hops: hops,
        url: url, timeoutMs: timeoutMs);
  } on ChainProbeUnavailable catch (e) {


    if (e.isVpnDown) {
      throw const Conflict(
          'VPN is down — chain hops exist only in the running core');
    }
    throw Conflict('chain probe unavailable: ${e.reason}');
  }

  return JsonResponse({
    'ok': true,
    'action': 'chain-probe',
    'tag': tag,
    'url': report.url,
    'timeout_ms': report.timeoutMs,
    'layers': [
      for (var i = 0; i < report.layers.length; i++)
        {
          'pos': report.layers[i].pos,



          'tag': report.layers[i].tag,
          'probe_tag': report.layers[i].probeTag,
          if (report.layers[i].ok)
            'cumulative_ms': report.layers[i].cumulativeMs,



          if (report.deltaAt(i) != null) 'delta_ms': report.deltaAt(i),
          if (report.layers[i].error.isNotEmpty)
            'error': report.layers[i].error,
          if (report.layers[i].notReached) 'not_reached': true,
        },
    ],
  });
}

Future<DebugResponse> _list() async {
  final chains = await SettingsStorage.getChains();
  return JsonResponse(chains.map(serializeChain).toList());
}

Future<DebugResponse> _single(String tag) async {
  final chains = await SettingsStorage.getChains();
  final c = chains.where((c) => c.tag == tag).firstOrNull;
  if (c == null) throw NotFound('chain: $tag');
  return JsonResponse(serializeChain(c));
}















Future<DebugResponse> _create(DebugRequest req, DebugContext ctx) async {
  final body = req.jsonBodyAsMap();
  final label = fieldString(body, 'label');
  final tag = fieldString(body, 'tag');

  final existing = await SettingsStorage.getChains();
  final wanted = (tag ?? nextChainTag([
    ...existing.map((c) => c.tag),
    ...(await SettingsStorage.getDirections()).map((d) => d.tag),
  ]))
      .trim();


  var chain = SourceChain(tag: wanted, label: label ?? wanted, enabled: true);
  chain = _applyPatch(chain, body, tagConsumed: true) ?? chain;






  if (chain.hops.isNotEmpty) await _requireValid(chain, ctx, isNew: true);

  final SourceChain created;
  try {
    created = await SettingsStorage.createChain(chain);
  } on StateError catch (e) {


    throw Conflict(e.message);
  }

  final extras = await maybeRebuild(req, ctx);
  return JsonResponse({...serializeChain(created), ...extras}, status: 201);
}

Future<DebugResponse> _update(String tag, DebugRequest req, DebugContext ctx) async {
  final body = req.jsonBodyAsMap();
  final chains = await SettingsStorage.getChains();
  final chain = chains.where((c) => c.tag == tag).firstOrNull;
  if (chain == null) throw NotFound('chain: $tag');

  final next = _applyPatch(chain, body) ?? chain;


  if (next.hops.isNotEmpty) await _requireValid(next, ctx);
  try {
    await SettingsStorage.updateChain(next);
  } on StateError catch (e) {
    throw Conflict(e.message);
  }
  final extras = await maybeRebuild(req, ctx);
  return JsonResponse({...serializeChain(next), ...extras});
}

Future<DebugResponse> _delete(String tag, DebugRequest req, DebugContext ctx) async {
  final chains = await SettingsStorage.getChains();
  if (!chains.any((c) => c.tag == tag)) throw NotFound('chain: $tag');



  final healed = await SettingsStorage.deleteChain(tag);
  final extras = await maybeRebuild(req, ctx);
  return JsonResponse({
    'ok': true,
    'action': 'chains-delete',
    'tag': tag,



    'healed': {'chain_positions': healed.positions},
    'chains_touched': healed.touched,
    ...extras,
  });
}







Future<void> _requireValid(
  SourceChain chain,
  DebugContext ctx, {
  bool isNew = false,
}) async {
  final chains = await SettingsStorage.getChains();
  final directions = await SettingsStorage.getDirections();








  final ordered = isNew
      ? [...chains, chain]
      : [
          for (final c in chains)
            if (c.tag == chain.tag) chain else c,
        ];
  final config = ctx.home?.state.configModel ?? const ParsedConfig.empty();

  final lists = [
    for (final e in ctx.sub?.entries ?? const <SubscriptionEntry>[]) e.list,
  ];
  final pool = computeNodeLinkPool(lists, directions: directions);
  final candidates = chainHopLookup(collectChainHopTargets(
    config: config,
    directions: directions,
    chains: ordered,
    selfTag: chain.tag,
    pool: pool,
  ));
  final issues = validateChainForm(
    ChainFormState.of(chain, pool: pool, lists: lists),
    ChainFormContext(
      candidates: candidates,
      targetsKnown: chainTargetsKnown(config),


      takenTags: {
        for (final d in directions) d.tag,
        for (final c in ordered)
          if (c.tag != chain.tag) c.tag,
        for (final t in config.byTag.keys)
          if (t != chain.tag) t,
      },
      originalTag: chain.tag,
    ),
  );
  final blocker = issues.where((i) => i.blocks).firstOrNull;
  if (blocker != null) {
    throw BadRequest('chain ${chain.tag} rejected '
        '(${blocker.code.name}): ${blocker.message}');
  }
}




SourceChain? _applyPatch(SourceChain c, Map<String, dynamic> body,
    {bool tagConsumed = false}) {



  if (!tagConsumed && body.containsKey('tag')) {
    throw const BadRequest(
        'field "tag" is immutable (outbound id, edit "label" instead)');
  }

  final label = fieldString(body, 'label');
  final enabled = fieldBool(body, 'enabled');


  final hops = fieldNodeLinkList(body, 'hops');
  final idleTimeout = fieldString(body, 'idle_timeout');




  var clearStripEvasion = false;
  bool? stripEvasion;
  if (body.containsKey('strip_evasion')) {
    final raw = body['strip_evasion'];
    if (raw == null) {
      clearStripEvasion = true;
    } else if (raw is bool) {
      stripEvasion = raw;
    } else {
      throw BadRequest(
          'field "strip_evasion" must be bool or null, got ${raw.runtimeType}');
    }
  }





  Map<String, bool>? strip;
  if (body.containsKey('strip')) {
    final raw = body['strip'];
    if (raw is! Map) {
      throw BadRequest('field "strip" must be object, got ${raw.runtimeType}');
    }
    strip = {};
    for (final e in raw.entries) {
      final key = e.key;
      if (key is! String || !chainStripKeyKnown(key)) {
        throw BadRequest('field "strip": unknown key "$key" '
            '(allowed: ${chainStripKeys().join(', ')})');
      }
      final v = e.value;
      if (v is! bool) {
        throw BadRequest(
            'field "strip.$key" must be bool, got ${v.runtimeType}');
      }
      strip[key] = v;
    }
  }




  Map<String, dynamic>? rewrite;
  if (body.containsKey('rewrite')) {
    final raw = body['rewrite'];
    if (raw is! Map) {
      throw BadRequest('field "rewrite" must be object, got ${raw.runtimeType}');
    }
    rewrite = <String, dynamic>{};
    for (final e in raw.entries) {
      final key = e.key;
      if (key is! String) {
        throw BadRequest('field "rewrite" keys must be strings, got ${key.runtimeType}');
      }
      rewrite[key] = e.value;
    }
  }

  final changed = label != null ||
      enabled != null ||
      hops != null ||
      idleTimeout != null ||
      stripEvasion != null ||
      clearStripEvasion ||
      strip != null ||
      rewrite != null;
  if (!changed) return null;

  return c.copyWith(
    label: label,
    enabled: enabled,
    hops: hops,
    idleTimeout: idleTimeout,
    stripEvasion: stripEvasion,
    clearStripEvasion: clearStripEvasion,
    strip: strip,
    rewrite: rewrite,
  );
}
