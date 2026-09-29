


sealed class SingboxEntry {
  SingboxEntry();
  Map<String, dynamic> get map;






  bool authored = false;



  String get tag => (map['tag'] as String?) ?? '';
}

final class Outbound extends SingboxEntry {
  @override
  final Map<String, dynamic> map;
  Outbound(this.map);
}

final class Endpoint extends SingboxEntry {
  @override
  final Map<String, dynamic> map;
  Endpoint(this.map);
}
