








library;

import '../../../models/node_warning.dart';
import '../../contract/body_sanitizer.dart' show BodySource;
import '../drop_verdict.dart';
import '../mappers/uri_mapper.dart';
import 'interpreter.dart';
import 'section_loader.dart';








UriMapping? mapViaEngine(String uri, String singboxType,
    {XrayDropVerdict? dropped}) {
  final section = MapperSections.I.sectionFor('uri', singboxType);
  if (section == null) return null;
  final res = runSection(section, uri, dropped: dropped);
  if (res == null) return null;
  return UriMapping(
    body: res.body,
    label: res.label,
    warnings: res.warnings,
    extensionFields: res.extensionFields,
    wsEarlyDataHeaderImplicit: res.wsEarlyDataHeaderImplicit,
    tagAddress: res.tagAddress,



    kinds: res.kinds,


    bodySource: BodySource.byRegistryName(res.bodySource),
  );
}















UriMapping? mapIniViaEngine(
  String text,
  String singboxType, {
  String? nameHint,
  XrayDropVerdict? dropped,
  Map<String, dynamic>? context,
}) {
  final section = MapperSections.I.sectionFor('conf', singboxType);
  if (section == null) return null;
  final res = runSectionOnIni(section, text,
      nameHint: nameHint, dropped: dropped, context: context);
  if (res == null) return null;
  return UriMapping(
    body: res.body,
    label: res.label,
    warnings: res.warnings,
    extensionFields: res.extensionFields,
    tagAddress: res.tagAddress,
    kinds: res.kinds,
    bodySource: BodySource.byRegistryName(res.bodySource),
  );
}






final class JsonMapping {
  const JsonMapping({
    required this.body,
    this.warnings = const [],
    this.wsEarlyDataHeaderImplicit = false,
    this.tagScheme,
  });

  final Map<String, dynamic> body;
  final List<NodeWarning> warnings;
  final bool wsEarlyDataHeaderImplicit;



  final String? tagScheme;
}












JsonMapping? mapJsonViaEngine(String kind, Map<String, dynamic> element,
    {XrayDropVerdict? dropped, List<dynamic>? document}) {
  final section = MapperSections.I.matchJson(kind, element);
  if (section == null) {



    if (dropped != null && dropped.reason == null) {
      dropped.reason = const RegistryWarning(code: 'protocol_unsupported');
    }
    return null;
  }
  final res = runSectionOnJson(section, element,
      dropped: dropped, document: document);
  if (res == null) return null;
  return JsonMapping(
    body: res.body,
    warnings: res.warnings,
    wsEarlyDataHeaderImplicit: res.wsEarlyDataHeaderImplicit,
    tagScheme: res.tagScheme,
  );
}
