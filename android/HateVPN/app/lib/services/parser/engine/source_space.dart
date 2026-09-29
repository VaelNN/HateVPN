




















library;










final class QueryPairs {
  QueryPairs(this.pairs);


  final List<(String, String)> pairs;

  static final QueryPairs empty = QueryPairs(const []);






  String? get(String name) {
    for (final p in pairs) {
      if (p.$1 == name) return p.$2;
    }
    final lower = name.toLowerCase();
    for (final p in pairs) {
      if (p.$1.toLowerCase() == lower) return p.$2;
    }
    return null;
  }



  bool has(String name) => get(name) != null;


  Iterable<String> get names => pairs.map((p) => p.$1);
}






final class SourceSpace {
  const SourceSpace({
    this.formId = '',
    this.scheme = '',
    this.authority = '',
    this.userinfo = '',
    this.userinfoUser,
    this.userinfoPass,
    this.host = '',
    this.port,
    this.portRaw = '',
    this.path = '',
    this.fragment = '',
    QueryPairs? query,
    this.json,
    this.jsonBase,
    this.ini,
  }) : _query = query;

  final QueryPairs? _query;



  final String formId;



  final String scheme;


  final String authority;



  final String userinfo;


  final String? userinfoUser;
  final String? userinfoPass;



  final String host;


  final int? port;



  final String portRaw;


  final String path;



  final String fragment;


  QueryPairs get query => _query ?? QueryPairs.empty;


  final Map<String, dynamic>? json;





  final String? jsonBase;



  final Map<String, String>? ini;

  SourceSpace copyWith({
    String? formId,
    String? userinfoUser,
    String? userinfoPass,
  }) =>
      SourceSpace(
        formId: formId ?? this.formId,
        scheme: scheme,
        authority: authority,
        userinfo: userinfo,
        userinfoUser: userinfoUser ?? this.userinfoUser,
        userinfoPass: userinfoPass ?? this.userinfoPass,
        host: host,
        port: port,
        portRaw: portRaw,
        path: path,
        fragment: fragment,
        query: _query,
        json: json,
        jsonBase: jsonBase,
        ini: ini,
      );
}
