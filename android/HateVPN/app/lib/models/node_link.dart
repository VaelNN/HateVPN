









library;

final class NodeLink {
  const NodeLink({this.folderId = '', required this.tag});



  static const none = NodeLink(tag: '');


  final String folderId;




  final String tag;

  bool get isRoot => folderId.isEmpty;


  bool get isEmpty => tag.isEmpty;

  bool get isNotEmpty => tag.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NodeLink && folderId == other.folderId && tag == other.tag);

  @override
  int get hashCode => Object.hash(folderId, tag);

  @override
  String toString() => isRoot ? 'NodeLink($tag)' : 'NodeLink($folderId/$tag)';
}
