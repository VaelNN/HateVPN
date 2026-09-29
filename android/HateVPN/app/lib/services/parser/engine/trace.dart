














library;



abstract final class TraceStage {
  static const docDetect = 'doc_detect';
  static const unwrap = 'unwrap';
  static const elemDetect = 'elem_detect';
  static const lex = 'lex';
  static const field = 'field';
  static const sets = 'sets';
  static const defaults = 'default';
  static const label = 'label';
  static const unknown = 'unknown';
  static const result = 'result';
}


abstract final class TraceAct {
  static const write = 'write';
  static const skip = 'skip';
  static const remove = 'remove';
  static const override = 'override';
  static const keep = 'keep';
}



abstract final class TraceWhy {
  static const none = '-';
  static const whenFalse = 'when_false';
  static const empty = 'empty';
  static const notDeclared = 'not_declared';
  static const byDefault = 'default';
  static const materializeDefault = 'materialize_default';


  static String lowerPriority(String entry) => 'lower_priority:$entry';


  static String aliasOf(String canon) => 'alias_of:$canon';
}



final class MapperTrace {
  MapperTrace();

  final List<String> _lines = [];
  int _n = 0;


  void add({
    required String stage,
    required String mapper,
    String entry = '-',
    String src = '-',
    String? raw,
    Object? val,
    String? path,
    String act = TraceAct.write,
    String why = TraceWhy.none,
  }) {
    _n++;
    final b = StringBuffer('{"n":$_n,"stage":${_str(stage)},'
        '"mapper":${_str(mapper)},"entry":${_str(entry)},"src":${_str(src)},'
        '"raw":${raw == null ? 'null' : _str(raw)},"val":${encode(val)},'
        '"path":${path == null ? 'null' : _str(path)},"act":${_str(act)},'
        '"why":${_str(why)}}');
    _lines.add(b.toString());
  }


  String render() => _lines.join('\n');

  List<String> get lines => List.unmodifiable(_lines);













  static String encode(Object? v, {bool sortFree = false}) {
    if (v == null) return 'null';
    if (v is bool) return v ? 'true' : 'false';
    if (v is int) return '$v';
    if (v is double) {

      if (v == v.roundToDouble() && v.abs() < 1e15) {
        return '${v.toInt()}';
      }
      return v.toString();
    }
    if (v is String) return _str(v);
    if (v is List) {
      return '[${v.map((e) => encode(e, sortFree: sortFree)).join(',')}]';
    }
    if (v is Map) {
      final keys = v.keys.map((k) => '$k').toList();
      if (sortFree) keys.sort();
      final parts = [
        for (final k in keys) '${_str(k)}:${encode(v[k], sortFree: sortFree)}',
      ];
      return '{${parts.join(',')}}';
    }
    return _str('$v');
  }



  static String _str(String s) {
    final b = StringBuffer('"');
    for (final r in s.runes) {
      switch (r) {
        case 0x22:
          b.write(r'\"');
        case 0x5C:
          b.write(r'\\');
        case 0x08:
          b.write(r'\b');
        case 0x0C:
          b.write(r'\f');
        case 0x0A:
          b.write(r'\n');
        case 0x0D:
          b.write(r'\r');
        case 0x09:
          b.write(r'\t');
        default:
          if (r < 0x20) {
            b.write('\\u${r.toRadixString(16).padLeft(4, '0')}');
          } else {
            b.writeCharCode(r);
          }
      }
    }
    b.write('"');
    return b.toString();
  }
}
