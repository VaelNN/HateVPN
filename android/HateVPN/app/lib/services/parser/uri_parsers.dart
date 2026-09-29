import '../../models/node_spec.dart';
import '../../models/node_warning.dart';
import 'amnezia_link.dart';
import 'mappers/uri_pipeline.dart';
export 'drop_verdict.dart' show XrayDropVerdict;

import 'drop_verdict.dart';
import 'engine/interpreter.dart' show formMatchesText;
import 'engine/section_loader.dart' show MapperSections;
import 'uri_utils.dart';




export 'mappers/uri_pipeline.dart' show parseLinkViaPipeline;





bool _isContainerLine(String line) {
  final src = MapperSections.I.documents?.sourceByKind('amnezia_link');
  if (src == null || src.detect == null) return false;
  return formMatchesText(src.detect, line);
}





List<NodeSpec>? parseContainerLineAll(String line,
    {List<XrayDropVerdict>? verdicts}) {
  final t = line.trim();
  if (t.length > maxAmneziaLinkLength || !_isContainerLine(t)) return null;
  return parseAmneziaVpnUriAll(t, verdicts: verdicts);
}










String? _serviceSchemeCode(String line) => MapperSections.I.documents
    ?.sourceByKind('uri_lines')
    ?.serviceSchemeCode(line);










NodeSpec? parseUri(String uri, {XrayDropVerdict? dropped}) {
  final node = _parseUriInner(uri, dropped: dropped);
  if (node == null) return null;









  final banner = _providerBannerWarning(node, uri);
  if (banner != null) {
    dropped?.explicit = true;
    dropped?.reason = banner;
    return null;
  }
  return node;
}





RegistryWarning? _providerBannerWarning(NodeSpec node, String uri) {
  final src = MapperSections.I.documents?.sourceByKind('uri_lines');
  if (src == null || !src.isBannerTarget(node.server)) return null;
  final code = src.bannerCode;
  if (code == null || code.isEmpty) return null;
  return RegistryWarning(
    code: code,
    params: {'message': node.tag},
    value: node.server,
  );
}

NodeSpec? _parseUriInner(String uri, {XrayDropVerdict? dropped}) {
  final t = uri.trim();
  if (t.isEmpty) return null;
  final scheme = t.split('://').first.toLowerCase();



  final container = _isContainerLine(t);
  if (!container && uri.length > maxURILength) {


    dropped?.reason = RegistryWarning(
      code: 'uri_too_long',
      params: {'length': '${uri.length}', 'limit': '$maxURILength'},
    );
    return null;
  }
  try {




    final type = registrySchemeType(scheme);
    if (type != null) {


      return parseUriViaPipeline(t, scheme, dropped: dropped);
    }

    if (container) {
      final n = parseAmneziaVpnUri(t, dropped: dropped);








      if (n == null && dropped != null && dropped.reason == null) {
        dropped.reason = RegistryWarning(
          code: 'form_unrecognized',
          params: {'scheme': scheme},
        );
      }
      return n;
    }





    final serviceCode = _serviceSchemeCode(t);
    if (serviceCode != null) {
      if (serviceCode.isNotEmpty) {
        dropped?.reason = RegistryWarning(
          code: serviceCode,
          params: {'scheme': scheme},
          value: scheme,
        );
      }
      return null;
    }




    if (!t.contains('://')) return null;





    dropped?.reason = RegistryWarning(
      code: 'scheme_unsupported',
      params: {'scheme': scheme},
      value: scheme,
    );
    return null;
  } catch (_) {
    return null;
  }
}
