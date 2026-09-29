
























library;

import 'section.dart';
import 'source_space.dart';






typedef IniParse = ({Map<String, String> space, List<String> codes});





IniParse parseIniSpace(String text, IniDialect d) {
  final out = <String, String>{};
  final codes = <String>[];


  final seen = <String, int>{};


  var section = '';




  var collecting = true;

  for (final line in text.split(RegExp(r'\r?\n'))) {
    final t = line.trim();
    if (t.isEmpty) continue;




    final commentPrefix =
        d.lineCommentPrefixes.where(t.startsWith).firstOrNull;
    if (commentPrefix != null) {
      if (!collecting) continue;
      final body = t.substring(commentPrefix.length).trim();


      if (body.isEmpty || body.contains('=')) continue;


      final key =
          '${DraftNames.iniCommentPrefix.substring('ini.'.length)}$section'
              .toLowerCase();

      out.putIfAbsent(key, () => body);
      continue;
    }

    if (t.startsWith('[')) {
      final close = t.indexOf(']');
      final name = (close > 0 ? t.substring(1, close) : t.substring(1)).trim();
      section = name.toLowerCase();
      final n = (seen[section] ?? 0) + 1;
      seen[section] = n;
      final rule = d.sectionRule(name);
      collecting = true;
      if (n > 1 && rule?.repeat == 'first_only') {
        collecting = false;
        final code = rule?.onExtraCode;
        if (code != null && !codes.contains(code)) codes.add(code);
      }
      continue;
    }

    if (!collecting) continue;

    final idx = t.indexOf('=');
    if (idx < 0) continue;
    var key = t.substring(0, idx).trim();
    var value = t.substring(idx + 1).trim();
    if (d.keyCase == 'lower') key = key.toLowerCase();
    if (d.valueCase == 'lower') value = value.toLowerCase();



    if (value.isEmpty) continue;

    final path = '$section.$key';
    if (d.repeatedKey == 'first_wins' && out.containsKey(path)) continue;
    out[path] = value;
  }

  return (space: out, codes: codes);
}


SourceSpace iniSpace(String text, IniDialect d, {required String formId}) =>
    SourceSpace(formId: formId, ini: parseIniSpace(text, d).space);
