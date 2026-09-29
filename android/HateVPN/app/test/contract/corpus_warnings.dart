import '../contract_paths.dart';

import 'dart:convert';
import 'dart:io';

import 'package:lxbox/models/node_warning.dart';
import 'package:lxbox/services/contract/warning_codes.dart';






















String? _legacyWarningPath(NodeWarning w) => handwrittenWarningPath(w);











String? _legacyWarningValue(NodeWarning w) => switch (w) {
      PacketEncodingUnknownWarning(:final value) => value,
      UnknownFingerprintWarning(:final value) => value,
      RealityFingerprintWarning(:final value) => value,
      UnknownObfsWarning(:final value) => value,


      XhttpParamResetWarning(:final value) => value,
      _ => null,
    };






Map<String, dynamic>? warningRecordOf(NodeWarning w) {
  final code = warningCodeOf(w);
  if (code == null) return null;

  final String? path;
  final String? value;
  final Map<String, String> params;
  if (w is RegistryWarning) {


    path = w.path;
    value = w.value;
    params = w.params;
  } else {
    path = _legacyWarningPath(w);
    value = _legacyWarningValue(w);
    params = const {};
  }

  return <String, dynamic>{
    'code': code,
    if (path != null && path.isNotEmpty) 'path': path,
    if (value != null && value.isNotEmpty) 'value': value,
    if (params.isNotEmpty) 'params': params,

    if (!w.applied) 'applied': false,
  };
}













final _bodyOrderCache = <String, List<String>>{};

List<String> _bodyOrderFor(String scheme) => _bodyOrderCache.putIfAbsent(
      scheme,
      () {
        final f = File('$kContractRoot/registry/protocols/$scheme.json');
        if (!f.existsSync()) return const <String>[];
        final data = json.decode(f.readAsStringSync()) as Map<String, dynamic>;
        final body = data['body'];
        if (body is! Map) return const <String>[];
        return ((body['order'] as List?) ?? const []).cast<String>();
      },
    );












final _mapperOnlyPathsCache = <String, Set<String>>{};

Set<String> _mapperOnlyPathsFor(String scheme) =>
    _mapperOnlyPathsCache.putIfAbsent(scheme, () {
      final f = File('$kContractRoot/registry/protocols/$scheme.json');
      if (!f.existsSync()) return const <String>{};
      final data = json.decode(f.readAsStringSync()) as Map<String, dynamic>;
      final mappers = data['mappers'];
      if (mappers is! Map) return const <String>{};
      final out = <String>{};
      for (final section in mappers.values) {
        if (section is! Map) continue;
        final params = section['params'];
        if (params is! Map) continue;
        for (final e in params.entries) {
          final p = e.value;
          if (p is! Map) continue;


          if (p.containsKey('maps_to') && p['maps_to'] == null) {
            out.add('${e.key}');
          }
        }
      }



      for (final shared in const ['tls', 'transports', 'dialer', 'multiplex']) {
        final sf = File('$kContractRoot/registry/$shared.json');
        if (!sf.existsSync()) continue;
        final blocks = (json.decode(sf.readAsStringSync()) as Map)['blocks'];
        if (blocks is! Map) continue;
        for (final block in blocks.values) {
          if (block is! Map) continue;
          for (final e in block.entries) {
            final p = e.value;
            if (p is Map && p.containsKey('maps_to') && p['maps_to'] == null) {
              out.add('${e.key}');
            }
          }
        }
      }
      return out;
    });

final _mapperUnknownCodesCache = <String, Set<String>>{};

Set<String> _mapperUnknownCodesFor(String scheme) =>
    _mapperUnknownCodesCache.putIfAbsent(scheme, () {
      final f = File('$kContractRoot/registry/protocols/$scheme.json');
      if (!f.existsSync()) return const <String>{};
      final data = json.decode(f.readAsStringSync()) as Map<String, dynamic>;
      final mappers = data['mappers'];
      if (mappers is! Map) return const <String>{};
      return {
        for (final section in mappers.values)
          if (section is Map &&
              section['unknown_key'] is Map &&
              (section['unknown_key'] as Map)['code'] is String)
            (section['unknown_key'] as Map)['code'] as String,
      };
    });

void sortWarningsByBodyOrder(
    List<Map<String, dynamic>> warnings, String scheme) {
  if (warnings.length < 2) return;
  final order = _bodyOrderFor(scheme);
  if (order.isEmpty) return;
  final mapperOnly = _mapperOnlyPathsFor(scheme);
  int rank(Map<String, dynamic> w) {
    final path = w['path'];
    if (path is! String || path.isEmpty) return 1 << 20;


    if (mapperOnly.contains(path)) return -1;


    final head = path.split('.').first.split('[').first;
    final i = order.indexOf(head);
    if (i >= 0) return i;




    if (_mapperUnknownCodesFor(scheme).contains(w['code'])) return -1;
    return 1 << 20;
  }


  final indexed = [
    for (var i = 0; i < warnings.length; i++) (i, warnings[i]),
  ]..sort((a, b) {
      final d = rank(a.$2).compareTo(rank(b.$2));
      return d != 0 ? d : a.$1.compareTo(b.$1);
    });
  warnings
    ..clear()
    ..addAll(indexed.map((e) => e.$2));
}
















List<Map<String, dynamic>> warningListOf(
    Iterable<NodeWarning> source, String scheme) {
  final warnings = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final w in source) {
    final rec = warningRecordOf(w);
    if (rec == null) continue;
    if (!seen.add('${rec['code']} ${rec['path'] ?? ''}')) continue;
    warnings.add(rec);
  }
  sortWarningsByBodyOrder(warnings, scheme);
  return warnings;
}














void normalizeWarnings(Map<String, dynamic> got, Map<String, dynamic> want) {
  final gotNodes = nodeList(got, 'nodes');
  final wantNodes = nodeList(want, 'nodes');
  for (var i = 0; i < gotNodes.length; i++) {
    normalizeNodeWarnings(
        gotNodes[i], i < wantNodes.length ? wantNodes[i] : null);
  }


  for (final wn in wantNodes) {
    normalizeNodeWarnings(wn, null);
  }
}

void normalizeNodeWarnings(
    Map<String, dynamic> node, Map<String, dynamic>? want) {
  final gotList = warningObjects(node);
  final wantList = want == null ? null : warningObjects(want);

  if (wantList != null) {
    for (var i = 0; i < gotList.length && i < wantList.length; i++) {



      if (!wantList[i].containsKey('path')) gotList[i].remove('path');
      if (!wantList[i].containsKey('value')) gotList[i].remove('value');
      if (!wantList[i].containsKey('params')) gotList[i].remove('params');
    }
  }


  final gotHops = nodeList(node, 'chain');
  final wantHops =
      want == null ? const <Map<String, dynamic>>[] : nodeList(want, 'chain');
  for (var i = 0; i < gotHops.length; i++) {
    normalizeNodeWarnings(gotHops[i], i < wantHops.length ? wantHops[i] : null);
  }
}



List<Map<String, dynamic>> warningObjects(Map<String, dynamic> node) {
  final list = node['warnings'];
  if (list is! List) return const [];
  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < list.length; i++) {
    final item = list[i];
    if (item is String) {
      final m = <String, dynamic>{'code': item};
      list[i] = m;
      out.add(m);
    } else if (item is Map<String, dynamic>) {
      out.add(item);
    }
  }
  return out;
}










void normalizeDrops(Map<String, dynamic> got, Map<String, dynamic> want) {
  final gotDrops = nodeList(got, 'dropped');
  final wantDrops = nodeList(want, 'dropped');
  for (var i = 0; i < gotDrops.length; i++) {
    gotDrops[i].remove('reason');
    if (i >= wantDrops.length || !wantDrops[i].containsKey('code')) {
      gotDrops[i].remove('code');
    }
  }
  for (final d in wantDrops) {
    d.remove('reason');
  }
}


List<Map<String, dynamic>> nodeList(Map<String, dynamic> m, String key) {
  final list = m[key];
  if (list is! List) return const [];
  return [for (final e in list) if (e is Map<String, dynamic>) e];
}



Object? deepCopyEnvelope(Object? v) {
  if (v is Map) {
    return <String, dynamic>{
      for (final e in v.entries) e.key as String: deepCopyEnvelope(e.value),
    };
  }
  if (v is List) return [for (final e in v) deepCopyEnvelope(e)];
  return v;
}





String canonEncode(Object? v) => json.encode(sortKeys(v));

Object? sortKeys(Object? v) {
  if (v is Map) {
    final keys = v.keys.cast<String>().toList()..sort();
    final out = <String, dynamic>{};
    for (final k in keys) {
      out[k] = sortKeys(v[k]);
    }
    return out;
  }
  if (v is List) {
    return [for (final val in v) sortKeys(val)];
  }
  return v;
}



String prettyPrintEnvelope(Map<String, dynamic> envelope) {
  final canon = sortKeys(envelope);
  const encoder = JsonEncoder.withIndent('  ');
  return '${encoder.convert(canon)}\n';
}
