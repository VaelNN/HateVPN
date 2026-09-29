


























library;

import '../../../models/node_spec.dart';
import '../../../models/node_warning.dart';
import '../drop_verdict.dart';
import '../../contract/body_sanitizer.dart';
import '../../contract/registry.dart';
import '../../../services/parser/engine/engine_mapper.dart';
import '../engine/section_loader.dart' show MapperSections;
import '../json_parsers.dart';
import '../uri_utils.dart';
import 'uri_mapper.dart';




const _kParseTimeCore = '0.0.0';










Set<String>? registryUriSchemes() => _schemeRoute().uriSchemes;


























final class _SchemeRoute {
  _SchemeRoute(this.types)
      : uriSchemes = _uriSchemesOf(types),
        typeByScheme = _typeBySchemeOf(types) {
    pipeline = Set.unmodifiable(typeByScheme.keys);
  }

  final List<String> types;



  final Set<String>? uriSchemes;


  late final Set<String> pipeline;




  final Map<String, String> typeByScheme;

  static Iterable<String> _schemeIn(String type) sync* {
    final si = MapperSections.I.sectionFor('uri', type)?.detect?['scheme_in'];
    if (si is! List) return;
    for (final s in si) {
      if (s is String && s.isNotEmpty) yield s.toLowerCase();
    }
  }

  static Iterable<String> _aliases(String type) sync* {
    final a = ContractRegistry.I.rawProtocol(type)?['aliases'];
    if (a is! List) return;
    for (final s in a) {
      if (s is String && s.isNotEmpty) yield s.toLowerCase();
    }
  }

  static Set<String>? _uriSchemesOf(List<String> types) {
    if (types.isEmpty) return null;
    final out = <String>{for (final type in types) ..._schemeIn(type)};
    return out.isEmpty ? null : Set.unmodifiable(out);
  }

  static Map<String, String> _typeBySchemeOf(List<String> types) {
    final out = <String, String>{};
    for (final type in types) {
      for (final s in _schemeIn(type)) {
        out.putIfAbsent(s, () => type);
      }
    }
    for (final type in types) {


      if (MapperSections.I.sectionFor('uri', type) == null) continue;
      for (final s in _aliases(type)) {
        out.putIfAbsent(s, () => type);
      }
    }
    return Map.unmodifiable(out);
  }
}

_SchemeRoute? _route;

_SchemeRoute _schemeRoute() {
  final types = MapperSections.I.typesFor('uri');
  final r = _route;
  if (r != null && identical(r.types, types)) return r;
  return _route = _SchemeRoute(types);
}




Object schemeRouteToken() => _schemeRoute();







Set<String> pipelineSchemes() => _schemeRoute().pipeline;






String? registrySchemeType(String scheme) =>
    _schemeRoute().typeByScheme[scheme.toLowerCase()];






const Map<String, UriMapper> _kMappers = <String, UriMapper>{};







NodeSpec? parseUriViaPipeline(String uri, String scheme,
    {XrayDropVerdict? dropped}) {







  final singboxType = registrySchemeType(scheme);
  if (singboxType != null) {


    final mapping = mapViaEngine(uri, singboxType, dropped: dropped);
    if (mapping == null) return null;
    return _runPipeline(uri, null, mapping: mapping, dropped: dropped);
  }

  final mapper = _kMappers[scheme];
  if (mapper == null) return null;



  return _runPipeline(uri, mapper, dropped: dropped);
}








NodeSpec? parseLinkViaPipeline(String uri, {XrayDropVerdict? dropped}) {
  final sep = uri.indexOf('://');
  if (sep <= 0) return null;
  return parseUriViaPipeline(uri, uri.substring(0, sep), dropped: dropped);
}
















NodeSpec? parseIniViaPipeline(
  String source,
  String singboxType, {
  String? nameHint,
  XrayDropVerdict? dropped,
}) {
  final mapping =
      mapIniViaEngine(source, singboxType, nameHint: nameHint, dropped: dropped);
  if (mapping == null) return null;
  return _runPipeline(source, null, mapping: mapping, dropped: dropped);
}




















NodeSpec? parseXrayViaPipeline(
  Map<String, dynamic> body, {
  required String rawSource,
  required String label,
  bool wsEarlyDataHeaderImplicit = false,
  List<NodeWarning>? warnings,
  String? tagScheme,
  XrayDropVerdict? dropped,
}) =>
    _runPipeline(
      rawSource,
      null,
      prebuilt: _Prebuilt(
        body: body,
        label: label,
        warnings: warnings ?? const [],
        wsEarlyDataHeaderImplicit: wsEarlyDataHeaderImplicit,
        tagScheme: tagScheme,
      ),
      dropped: dropped,
    );


final class _Prebuilt {
  const _Prebuilt({
    required this.body,
    required this.label,
    required this.warnings,
    required this.wsEarlyDataHeaderImplicit,
    this.tagScheme,
  });

  final Map<String, dynamic> body;
  final String label;
  final List<NodeWarning> warnings;
  final bool wsEarlyDataHeaderImplicit;


  final String? tagScheme;
}







NodeSpec? _runPipeline(
  String source,
  UriMapper? mapper, {
  _Prebuilt? prebuilt,
  XrayDropVerdict? dropped,
  UriMapping? mapping,
}) {
  mapping ??= prebuilt == null
      ? mapper!(source)
      : UriMapping(
          body: prebuilt.body,
          label: prebuilt.label,
          warnings: prebuilt.warnings,
          wsEarlyDataHeaderImplicit: prebuilt.wsEarlyDataHeaderImplicit,
        );
  if (mapping == null) return null;

  final warnings = <NodeWarning>[...mapping.warnings];










  var body = mapping.body;
  if (mapping.extensionFields.isNotEmpty) {
    body = {...body, ...mapping.extensionFields};
  }




  if (ContractRegistry.I.isLoaded) {
    final res = RegistrySanitizer.sanitize(
      body,
      scheme: body['type'] as String,
      coreVersion: _kParseTimeCore,
      applyCoreGates: false,












      source: mapping.bodySource,




      kinds: mapping.kinds,
    );

    if (res.body == null) {


      if (dropped != null) {
        dropped.explicit = res.explicitDropNode;
        for (final w in res.warnings) {
          if (ContractRegistry.I.textFor(w.code)?.severity == 'error') {
            dropped.reason = w;
            break;
          }
        }



        dropped.reason ??=
            res.warnings.isNotEmpty ? res.warnings.first : null;
      }
      return null;
    }
    body = res.body!;
    warnings.addAll(res.warnings);
  }















  if (!ContractRegistry.I.isLoaded &&
      (mapping.kinds.contains('awg') || mapping.kinds.contains('awg3'))) {
    final type = body['type'] as String? ?? '';
    final ceiling = awgMtuCeilingByRegistry(type);
    if (ceiling != null) {
      final written = body['mtu'];
      if (written == null) {


        body['mtu'] = ceiling;
      } else if (written is num && written > ceiling) {
        warnings.add(RegistryWarning(
          code: awgMtuClampCodeByRegistry(type) ?? 'awg_mtu_clamped',
          path: 'mtu',
          value: RegistrySanitizer.renderWarningValue(written),
        ));
        body['mtu'] = ceiling;
      }
    }
  }

















  final (server, port) = mapping.tagAddress ??
      (
        body['server']?.toString() ?? '',
        (body['server_port'] as num?)?.toInt() ?? 0,
      );



  body['tag'] = tagFromLabel(
    mapping.label,
    prebuilt?.tagScheme ?? body['type'] as String,
    server,
    port,
  );










  final node = parseSingboxEntry(
    body,
    rawSource: source,
    label: mapping.label,
    wsEarlyDataHeaderImplicit: mapping.wsEarlyDataHeaderImplicit,
    sanitizedFrom: mapping.bodySource,
  );
  if (node == null) return null;






  if (mapping.bodySource == BodySource.uri) {
    final delta = node.bodyDelta;
    final foreign = _foreignSideParamPaths(body['type'] as String);
    if (delta != null && foreign.isNotEmpty) {
      node.bodyDelta = delta.withoutAdds(foreign);
    }
  }

  node.warnings.addAll(warnings);
  markPipelineParsed(node);
  return node;
}
























final _pipelineParsed = Expando<bool>('§472 разобран конвейером');

void markPipelineParsed(NodeSpec node) => _pipelineParsed[node] = true;


bool isPipelineParsed(NodeSpec node) => _pipelineParsed[node] == true;



const _kThisSideExt = 'mobile';



Set<String> _foreignSideParamPaths(String type) {
  if (!ContractRegistry.I.isLoaded) return const {};
  final query =
      ((ContractRegistry.I.rawProtocol(type)?['uri'] as Map?)?['query'] as Map?);
  if (query == null) return const {};
  return {
    for (final e in query.values)
      if (e is Map &&
          e['ext'] is String &&
          e['ext'] != _kThisSideExt &&
          e['maps_to'] is String)
        e['maps_to'] as String,
  };
}
