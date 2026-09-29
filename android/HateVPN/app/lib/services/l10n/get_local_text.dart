









import 'plural_resolver.dart';

class GetLocalText {


  GetLocalText(this._dict, this._plural);





  static const en = GetLocalText.raw();
  const GetLocalText.raw()
      : _dict = null,
        _plural = const EnPluralResolver();

  final Map<String, dynamic>? _dict;
  final PluralResolver _plural;






  String s(Object a0,
      [Object? a1,
      Object? a2,
      Object? a3,
      Object? a4,
      Object? a5,
      Object? a6]) {
    final int formIndex;
    final String key;
    final List<Object?> args;


    if (a0 is int) {
      formIndex = a0;
      key = a1 is String ? a1 : a1.toString();
      args = _prefixNonNull([a2, a3, a4, a5, a6]);
    } else {
      formIndex = 0;
      key = a0 is String ? a0 : a0.toString();
      args = _prefixNonNull([a1, a2, a3, a4, a5, a6]);
    }

    final raw = _lookupValue(key, formIndex);



    final template = raw is String ? raw : key;
    return _format(template, args);
  }






  String plural(Object a0,
      [Object? a1, Object? a2, Object? a3, Object? a4]) {
    final int formIndex;
    final String key;
    final num n;



    final List<Object?> rest;
    if (a0 is int && a1 != null) {

      formIndex = a0;
      key = a1 is String ? a1 : a1.toString();
      n = a2 is num ? a2 : 0;
      rest = [a3, a4];
    } else {


      formIndex = 0;
      key = a0 is String ? a0 : a0.toString();
      n = a1 is num ? a1 : 0;
      rest = [a2, a3, a4];
    }

    final args = <Object?>[n, ...rest.takeWhile((e) => e != null)];

    final raw = _lookupValue(key, formIndex);



    if (raw is Map) {
      final forms = <String, String>{
        for (final e in raw.entries)
          e.key.toString(): e.value is String ? e.value as String : '',
      };
      final picked = _plural.select(forms, n);
      return _format(picked, args);
    }
    return _format(key, args);
  }



  Object? _lookupValue(String key, int formIndex) {
    final dict = _dict;
    if (dict == null) return null;
    final entry = dict[key];
    if (entry is! Map) return null;
    if (formIndex <= 0) return entry['value'];

    final special = entry['special'];
    if (special is! Map) return null;
    final form = special[formIndex.toString()];
    if (form is! Map) return null;
    return form['value'];
  }

  static List<Object?> _prefixNonNull(List<Object?> a) {

    final out = <Object?>[];
    for (final x in a) {
      if (x == null) break;
      out.add(x);
    }
    return out;
  }








  static String _format(String template, List<Object?> args) {
    final out = StringBuffer();
    var seq = 0;
    var i = 0;
    while (i < template.length) {
      final c = template[i];
      if (c != '%') {
        out.write(c);
        i++;
        continue;
      }

      if (i + 1 >= template.length) {
        out.write('%');
        break;
      }
      final next = template[i + 1];
      if (next == '%') {
        out.write('%');
        i += 2;
        continue;
      }

      if (_isDigit(next)) {
        var j = i + 1;
        while (j < template.length && _isDigit(template[j])) {
          j++;
        }
        if (j + 1 < template.length && template[j] == r'$') {
          final pos = int.parse(template.substring(i + 1, j));
          final conv = template[j + 1];
          out.write(_render(args, pos - 1, conv));
          i = j + 2;
          continue;
        }

        out.write('%');
        i++;
        continue;
      }
      if (next == 's' || next == 'd') {
        out.write(_render(args, seq, next));
        seq++;
        i += 2;
        continue;
      }

      out.write('%');
      i++;
    }
    return out.toString();
  }

  static bool _isDigit(String c) {
    final u = c.codeUnitAt(0);
    return u >= 0x30 && u <= 0x39;
  }

  static String _render(List<Object?> args, int index, String conv) {
    if (index < 0 || index >= args.length) return '';
    final v = args[index];
    if (v == null) return '';
    if (conv == 'd') {
      if (v is int) return v.toString();
      if (v is num) return v.truncate().toString();
      return v.toString();
    }
    return v.toString();
  }
}
