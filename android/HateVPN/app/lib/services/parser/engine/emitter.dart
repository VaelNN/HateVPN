





















library;

import 'dart:convert';

import 'section.dart';




















abstract final class EmitNames {



  static const emit = 'emit';



  static const form = 'form';



  static const formFrom = 'form_from';








  static const formFromAnySet = 'any_set';



  static const paramOrder = 'param_order';


  static const omitDefault = 'omit_default';


  static const emitWhen = 'emit_when';


  static const paramOrderAlphabetical = 'alphabetical';


  static const emitWhenAlways = 'always';








  static const roundTrip = 'round_trip';


  static const roundTripWhy = 'round_trip_why';









  static const compose = 'compose';


  static const composeTemplate = 'template';


  static const composeFrom = 'from';


  static const composeOmitWhenEmpty = 'omit_when_empty';










  static const emitAs = 'emit_as';


  static const emitAsJoin = 'join';


  static const emitAsBool01 = 'bool01';


  static const emitAsJson = 'json';


  static const emitAsRaw = 'raw';
















  static const names = 'names';










  static const omitPort = 'omit_port';











  static const userinfo = 'userinfo';


  static const userinfoForm = 'form';


  static const userinfoPadding = 'padding';









  static const userinfoEmptySeparator = 'empty_separator';










  static const userinfoKeepEmptyTail = 'keep_empty_tail';


  static const userinfoRaw = 'raw';


  static const userinfoBase64 = 'base64';







  static const jsonMap = 'json_map';









  static const jsonAlways = 'json_always';





  static const refuseWhen = 'refuse_when';


  static const roundTripOnly = 'round_trip_only';


  static const roundTripOnlyEmit = 'emit';


  static const roundTripOnlyParse = 'parse';
}


final class EmitResult {
  const EmitResult({required this.uri, this.lost = const []});


  final String uri;



  final List<String> lost;
}






EmitResult? emitViaSection(
  MapperSection section,
  Map<String, dynamic> body,
  String label,
) {
  if (!sectionEmits(section)) return null;
  return _Emit(section, section.emit!, body, label).run();
}









bool sectionEmits(MapperSection section) =>
    section.emit != null && section.params.isNotEmpty;







Set<String> readableNames(MapperParam p) => {
      ...p.spellings,
      for (final s in [
        ...p.source,
        for (final v in p.sourceByForm.values) ...v,
      ])
        if (s.startsWith('query.')) s.substring('query.'.length),
    };

final class _Emit {
  _Emit(this.section, this.emit, this.body, this.label);

  final MapperSection section;
  final Map<String, dynamic> emit;
  final Map<String, dynamic> body;
  final String label;


  final List<(MapperParam p, String name, String value)> _query = [];


  final Set<String> _consumed = {};

  final List<String> _lost = [];


  late final Map<String, List<MapperParam>> _pathOwners = _seedPathOwners();

  EmitResult run() {


    if (_refuse()) return const EmitResult(uri: '');

    final scheme = _scheme();
    final userinfo = _userinfo();





    _consumeSchemeSets(scheme);





    for (final p in section.params.values) {
      _emitParam(p);
    }



    _consumeDefaults();

    _collectLost();

    final form = _form();



    if (_spaceOf(form) == 'json') {
      return EmitResult(uri: _emitJson(scheme), lost: _lost);
    }

    final host = _wrapIpv6(_str(_readSourcePath('host')) ?? '');
    final portPart = _portPart();
    final qs = _serializeQuery();
    final frag = label.isEmpty ? '' : '#${_encodeFragment(label)}';
    final ui = userinfo.isEmpty && !_userinfoEmptySeparator()
        ? ''
        : '$userinfo@';

    return EmitResult(
      uri: '$scheme://$ui$host$portPart'
          '${qs.isEmpty ? '' : '?$qs'}$frag',
      lost: _lost,
    );
  }



  String _spaceOf(String id) {
    for (final f in section.forms) {
      if (f.id == id) return f.space;
    }
    return 'url';
  }



  bool get _userinfoDecodesBase64 =>
      section.userinfo?.decode.any((d) => d.startsWith('base64')) ?? false;



  String _form() => emit[EmitNames.form] as String? ?? 'url';












  String _scheme() {
    final ff = emit[EmitNames.formFrom];
    if (ff is Map) {
      for (final e in ff.entries) {
        final key0 = '${e.key}';
        final branches = (e.value as Map).cast<String, dynamic>();

        if (key0 == EmitNames.formFromAnySet) {


          for (final b in branches.entries) {
            if (b.key == '*') continue;
            final paths = b.value;
            if (paths is! List) continue;
            if (paths.any((p) => _read('$p') != null)) return b.key;
          }
          final star = branches['*'];
          if (star is String) return star;
          continue;
        }

        final actual = _read(key0);
        final key = _fold(actual);
        for (final b in branches.entries) {
          if (b.key == '*') continue;
          if (_fold(b.key) == key) return b.value as String;
        }
        final star = branches['*'];
        if (star is String) return star;
      }
    }


    final si = section.detect?['scheme_in'];
    if (si is List && si.isNotEmpty) return '${si.first}';
    return section.singboxType;
  }





  void _consumeSchemeSets(String scheme) {
    for (final e in section.schemeSets.entries) {
      if (e.key != '*' && _fold(e.key) != _fold(scheme)) continue;
      final sets = e.value;
      if (sets is! Map) continue;
      for (final s in sets.entries) {
        final k = s.key as String;
        if (k.startsWith(DraftNames.serviceParamPrefix)) continue;



        final v = s.value;
        if (v is String && v.startsWith(DraftNames.serviceParamPrefix)) {
          _consumed.add(k);
          continue;
        }
        if (_matches(_read(k), v)) _consumed.add(k);
      }
    }
  }



  void _consumeDefaults() {
    for (final e in section.defaults.entries) {
      if (e.key.startsWith(DraftNames.serviceParamPrefix)) continue;
      if (_matches(_read(e.key), e.value)) _consumed.add(e.key);
    }

    _consumed.add('type');
  }

  String _portPart() {
    final port = _readSourcePath('port');
    if (port == null) return '';
    final omit = emit[EmitNames.omitPort];
    if (omit != null && '$omit' == '$port') return '';
    return ':$port';
  }











  dynamic _readSourcePath(String place) {
    for (final p in section.params.values) {
      if (p.isService) continue;
      final path = p.mapsTo;
      if (path == null) continue;
      final sources = [
        ...p.source,
        for (final v in p.sourceByForm.values) ...v,
      ];
      if (!sources.contains(place)) continue;
      final v = _read(path);
      if (v != null) return v;
    }
    return null;
  }










  String _userinfo() {
    final u = section.userinfo;
    final paths = u?.into ?? const <String>[];







    if (paths.isEmpty || u == null) return _userinfoFromParam();

    final values = [for (final p in paths) _str(_read(p)) ?? ''];
    for (final p in paths) {
      _consumed.add(p);
    }




    if (_userinfoForm() == EmitNames.userinfoBase64) {
      if (values.every((v) => v.isEmpty)) return '';
      final joined = values.join(u.splitSep ?? ':');
      final encoded = base64.encode(utf8.encode(joined));
      return _userinfoPadding() ? encoded : encoded.replaceAll('=', '');
    }


    if (paths.length == 1) return _encodeParam(values.first);

    final sep = u.splitSep ?? ':';
    final first = values.first;
    final rest = values.skip(1).toList();
    final restEmpty = rest.every((v) => v.isEmpty);

    if (first.isEmpty && restEmpty) return '';





    final single = u.singleInto;
    final singleIdx = single == null ? -1 : paths.indexOf(single);



    final filled = [
      for (var i = 0; i < values.length; i++)
        if (values[i].isNotEmpty) i,
    ];
    if (filled.length == 1 && filled.first == singleIdx) {






      final tail = _userinfoKeepEmptyTail() ? sep : '';
      return '${_encodeParam(values[singleIdx])}$tail';
    }



    if (restEmpty) {
      final needsSep = singleIdx >= 0 && singleIdx != 0;
      return '${_encodeParam(first)}${needsSep ? sep : ''}';
    }



    return [
      _encodeParam(first),
      ...rest.map(_encodeParam),
    ].join(sep);
  }








  String _userinfoFromParam() {
    for (final p in section.params.values) {
      if (p.isService || _roundTripOff(p)) continue;
      final path = p.mapsTo;
      if (path == null || p.source.isEmpty) continue;
      if (p.source.first != 'userinfo') continue;
      final v = _str(_read(path));
      if (v == null || v.isEmpty) continue;
      _consumed.add(path);
      return _encodeParam(v);
    }
    return '';
  }




  String _userinfoForm() {
    final raw = emit[EmitNames.userinfo];
    if (raw is String) return raw;
    if (raw is Map) {
      final f = raw[EmitNames.userinfoForm];
      if (f is String) return f;
    }
    return _userinfoDecodesBase64
        ? EmitNames.userinfoBase64
        : EmitNames.userinfoRaw;
  }




  bool _userinfoPadding() {
    final raw = emit[EmitNames.userinfo];
    if (raw is Map) {
      final p = raw[EmitNames.userinfoPadding];
      if (p is bool) return p;
    }
    return false;
  }



  bool _userinfoKeepEmptyTail() {
    final raw = emit[EmitNames.userinfo];
    if (raw is Map) {
      final p = raw[EmitNames.userinfoKeepEmptyTail];
      if (p is bool) return p;
    }
    return false;
  }



  bool _userinfoEmptySeparator() {
    final raw = emit[EmitNames.userinfo];
    if (raw is Map) {
      final p = raw[EmitNames.userinfoEmptySeparator];
      if (p is bool) return p;
    }
    return false;
  }




  void _emitParam(MapperParam p) {

    if (p.isService) return;

    if (_roundTripOnlyParse(p)) return;

    if (_roundTripOff(p)) return;





    if (p.mapsToPresent &&
        p.mapsTo == null &&
        p.compose == null &&
        p.sets.isEmpty) {
      return;
    }






    if (!_readsQuery(p)) {
      final path = p.mapsTo;
      if (path != null && _read(path) != null) _consumed.add(path);
      for (final t in p.splitInto.keys) {
        _consumed.add(t);
      }
      return;
    }




    final target = p.mapsTo;
    if (target != null && _consumed.contains(target)) return;


    final composed = _compose(p);
    if (composed != null) {
      _add(p, composed);
      return;
    }






    if (_extractsPairs(p)) {
      final pairs = _joinPairs(p);
      if (pairs != null) _add(p, pairs);
      return;
    }





    if (p.splitInto.isNotEmpty) {
      final joined = _joinSplit(p);
      if (joined != null) _add(p, joined);
      return;
    }

    final path = p.mapsTo;







    if (path == null) {
      if (p.sets.isEmpty) return;
      final back = _valueFromSets(p);
      if (back != null) _add(p, back);
      return;
    }

    var value = _read(path);





    if (value != null) {
      for (final s in [...p.implies.entries, ...p.sets.entries]) {
        final k = s.key;
        if (k.startsWith(DraftNames.serviceParamPrefix)) continue;
        if (_matches(_read(k), s.value)) _consumed.add(k);
      }
    }










    if (value == null && p.sets.isNotEmpty && !_setsOwnedByOthers(p)) {
      final back = _valueFromSets(p);
      if (back != null) {
        _add(p, back);
        return;
      }
    }

    if (value == null) return;
    _consumed.add(path);







    final inv = invertValueMap(p.valueMap);
    if (inv != null && !_isUntranslatedCanon(p, value)) {
      final hit = inv[_fold(value)];
      if (hit != null) {
        final branch = p.sets[hit];


        if (branch is! Map ||
            !_setsBranchOwnedByOthers(p, branch.cast<String, dynamic>())) {
          value = hit;
        }
      }
    }

    final text = _serializeValue(p, value);
    if (text == null) return;
    _add(p, text);
  }



  static bool _extractsPairs(MapperParam p) {
    final into = p.extract?.into;
    if (into == null) return false;
    return into.values.any((v) => v == r'$key') &&
        into.values.any((v) => v == r'$value');
  }















  String? _joinPairs(MapperParam p) {
    final path = p.mapsTo;
    if (path == null) return null;
    final v = _read(path);
    if (v is! Map || v.isEmpty) return null;
    _consumed.add(path);
    final keys = v.keys.map((e) => '$e').toList();
    if (p.sortKeys) keys.sort();
    final sep = p.list?.sep ?? '\r\n';
    final re = _pairRegex(p);
    final items = <String>[];
    for (final k in keys) {
      final item = '$k: ${v[k]}';
      if (re != null && !re.hasMatch(item)) continue;
      items.add(item);
    }
    return items.isEmpty ? null : items.join(sep);
  }


  static RegExp? _pairRegex(MapperParam p) {
    final re = p.extract?.re;
    if (re == null || re.isEmpty) return null;
    return _reCache.putIfAbsent(
        re, () => RegExp(re.replaceAll('(?P<', '(?<')));
  }

  static final Map<String, RegExp> _reCache = {};








  String? _joinSplit(MapperParam p) {
    final items = <String>[];
    for (final path in p.splitInto.keys) {
      final v = _read(path);
      if (v == null) continue;
      _consumed.add(path);
      if (v is List) {
        items.addAll(v.map((e) => '$e'));
      } else {
        items.add('$v');
      }
    }
    if (items.isEmpty) return null;
    return items.join(p.list?.sep ?? ',');
  }




  static bool _readsQuery(MapperParam p) {
    final sources = [
      ...p.source,
      for (final v in p.sourceByForm.values) ...v,
    ];
    if (sources.isEmpty) return false;
    return sources.any((s) => s.startsWith('query.') || s == 'query');
  }





















  bool _setsOwnedByOthers(MapperParam p) {
    final targets = <String>{};
    for (final branch in p.sets.values) {
      if (branch is! Map) continue;
      for (final k in branch.keys) {
        final path = '$k';
        if (path.startsWith(DraftNames.serviceParamPrefix)) continue;
        if (_read(path) != null) targets.add(path);
      }
    }
    if (targets.isEmpty) return false;
    final owned = <String>{};
    for (final o in section.params.values) {
      if (identical(o, p) || o.isService || _roundTripOff(o)) continue;
      final m = o.mapsTo;
      if (m != null && targets.contains(m)) owned.add(m);
    }
    return owned.length == targets.length;
  }


  bool _setsBranchOwnedByOthers(MapperParam p, Map<String, dynamic> branch) {
    var any = false;
    for (final s in branch.entries) {
      final path = s.key.toString();
      if (path.startsWith(DraftNames.serviceParamPrefix) || s.value == null) {
        continue;
      }
      if (_read(path) == null) continue;
      any = true;
      if (!_pathOwnedByOther(p, path)) return false;
    }
    return any;
  }




  Map<String, List<MapperParam>> _seedPathOwners() {
    final out = <String, List<MapperParam>>{};
    for (final p in section.params.values) {
      if (p.isService || _roundTripOff(p)) continue;
      final path = p.mapsTo;
      if (path != null && _read(path) != null) {
        (out[path] ??= []).add(p);
      }
    }
    return out;
  }

  bool _pathOwnedByOther(MapperParam p, String path) {
    final owners = _pathOwners[path];
    if (owners == null) return false;
    return owners.any((o) => !identical(o, p));
  }

  bool _roundTripOnlyParse(MapperParam p) =>
      p.roundTripOnly == EmitNames.roundTripOnlyParse;

  bool _roundTripOnlyEmit(MapperParam p) =>
      p.roundTripOnly == EmitNames.roundTripOnlyEmit;

  String? _valueFromSets(MapperParam p) {
    String? best;
    var bestScore = -1;

    var defaultScore = -1;

    for (final e in p.sets.entries) {
      final branch = e.value;
      if (branch is! Map || branch.isEmpty) continue;
      var all = true;



      var score = 0;
      for (final s in branch.entries) {
        final k = '${s.key}';
        if (k.startsWith(DraftNames.serviceParamPrefix)) continue;
        if (!_matches(_read(k), s.value)) {
          all = false;
          break;
        }
        if (s.value != null) score++;
      }
      if (!all) continue;





      if (e.key.isEmpty) {
        _consumeBranch(branch);
        defaultScore = score;
        continue;
      }






      if (score == 0 && bestScore < 0) {
        bestScore = 0;
        best = e.key;
        continue;
      }
      if (score <= bestScore) continue;
      bestScore = score;
      best = e.key;
      _consumeBranch(branch);
    }













    if (defaultScore >= bestScore && !_alwaysEmitted(p)) return null;
    return best;
  }

  void _consumeBranch(Map branch) {
    for (final s in branch.entries) {
      final k = '${s.key}';
      if (k.startsWith(DraftNames.serviceParamPrefix)) continue;

      if (s.value == null) continue;
      _consumed.add(k);
    }
  }

















  String? _compose(MapperParam p) {
    final raw = p.raw[EmitNames.compose] ?? p.compose;
    if (raw is String) {
      return _composeTemplate(p, raw, (g) => g, _impliedOffGroups(p));
    }
    if (raw is! Map) return null;
    final spec = raw.cast<String, dynamic>();
    final template = spec[EmitNames.composeTemplate] as String?;
    if (template == null) return null;





    final fromRaw = spec[EmitNames.composeFrom];
    final from = fromRaw is Map ? fromRaw.cast<String, dynamic>() : null;




    return _composeTemplate(
      p,
      template,
      from == null ? (g) => g : (g) => '${from[g] ?? g}',
      _impliedOffGroups(p),
    );
  }










  String? _extractSingle(MapperParam p) {
    if (p.compose != null || p.raw[EmitNames.compose] != null) return null;
    final into = p.extract?.into;
    if (into == null || into.length != 1) return null;
    final spec = into.values.first;
    final path = spec is Map ? spec['path'] : spec;
    if (path is! String) return null;
    final v = _read(path);
    if (v == null) return null;
    _consumed.add(path);
    return _serializeValue(p, v);
  }





  void _consumeImplied(MapperParam p, String name, String path) {
    final into = p.extract?.into;
    if (into == null) return;
    for (final e in into.entries) {
      final spec = e.value;
      if (spec is! Map) continue;
      if (e.key != name && spec['path'] != path) continue;
      final implies = spec['implies'];
      if (implies is! Map) continue;
      for (final i in implies.keys) {
        _consumed.add('$i');
      }
    }
  }













  Set<String> _impliedOffGroups(MapperParam p) {
    final into = p.extract?.into;
    if (into == null) return const {};
    final off = <String>{};
    for (final e in into.entries) {
      final spec = e.value;
      if (spec is! Map) continue;
      final implies = spec['implies'];
      if (implies is! Map) continue;
      for (final i in implies.entries) {
        final want = i.value;
        final expected = want is Map ? want['value'] : want;
        if (_matches(_read('${i.key}'), expected)) continue;


        off.add(e.key);
        final path = spec['path'];
        if (path is String) off.add(path);
        break;
      }
    }
    return off;
  }







  String? _composeTemplate(
    MapperParam p,
    String template,
    String Function(String) pathOf,
    Set<String> omitEmpty,
  ) {
    final re = RegExp(r'\{([^{}]+)\}');
    final matches = re.allMatches(template).toList();
    if (matches.isEmpty) return null;

    final out = StringBuffer();
    var cursor = 0;
    var any = false;
    for (final m in matches) {
      final name = m.group(1)!;
      final path = pathOf(name);
      final v = _read(path);
      final text = v == null ? '' : '$v';
      final literal = template.substring(cursor, m.start);
      cursor = m.end;
      if (text.isEmpty || omitEmpty.contains(name)) {

        continue;
      }
      _consumed.add(path);



      _consumeImplied(p, name, path);
      out
        ..write(literal)
        ..write(text);
      any = true;
    }
    if (!any) return null;
    out.write(template.substring(cursor));
    final s = out.toString();
    return s.isEmpty ? null : s;
  }




  bool _roundTripOff(MapperParam p) {
    if (_paramEmitAttr(p, EmitNames.roundTrip) != false) return false;
    final path = p.mapsTo;
    if (path != null) _consumed.add(path);
    return true;
  }









  String? _firstTruthySpelling(MapperParam p) {
    for (final e in p.valueMap.entries) {
      final v = e.value;
      if (v == true || v == 'true') return e.key;
    }
    return null;
  }



  String? _serializeValue(MapperParam p, dynamic value) {
    final mode = _emitAs(p);
    switch (mode) {
      case EmitNames.emitAsBool01:
        if (value == false) return null;





        return _firstTruthySpelling(p) ?? '1';
      case EmitNames.emitAsJoin:
        final sep = p.list?.sep ?? ',';
        if (value is List) return value.isEmpty ? null : value.join(sep);
        return '$value';
      case EmitNames.emitAsJson:
        return jsonEncode(value);
    }







    if (value is bool &&
        _paramEmitAttr(p, EmitNames.emitAs) == EmitNames.emitAsRaw) {
      return value ? 'true' : null;
    }













    if (value is bool) {
      if (!value) return null;
      return _firstTruthySpelling(p) ?? 'true';
    }
    if (value is List) {
      if (value.isEmpty) return null;
      return value.join(p.list?.sep ?? ',');
    }
    if (value is Map) return jsonEncode(value);
    final text = '$value';
    return text.isEmpty ? null : text;
  }

  String _emitAs(MapperParam p) {

    final declared = _paramEmitAttr(p, EmitNames.emitAs);
    if (declared is String) return declared;
    if (p.list != null) return EmitNames.emitAsJoin;






    return EmitNames.emitAsRaw;
  }




  dynamic _paramEmitAttr(MapperParam p, String name) => p.raw[name];








  String _nameOf(MapperParam p) {
    final want = _declaredName(p);
    if (want != null) return want;
    return _queryCanonicalName(p);
  }


  String _queryCanonicalName(MapperParam p) {
    for (final s in [
      ...p.source,
      for (final v in p.sourceByForm.values) ...v,
    ]) {
      if (s.startsWith('query.')) return s.substring('query.'.length);
    }
    return p.name;
  }







  String? _declaredName(MapperParam p) {
    for (final src in [_formEmit()?[EmitNames.names], emit[EmitNames.names]]) {
      final want = (src as Map?)?[p.name];
      if (want is String && readableNames(p).contains(want)) return want;
    }
    return null;
  }


  Map<String, dynamic>? _formEmit() {
    final id = _form();
    for (final f in section.forms) {
      if (f.id == id) return f.emit;
    }
    return null;
  }

  void _add(MapperParam p, String value) {
    final name = _nameOf(p);
    if (_omitted(p, name, value)) return;
    _query.add((p, name, value));
  }


  int _encodePasses(MapperParam p) {
    final n = p.decodeExtra?.passes;
    if (n == null || n < 1) return 1;
    return n + 1;
  }


  String _encodeQueryValue(MapperParam p, String raw) {
    var val = raw;
    final passes = _encodePasses(p);
    for (var i = 1; i < passes; i++) {
      if (!val.contains('%')) break;
      val = _encodeParam(val);
    }
    return _encodeParam(val);
  }















  bool _alwaysEmitted(MapperParam p) {
    if (_paramEmitAttr(p, EmitNames.emitWhen) == EmitNames.emitWhenAlways) {
      return true;
    }
    final byName = (emit[EmitNames.emitWhen] as Map?)?[_nameOf(p)];
    return byName == EmitNames.emitWhenAlways;
  }

  bool _omitted(MapperParam p, String name, String value) {


    if (_alwaysEmitted(p)) return false;
    final ownOmit = _paramEmitAttr(p, EmitNames.omitDefault);
    if (ownOmit == false) return false;
    if (ownOmit == true) return _isDefaultValue(p, value);

    final omit = emit[EmitNames.omitDefault];
    if (omit is! List) return false;

    for (final raw in omit) {
      final n = '$raw';
      final i = n.indexOf(':');
      if (i > 0 && n.substring(0, i) == name) {
        if (_fold(n.substring(i + 1)) == _fold(value)) return true;
        continue;
      }
      if (n != name) continue;
















      if (_schemeSpellsBranch(p, value)) return true;
      return _isDefaultValue(p, value);
    }
    return false;
  }







  bool _schemeSpellsBranch(MapperParam p, String value) {
    final ff = emit[EmitNames.formFrom];
    if (ff is! Map || ff.isEmpty) return false;
    final branch = p.sets[value];
    if (branch is! Map || branch.isEmpty) return false;
    for (final k in branch.keys) {
      final key = '$k';
      if (key.startsWith(DraftNames.serviceParamPrefix)) continue;


      final spelled = ff.keys.any((f) {
        final path = '$f';
        return path == key ||
            path.startsWith('$key.') ||
            key.startsWith('$path.');
      });
      if (!spelled) return false;
    }
    return true;
  }











  bool _isDefaultValue(MapperParam p, String value) {
    final fallback = p.sets[''];
    if (fallback is Map) {
      final mine = p.sets[value];
      if (mine is Map) {
        return jsonEncode(_sorted(mine)) == jsonEncode(_sorted(fallback));
      }


      return false;
    }
    final path = p.mapsTo;
    if (path == null) return false;
    final d = section.defaults[path];
    return d != null && _fold(d) == _fold(value);
  }

  static Map<String, dynamic> _sorted(Map m) {
    final keys = m.keys.map((e) => '$e').toList()..sort();
    return {for (final k in keys) k: m[k]};
  }







  String _serializeQuery() {
    if (_query.isEmpty) return '';
    final order = emit[EmitNames.paramOrder];
    final pairs = [..._query];
    if (order == null || order == EmitNames.paramOrderAlphabetical) {
      pairs.sort((a, b) => a.$2.compareTo(b.$2));
    } else if (order is List) {
      final idx = {for (var i = 0; i < order.length; i++) '${order[i]}': i};
      pairs.sort((a, b) =>
          (idx[a.$2] ?? 1 << 20).compareTo(idx[b.$2] ?? 1 << 20));
    }
    return pairs
        .map((e) =>
            '${_encodeParam(e.$2)}=${_encodeQueryValue(e.$1, e.$3)}')
        .join('&');
  }













  String _emitJson(String scheme) {
    final map = <String, dynamic>{};
    final always = _jsonAlways();

    for (final e in _jsonMap().entries) {
      final v = _read(e.value);
      if (v == null) {
        if (always.containsKey(e.key)) map[e.key] = always[e.key]!;
        continue;
      }
      _consumed.add(e.value);




      final p = _jsonOwners[e.key];
      final text = p == null ? '$v' : _serializeValue(p, v);
      if (text == null) continue;
      map[e.key] = text;
    }








    for (final p in section.params.values) {
      if (p.isService || p.mapsTo != null || _roundTripOff(p)) continue;
      if (!_whenAgreesWithBody(p.when)) continue;
      final key = _jsonKeyOf(p);
      if (key == null || map.containsKey(key)) continue;
      final composed = _compose(p) ?? _extractSingle(p);
      if (composed == null) continue;
      if (_omitted(p, key, composed)) continue;
      map[key] = composed;
    }






    for (final p in section.params.values) {
      if (p.isService || p.mapsTo != null || p.sets.isEmpty) continue;
      if (_roundTripOff(p)) continue;
      final key = _jsonKeyOf(p);
      if (key == null || map.containsKey(key)) continue;
      final back = _valueFromSets(p);
      if (back != null && !_omitted(p, key, back)) map[key] = back;
    }




    final labelKey = _labelJsonKey();
    if (labelKey != null && label.isNotEmpty) map[labelKey] = label;

    for (final e in always.entries) {
      map.putIfAbsent(e.key, () => e.value);
    }

    final bytes = utf8.encode(jsonEncode(_orderedJson(map)));
    final encoded = base64.encode(bytes);
    return '$scheme://${_userinfoPadding() ? encoded : encoded.replaceAll('=', '')}';
  }



  Map<String, String> _jsonAlways() {
    final raw = emit[EmitNames.jsonAlways];
    if (raw is Map) {
      return {for (final e in raw.entries) '${e.key}': '${e.value}'};
    }
    if (raw is List) return {for (final k in raw) '$k': ''};
    return const {};
  }









  Map<String, dynamic> _orderedJson(Map<String, dynamic> map) {
    final order = emit[EmitNames.paramOrder];
    final keys = map.keys.toList();
    if (order == EmitNames.paramOrderAlphabetical) {
      keys.sort();
    } else if (order is List) {
      final idx = {for (var i = 0; i < order.length; i++) '${order[i]}': i};
      final at = {for (var i = 0; i < keys.length; i++) keys[i]: i};
      keys.sort((a, b) {
        final ia = idx[a] ?? (1 << 20) + at[a]!;
        final ib = idx[b] ?? (1 << 20) + at[b]!;
        return ia.compareTo(ib);
      });
    } else {
      return map;
    }
    return {for (final k in keys) k: map[k]};
  }



  String? _labelJsonKey() {
    final form = _form();
    final sources = section.label.sourceByForm[form] ?? section.label.source;
    for (final s in sources) {
      if (s.startsWith('json.')) return s.substring('json.'.length);
    }
    return null;
  }























  String? _jsonKeyOf(MapperParam p) {
    final sources = p.sourceByForm[_form()] ?? p.source;
    final declared = _declaredName(p);



    if (declared != null &&
        sources.any((s) => s.startsWith('query.')) &&
        !sources.any((s) => s.startsWith('json.'))) {
      return declared;
    }
    for (final s in sources) {
      if (s.startsWith('json.')) return s.substring('json.'.length);
      if (s.startsWith('query.')) {
        final name = s.substring('query.'.length);
        return name == p.name ? _nameOf(p) : name;
      }
    }
    return null;
  }



  Map<String, String> _jsonMap() {
    final declared = emit[EmitNames.jsonMap];
    if (declared is Map) {
      return {
        for (final e in declared.entries) '${e.key}': '${e.value}',
      };
    }
    final out = <String, String>{};
    _jsonOwners.clear();




















    for (final conditional in const [false, true]) {
      for (final p in section.params.values) {
        if (p.when.isEmpty == conditional) continue;
        if (p.isService || _roundTripOff(p)) continue;








        if (!_whenAgreesWithBody(p.when)) continue;
        final path = p.mapsTo;
        if (path == null) continue;
        final key = _jsonKeyOf(p);
        if (key == null) continue;
        if (out.containsKey(key)) continue;
        out[key] = path;
        _jsonOwners[key] = p;
      }
    }
    return out;
  }



  final Map<String, MapperParam> _jsonOwners = {};







  bool _whenAgreesWithBody(Map<String, dynamic> when) {
    if (when.isEmpty) return true;
    for (final e in when.entries) {
      final key = e.key;
      if (key.startsWith(r'$') ||
          key == 'any_set' ||
          key.startsWith('query.') ||
          key.startsWith('json.') ||
          key.startsWith('ini.')) {
        continue;
      }


      final actual = _read(key);
      if (actual == null) continue;
      if (!_matches(actual, e.value)) return false;
    }
    return true;
  }






  bool _refuse() {
    final raw = emit[EmitNames.refuseWhen];
    if (raw is! List) return false;
    for (final item in raw) {
      if (item is! Map) continue;
      if (_refuseRule(item.cast<String, dynamic>())) return true;
    }
    return false;
  }

  bool _refuseRule(Map<String, dynamic> rule) {
    final path = rule['path'];
    if (path is! String) return false;
    final actual = _read(path);
    final lenGt = rule['len_gt'];
    if (lenGt is num) {
      final n = actual is List ? actual.length : 0;
      return n > lenGt;
    }
    return false;
  }



  void _collectLost() {
    for (final path in _paths(body, '')) {

      if (path == 'type' || path == 'tag') continue;

      final owners = _pathOwners[path];
      if (owners != null && owners.any(_roundTripOnlyEmit)) continue;



      if (_consumedWithAncestors(path)) continue;
      _lost.add(path);
    }
  }

  bool _consumedWithAncestors(String path) {
    if (_consumed.contains(path)) return true;
    for (var i = path.indexOf('.'); i >= 0; i = path.indexOf('.', i + 1)) {
      if (_consumed.contains(path.substring(0, i))) return true;
    }
    return false;
  }








  static Iterable<String> _paths(Map<String, dynamic> m, String prefix) sync* {
    for (final e in m.entries) {
      final p = prefix.isEmpty ? e.key : '$prefix.${e.key}';
      final v = e.value;
      if (v is Map<String, dynamic> && v.isNotEmpty) {
        yield* _paths(v, p);
      } else if (v is List && v.isNotEmpty && v.first is Map<String, dynamic>) {



        for (var i = 0; i < v.length; i++) {
          final item = v[i];
          if (item is! Map<String, dynamic>) continue;
          yield* _paths(item, i == 0 ? '$p[]' : '$p[$i]');
        }
      } else {
        yield p;
      }
    }
  }











  dynamic _read(String path) {
    dynamic cur = body;
    for (final seg in path.split('.')) {
      if (seg.endsWith('[]')) {
        if (cur is! Map) return null;
        final list = cur[seg.substring(0, seg.length - 2)];
        if (list is! List || list.isEmpty) return null;
        cur = list.first;
        continue;
      }
      if (cur is! Map) return null;
      cur = cur[seg];
      if (cur == null) return null;
    }
    return cur;
  }

  static String? _str(dynamic v) => v == null ? null : '$v';

  static String _fold(dynamic v) => '$v'.trim().toLowerCase();

  static bool _matches(dynamic actual, dynamic expected) {
    if (expected == null) return actual == null;
    if (actual == null) return false;
    return _fold(actual) == _fold(expected);
  }

  static String _wrapIpv6(String host) =>
      host.contains(':') && !host.startsWith('[') ? '[$host]' : host;


  static String _encodeParam(String s) =>
      Uri.encodeQueryComponent(s).replaceAll('+', '%20');

  static String _encodeFragment(String s) =>
      Uri.encodeComponent(s).replaceAll('+', '%20');
}















































bool _isUntranslatedCanon(MapperParam p, dynamic value) {
  final v = '$value'.trim().toLowerCase();
  var isTarget = false;
  for (final e in p.valueMap.entries) {
    if (e.key.trim().toLowerCase() == v) return false;
    if (e.value != null && '${e.value}'.trim().toLowerCase() == v) {
      isTarget = true;
    }
  }
  return isTarget;
}


















Map<String, String>? invertValueMap(Map<String, dynamic> vm) {
  if (vm.isEmpty) return null;
  final out = <String, String>{};
  for (final e in vm.entries) {
    if (e.value == null) continue;

    if (e.value is Map || e.value is List) return null;

    if (e.key.isEmpty) continue;
    final key = '${e.value}'.trim().toLowerCase();

    out.putIfAbsent(key, () => e.key);
  }
  return out.isEmpty ? null : out;
}
