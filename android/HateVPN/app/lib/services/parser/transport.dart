import 'dart:convert';

import '../../models/node_warning.dart';
import '../../models/transport_spec.dart';
import 'uri_utils.dart';











TransportSpec? parseTransport(
  Map<String, String> q, {
  String? networkOverride,
  String? defaultHost,
  List<NodeWarning>? warnings,
}) {
  var typ = ((networkOverride ?? q['type']) ?? '').toLowerCase().trim();
  final headerType = (q['headerType'] ?? '').toLowerCase().trim();

  if ((typ == 'raw' || typ == 'tcp') && headerType == 'http') {
    final path = _guardUrlPath(q['path'] ?? '/', warnings);
    final host = q['host'] ?? '';
    return HttpTransport(
      path: path,
      hosts: host.isNotEmpty ? [host] : const [],
    );
  }

  switch (typ) {
    case 'ws':







      final pathParamPresent = q.containsKey('path');
      final (splitPath, edFromPath) =
          splitEarlyDataPath(decodeResidualPercent(q['path'] ?? ''));
      final path =
          pathParamPresent ? _guardUrlPath(splitPath, warnings) : '';
      var host = (q['host'] ?? '').trim();
      if (host.isEmpty) host = (q['sni'] ?? '').trim();
      if (host.isEmpty) host = (q['obfsParam'] ?? '').trim();


      final ed = edFromPath ?? _positiveInt(q['ed']);


      var eh = ed == null ? null : _nonEmpty(q['eh']);







      var ehImplicit = false;
      if (eh == null && edFromPath != null) {
        eh = 'Sec-WebSocket-Protocol';
        ehImplicit = true;
      }



      if (edFromPath != null) {
        warnings?.add(NodeWarning.byCode('ws_early_data_converted',
            path: 'path', value: '$edFromPath'));
      }
      return WsTransport(
        path: path,
        host: host,
        earlyDataHeaderImplicit: ehImplicit,
        maxEarlyData: ed,
        earlyDataHeaderName: eh,
      );
    case 'grpc':






      final sn = (q['serviceName'] ?? q['service_name'] ?? q['path'] ?? '').trim();
      return GrpcTransport(serviceName: sn);
    case 'http':
      final path = _guardUrlPath(q['path'] ?? '/', warnings);
      final host = (q['host'] ?? '').trim();
      return HttpTransport(
        path: path,
        hosts: host.isNotEmpty ? [host] : const [],
      );
    case 'h2':






      if (networkOverride == null) return null;
      final path = _guardUrlPath(q['path'] ?? '/', warnings);
      var host = (q['host'] ?? '').trim();
      if (host.isEmpty) host = (q['sni'] ?? '').trim();
      if (host.isEmpty && defaultHost != null) host = defaultHost;
      return HttpTransport(
        path: path,
        hosts: host.isNotEmpty ? [host] : const [],
      );
    case 'httpupgrade':




      final hasPathParam = q.containsKey('path');
      final (splitPath, _) =
          splitEarlyDataPath(decodeResidualPercent(q['path'] ?? ''));
      final path = hasPathParam ? _guardUrlPath(splitPath, warnings) : '';



      final host = (q['host'] ?? '').trim();
      return HttpUpgradeTransport(path: path, host: host);




    case 'splithttp':
    case 'xhttp':




      return xhttpFromMap(mergeXhttpExtra(q));
    case 'raw':
    case 'tcp':
    case '':
      return null;
    default:
      return null;
  }
}












String _guardUrlPath(String path, List<NodeWarning>? warnings) {
  if (path.isEmpty || urlPathOk(path)) return path;
  warnings?.add(RegistryWarning(
    code: 'type_invalid',
    path: 'transport.path',
    value: path,
  ));
  return '';
}







(String, int?) splitEarlyDataPath(String raw) {
  final qIdx = raw.indexOf('?');
  if (qIdx < 0) return (raw.isEmpty ? '/' : raw, null);

  var path = raw.substring(0, qIdx);
  if (path.isEmpty) path = '/';




  String? ed;
  try {
    ed = Uri.splitQueryString(raw.substring(qIdx + 1))['ed'];
  } catch (_) {
    ed = null;
  }
  final parsed = ed == null ? null : int.tryParse(ed.trim());
  return (path, parsed != null && parsed > 0 ? parsed : null);
}










final _percentSeq = RegExp(r'%[0-9A-Fa-f]{2}');

String decodeResidualPercent(String raw) {
  var v = raw;
  var guard = 0;
  while (_percentSeq.hasMatch(v) && guard < 2) {
    final decoded = Uri.tryParse('x://x?a=$v')?.queryParameters['a'];
    if (decoded == null || decoded == v) break;
    v = decoded;
    guard++;
  }
  return v;
}


int? _positiveInt(String? v) {
  final n = int.tryParse((v ?? '').trim());
  return n != null && n > 0 ? n : null;
}


String? _nonEmpty(String? v) {
  final s = (v ?? '').trim();
  return s.isEmpty ? null : s;
}

















XhttpTransport xhttpFromMap(
  Map<String, String> m, {
  Map<String, String> headers = const {},
}) {








  final hasPathKey = m.containsKey('path');
  final (splitPath, _) = splitEarlyDataPath(m['path'] ?? '');
  final path = hasPathKey ? splitPath : '';




  final host = (m['host'] ?? '').trim();

  return XhttpTransport(
    path: path,
    host: host,
    mode: (m['mode'] ?? '').trim(),
    xPaddingBytes: _pick(m, 'xPaddingBytes', 'x_padding_bytes'),
    noGrpcHeader: _truthy(m['noGRPCHeader'] ?? m['no_grpc_header']),
    headers: headers,
    sessionPlacement: _pick(m, 'sessionPlacement', 'session_placement'),
    sessionKey: _pick(m, 'sessionKey', 'session_key'),
    seqPlacement: _pick(m, 'seqPlacement', 'seq_placement'),
    seqKey: _pick(m, 'seqKey', 'seq_key'),
    uplinkDataPlacement: _pick(m, 'uplinkDataPlacement', 'uplink_data_placement'),
    uplinkDataKey: _pick(m, 'uplinkDataKey', 'uplink_data_key'),
    uplinkChunkSize: _pick(m, 'uplinkChunkSize', 'uplink_chunk_size'),
    uplinkHttpMethod: _pick(m, 'uplinkHTTPMethod', 'uplink_http_method'),
    xPaddingObfsMode:
        _truthy(m['xPaddingObfsMode'] ?? m['x_padding_obfs_mode']),
    xPaddingKey: _pick(m, 'xPaddingKey', 'x_padding_key'),
    xPaddingHeader: _pick(m, 'xPaddingHeader', 'x_padding_header'),
    xPaddingPlacement: _pick(m, 'xPaddingPlacement', 'x_padding_placement'),
    xPaddingMethod: _pick(m, 'xPaddingMethod', 'x_padding_method'),
    scMaxEachPostBytes:
        _normScRange(_pick(m, 'scMaxEachPostBytes', 'sc_max_each_post_bytes')),
    scMinPostsIntervalMs: _normScRange(
        _pick(m, 'scMinPostsIntervalMs', 'sc_min_posts_interval_ms')),
    scStreamUpServerSecs: _normScRange(
        _pick(m, 'scStreamUpServerSecs', 'sc_stream_up_server_secs')),
    scMaxBufferedPosts:
        _pickInt(m, 'scMaxBufferedPosts', 'sc_max_buffered_posts'),
    noSseHeader: _truthy(m['noSSEHeader'] ?? m['no_sse_header']),


    maxConnections: _pick(m, 'maxConnections', 'max_connections'),
    maxConcurrency: _pick(m, 'maxConcurrency', 'max_concurrency'),
    cMaxReuseTimes: _pick(m, 'cMaxReuseTimes', 'c_max_reuse_times'),
    hMaxRequestTimes: _pick(m, 'hMaxRequestTimes', 'h_max_request_times'),
    hMaxReusableSecs: _pick(m, 'hMaxReusableSecs', 'h_max_reusable_secs'),
    hKeepAlivePeriod: _pickInt(m, 'hKeepAlivePeriod', 'h_keep_alive_period'),
  );
}






int _pickInt(Map<String, String> m, String camel, String snake) {
  final raw = _pick(m, camel, snake);
  if (raw.isEmpty) return -1;
  final i = int.tryParse(raw);
  if (i != null) return i;
  final d = double.tryParse(raw);
  if (d != null) return d.toInt();
  return -1;
}









Map<String, String> xhttpScalarsFromJson(Map raw) {
  final out = <String, String>{};
  raw.forEach((k, v) {
    if (k is! String || v == null) return;
    if (v is Map) {
      if (k.toLowerCase() == 'xmux') {
        v.forEach((nk, nv) {
          if (nk is! String || nv == null || nv is Map || nv is List) return;
          out[nk] = _scalarToString(nv);
        });
      }
      return;
    }
    if (v is List) return;
    out[k] = _scalarToString(v);
  });
  return out;
}




const _xhttpFlatOnlyKeys = {'host', 'path', 'mode'};



























Map<String, String> mergeXhttpExtra(Map<String, String> q, {Object? raw}) {
  final src = raw ?? q['extra'];
  if (src == null) return q;

  Map? decoded;
  if (src is Map) {
    decoded = src;
  } else {
    final s = src.toString().trim();
    if (s.isEmpty) return q;
    try {
      final parsed = jsonDecode(s);
      if (parsed is Map) decoded = parsed;
    } catch (_) {

      return q;
    }
  }
  if (decoded == null) return q;

  final merged = Map<String, String>.from(q);
  decoded.forEach((k, v) {
    if (k is! String || v == null) return;

    if (_xhttpFlatOnlyKeys.contains(k.toLowerCase())) return;
    if (v is Map) {






      if (k.toLowerCase() == 'xmux') {
        v.forEach((nk, nv) {
          if (nk is! String || nv == null || nv is Map || nv is List) return;
          final s = _scalarToString(nv);
          if (s.isNotEmpty) merged[nk] = s;
        });
      }
      return;
    }
    if (v is List) return;

    final s = _scalarToString(v);
    if (s.isNotEmpty) merged[k] = s;
  });
  return merged;
}






String _scalarToString(Object v) {
  if (v is bool) return v ? 'true' : 'false';
  if (v is double && v == v.truncateToDouble()) {
    return v.toInt().toString();
  }
  return v.toString();
}


String _pick(Map<String, String> q, String camel, String snake) =>
    (q[camel] ?? q[snake] ?? '').trim();



String _normScRange(String v) {
  if (v.isEmpty) return v;
  final d = double.tryParse(v);
  if (d != null && d == d.truncateToDouble()) return d.toInt().toString();
  return v;
}






















void warnEchIgnored(Map<String, String> q, List<NodeWarning> warnings) {
  final raw = (q['ech'] ?? '').trim();
  if (raw.isEmpty || raw.toLowerCase() == 'none') return;
  warnings.add(NodeWarning.byCode('ech_ignored',
      path: 'ech', value: raw.split('+').first.trim()));
}


bool _truthy(String? v) {
  final s = (v ?? '').toLowerCase().trim();
  return s == 'true' || s == '1';
}
