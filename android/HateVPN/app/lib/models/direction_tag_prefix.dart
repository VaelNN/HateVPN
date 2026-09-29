



























import '../services/safe_regex.dart';
import 'direction.dart';


class DirectionPrefixImpact {
  const DirectionPrefixImpact({
    required this.direction,
    required this.healed,
    required this.ambiguous,
  });


  final Direction direction;



  final Direction? healed;





  final bool ambiguous;


  bool get isHealed => healed != null;
}


class DirectionPrefixCascade {
  const DirectionPrefixCascade({required this.impacts});

  static const empty = DirectionPrefixCascade(impacts: []);

  final List<DirectionPrefixImpact> impacts;

  bool get isEmpty => impacts.isEmpty;


  List<Direction> get healedDirections => [
        for (final i in impacts)
          if (i.healed != null) i.healed!,
      ];


  List<DirectionPrefixImpact> get ambiguousImpacts =>
      [for (final i in impacts) if (i.ambiguous) i];
}










DirectionPrefixCascade analyzeTagPrefixChange({
  required List<Direction> directions,
  required String oldPrefix,
  required String newPrefix,
}) {
  if (oldPrefix.isEmpty || oldPrefix == newPrefix) {
    return DirectionPrefixCascade.empty;
  }
  final impacts = <DirectionPrefixImpact>[];
  for (final d in directions) {
    final node = rewriteLiteralPrefix(d.nodeFilter, oldPrefix, newPrefix);
    final def = rewriteLiteralPrefix(d.defaultFilter, oldPrefix, newPrefix);
    final ambiguous = node.ambiguous || def.ambiguous;
    final changed = node.changed || def.changed;
    if (!ambiguous && !changed) continue;
    impacts.add(DirectionPrefixImpact(
      direction: d,
      healed: changed
          ? d.copyWith(nodeFilter: node.pattern, defaultFilter: def.pattern)
          : null,
      ambiguous: ambiguous,
    ));
  }
  return DirectionPrefixCascade(impacts: impacts);
}


typedef PrefixRewrite = ({String pattern, bool changed, bool ambiguous});













PrefixRewrite rewriteLiteralPrefix(
    String pattern, String oldPrefix, String newPrefix) {
  if (pattern.isEmpty || oldPrefix.isEmpty) {
    return (pattern: pattern, changed: false, ambiguous: false);
  }




  if (tryCompileRegex(pattern, caseSensitive: false) == null) {
    return (
      pattern: pattern,
      changed: false,
      ambiguous: pattern.contains(oldPrefix),
    );
  }
  final atoms = _scan(pattern);
  if (atoms == null) {



    return (
      pattern: pattern,
      changed: false,
      ambiguous: pattern.contains(oldPrefix),
    );
  }

  final replacement = newPrefix.isEmpty ? '' : RegExp.escape(newPrefix);
  final out = StringBuffer();
  var changed = false;
  var ambiguous = false;
  var i = 0;
  while (i < atoms.length) {
    final clean = _matchAt(atoms, i, oldPrefix, strict: true);
    if (clean != null) {
      out.write(replacement);
      changed = true;
      i = clean;
      continue;
    }





    if (!ambiguous && _matchAt(atoms, i, oldPrefix, strict: false) != null) {
      ambiguous = true;
    }
    out.write(atoms[i].source);
    i++;
  }
  return (pattern: out.toString(), changed: changed, ambiguous: ambiguous);
}









class _Atom {
  _Atom(this.source, this.literal, {this.classChars});
  final String source;
  final String? literal;
  final Set<String>? classChars;
  bool quantified = false;



  bool canMatch(String c, {required bool strict}) {
    if (strict) return literal == c && !quantified;
    return literal == c || (classChars?.contains(c) ?? false);
  }
}



int? _matchAt(List<_Atom> atoms, int start, String prefix,
    {required bool strict}) {
  var ai = start;
  for (final want in prefix.split('')) {
    if (ai >= atoms.length) return null;
    if (!atoms[ai].canMatch(want, strict: strict)) return null;
    ai++;
  }



  return ai;
}


List<_Atom>? _scan(String p) {
  final atoms = <_Atom>[];
  var i = 0;
  while (i < p.length) {
    final c = p[i];
    switch (c) {
      case '\\':
        if (i + 1 >= p.length) return null;
        final n = p[i + 1];
        final src = '\\$n';



        final isWordChar = RegExp(r'[A-Za-z0-9]').hasMatch(n);
        atoms.add(_Atom(src, isWordChar ? null : n));
        i += 2;
      case '[':
        final end = _classEnd(p, i);
        if (end < 0) return null;
        final src = p.substring(i, end + 1);
        atoms.add(_Atom(src, null, classChars: _classChars(src)));
        i = end + 1;
      case '(':
      case ')':
      case '|':
      case '^':
      case r'$':
      case '.':
        atoms.add(_Atom(c, null));
        i++;
      case '*':
      case '+':
      case '?':
        if (atoms.isNotEmpty) atoms.last.quantified = true;
        atoms.add(_Atom(c, null));
        i++;
      case '{':
        final end = p.indexOf('}', i);



        if (end < 0) {
          atoms.add(_Atom(c, null));
          i++;
        } else {
          if (atoms.isNotEmpty) atoms.last.quantified = true;
          atoms.add(_Atom(p.substring(i, end + 1), null));
          i = end + 1;
        }
      default:
        atoms.add(_Atom(c, c));
        i++;
    }
  }
  return atoms;
}



int _classEnd(String p, int start) {
  var i = start + 1;
  if (i < p.length && p[i] == '^') i++;
  if (i < p.length && p[i] == ']') i++;
  while (i < p.length) {
    if (p[i] == '\\') {
      i += 2;
      continue;
    }
    if (p[i] == ']') return i;
    i++;
  }
  return -1;
}




Set<String>? _classChars(String src) {
  var body = src.substring(1, src.length - 1);
  if (body.startsWith('^')) return null;
  if (body.contains(r'\')) return null;
  if (body.contains('-') && body.length > 1) return null;
  return body.split('').toSet();
}
