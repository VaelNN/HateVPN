







library;

import '../node_link.dart';


Map<String, dynamic> nodeLinkToRecord(NodeLink link) => {
      if (link.folderId.isNotEmpty) 'folder_id': link.folderId,
      'tag': link.tag,
    };



Map<String, dynamic>? nodeLinkToRecordOrNull(NodeLink link) =>
    link.isEmpty ? null : nodeLinkToRecord(link);





NodeLink? nodeLinkFromRecord(Object? raw) {
  if (raw is String) return NodeLink(tag: raw);
  if (raw is! Map) return null;
  final folderId = raw['folder_id'];
  final tag = raw['tag'];
  return NodeLink(
    folderId: folderId is String ? folderId.trim() : '',
    tag: tag is String ? tag : '',
  );
}




NodeLink liftSiblingLink(
  NodeLink link,
  String containerId,
  Set<String> rawTags,
) {
  if (!link.isRoot || link.isEmpty || containerId.isEmpty) return link;
  if (!rawTags.contains(link.tag)) return link;
  return NodeLink(folderId: containerId, tag: link.tag);
}





NodeLink lowerGroupFinalLink(
  NodeLink link,
  String containerId,
  Set<String> rawTags,
  Map<String, List<String>> groupFinalForms,
) {
  if (link.isRoot || link.folderId != containerId) return link;
  if (rawTags.contains(link.tag)) return link;
  final candidates = groupFinalForms[link.tag];
  if (candidates == null || candidates.length != 1) return link;
  return NodeLink(folderId: containerId, tag: candidates.single);
}
