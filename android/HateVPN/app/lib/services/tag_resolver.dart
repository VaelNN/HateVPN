import '../config/consts.dart';














class TagResolver {
  TagResolver._();




  static String displayTag(String tagPrefix, String bareTag) =>
      tagPrefix.isEmpty ? bareTag : '$tagPrefix $bareTag';




  static bool isDetourMarker(String displayTag) =>
      displayTag.startsWith(kDetourTagPrefix) ||
      displayTag.contains(' $kDetourTagPrefix');



  static String stripPrefix(String displayTag, String tagPrefix) {
    if (tagPrefix.isEmpty) return displayTag;
    final p = '$tagPrefix ';
    return displayTag.startsWith(p)
        ? displayTag.substring(p.length)
        : displayTag;
  }
}
