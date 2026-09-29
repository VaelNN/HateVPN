






















library;

import '../../../models/node_warning.dart';
import '../../contract/body_sanitizer.dart' show BodySource;


final class UriMapping {
  const UriMapping({
    required this.body,
    required this.label,
    this.warnings = const [],
    this.extensionFields = const {},
    this.wsEarlyDataHeaderImplicit = false,
    this.tagAddress,
    this.kinds = const {},
    this.bodySource = BodySource.other,
  });







  final Map<String, dynamic> body;


  final String label;


  final List<NodeWarning> warnings;
















  final Map<String, dynamic> extensionFields;












  final (String, int)? tagAddress;














  final Set<String> kinds;










  final bool wsEarlyDataHeaderImplicit;













  final BodySource bodySource;
}














typedef UriMapper = UriMapping? Function(String uri);
