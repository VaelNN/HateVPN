




























library;

import 'dart:convert';

import '../../models/node_spec.dart';
import '../../models/node_warning.dart';
import '../../models/template_vars.dart';
import '../parser/authored_scope.dart'
    show parsingAuthoredBody, singboxBodySource;
import '../parser/mappers/uri_pipeline.dart' show isPipelineParsed;
import 'body_edit.dart' show settleSanitized;
import 'body_sanitizer.dart';
import 'registry.dart';
import 'warning_codes.dart';






const _kParseTimeCore = '0.0.0';





void annotateWithRegistry(NodeSpec node) {
  if (!ContractRegistry.I.isLoaded) return;

  final chained = node.chained;
  if (chained != null) annotateWithRegistry(chained);


  if (node.isGroup) return;

  if (node is UnknownTypeSpec) return;







  if (isPipelineParsed(node)) return;

  final Map<String, dynamic> body;
  try {
    body = Map<String, dynamic>.from(node.emit(TemplateVars.empty).map);
  } catch (_) {


    return;
  }

  final type = body['type'];
  if (type is! String) return;

  final res = RegistrySanitizer.sanitize(
    body,
    scheme: type,
    coreVersion: _kParseTimeCore,
    applyCoreGates: false,





    source: bodySourceOf(node),
  );
  _mergeRegistryWarnings(node, res.warnings);
}































bool annotateFromRawBody(NodeSpec node) {
  if (!ContractRegistry.I.isLoaded) return false;

  final chained = node.chained;
  if (chained != null) annotateFromRawBody(chained);

  if (node.isGroup) return false;

  if (node is UnknownTypeSpec) return false;






  if (isPipelineParsed(node)) return false;

  final raw = _rawSingboxBodyOf(node);
  if (raw == null) return false;
  final type = raw['type'];
  if (type is! String) return false;



  final res = settleSanitized(
    type,
    raw,
    RegistrySanitizer.sanitize(


      (jsonDecode(jsonEncode(raw)) as Map).cast<String, dynamic>(),
      scheme: type,
      coreVersion: _kParseTimeCore,
      applyCoreGates: false,



      source: singboxBodySource,
    ),
    authored: parsingAuthoredBody,
  );
  _mergeRegistryWarnings(node, res.warnings);












  return res.explicitDropNode || (parsingAuthoredBody && res.body == null);
}




















BodySource bodySourceOf(NodeSpec node) =>
    _rawSingboxBodyOf(node)?['type'] is String
        ? singboxBodySource
        : BodySource.other;








Map<String, dynamic>? _rawSingboxBodyOf(NodeSpec node) {
  final src = node.rawSource.trimLeft();
  if (!src.startsWith('{')) return null;
  try {
    final v = jsonDecode(src);
    return v is Map<String, dynamic> ? v : null;
  } catch (_) {

    return null;
  }
}
















void _mergeRegistryWarnings(NodeSpec node, List<RegistryWarning> incoming) {
  if (incoming.isEmpty) return;



  final handwrittenAnywhere = <String>{};

  final seen = <String>{};
  for (final w in node.warnings) {
    final code = warningCodeOf(w);
    if (code == null) continue;
    if (w is RegistryWarning) {
      seen.add('$code ${w.path ?? ''}');
    } else {
      final path = handwrittenWarningPath(w);
      if (path == null) {
        handwrittenAnywhere.add(code);
      } else {
        seen.add('$code $path');
      }
    }
  }

  for (final w in incoming) {
    if (handwrittenAnywhere.contains(w.code)) continue;
    if (!seen.add('${w.code} ${w.path ?? ''}')) continue;
    node.warnings.add(w);
  }
}


void annotateAllWithRegistry(List<NodeSpec> nodes) {
  if (!ContractRegistry.I.isLoaded) return;
  for (final n in nodes) {
    annotateWithRegistry(n);
  }
}







List<NodeSpec> annotateAllFromRawBody(List<NodeSpec> nodes) {
  if (!ContractRegistry.I.isLoaded) return const [];
  final dropped = <NodeSpec>[];
  for (final n in nodes) {
    if (annotateFromRawBody(n)) dropped.add(n);
  }
  return dropped;
}
