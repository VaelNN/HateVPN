











library;







abstract final class DraftNames {


  static const serviceParamPrefix = r'$';


  static const baseAnchor = r'$base';


  static const iniCommentPrefix = r'ini.$comment.';


  static const iniDialect = 'ini_dialect';


  static const emitFormFrom = 'form_from';


  static const unwrap = 'unwrap';
}


final class MapperForm {
  const MapperForm({
    required this.id,
    this.detect,
    this.decode = const [],
    this.space = 'url',
    this.base,
    this.level,
    this.emit,
  });

  factory MapperForm.fromJson(Map<String, dynamic> j) => MapperForm(
        id: j['id'] as String? ?? '',
        detect: (j['detect'] as Map?)?.cast<String, dynamic>(),
        decode: ((j['decode'] as List?) ?? const []).toList(),
        space: j['space'] as String? ?? 'url',
        base: j['base'] as String?,
        level: j['level'] as String?,
        emit: (j['emit'] as Map?)?.cast<String, dynamic>(),
      );

  final String id;
  final Map<String, dynamic>? detect;



  final List<dynamic> decode;


  final String space;


  final String? base;


  final String? level;












  final Map<String, dynamic>? emit;
}








final class OverlaySpec {
  const OverlaySpec({
    required this.name,
    this.source = const [],
    this.decode = const [],
    this.flatten = const [],
  });

  factory OverlaySpec.fromJson(Map<String, dynamic> j) => OverlaySpec(
        name: j['name'] as String? ?? '',
        source: _stringList(j['source'], fallback: const []),
        decode: ((j['decode'] as List?) ?? const []).cast<String>(),
        flatten: ((j['flatten'] as List?) ?? const []).cast<String>(),
      );


  final String name;


  final List<String> source;


  final List<String> decode;


  final List<String> flatten;
}


final class UserinfoSpec {
  const UserinfoSpec({
    this.decode = const [],
    this.decodeRequiresSeparator,
    this.splitSep,
    this.splitLimit,
    this.into = const [],
    this.singleInto,
    this.required = false,
  });

  factory UserinfoSpec.fromJson(Map<String, dynamic> j) {
    final split = (j['split'] as Map?)?.cast<String, dynamic>();
    return UserinfoSpec(
      required: j['required'] as bool? ?? false,
      decode: ((j['decode'] as List?) ?? const []).cast<String>(),
      decodeRequiresSeparator: j['decode_requires_separator'] as String?,
      splitSep: split?['sep'] as String?,


      splitLimit: (split?['limit'] as num?)?.toInt(),
      into: ((j['into'] as List?) ?? const []).cast<String>(),
      singleInto: j['single_into'] as String?,
    );
  }

  final List<String> decode;














  final String? decodeRequiresSeparator;
  final String? splitSep;
  final int? splitLimit;
  final List<String> into;
  final String? singleInto;





  final bool required;
}


final class LabelSpec {
  const LabelSpec({
    this.source = const ['fragment'],
    this.sourceByForm = const {},
    this.normalize = const [],
    this.valueMap = const {},
    this.fallbackTemplate,
    this.fallbackSchemeSource = 'singbox_type',
    this.fallbackScheme,
    this.fallbackServerPath,
    this.fallbackPortPath,
  });

  factory LabelSpec.fromJson(Map<String, dynamic> j) {
    final fb = (j['fallback'] as Map?)?.cast<String, dynamic>();






    final srcRaw = j['source'];
    return LabelSpec(
      source: srcRaw is Map
          ? const []
          : _stringList(srcRaw, fallback: const ['fragment']),
      sourceByForm: srcRaw is Map
          ? srcRaw.map((k, v) =>
              MapEntry(k as String, _stringList(v, fallback: const [])))
          : const {},
      normalize: ((j['normalize'] as List?) ?? const []).cast<String>(),
      valueMap: ((j['value_map'] as Map?) ?? const {}).cast<String, dynamic>(),
      fallbackTemplate: fb?['template'] as String?,



      fallbackSchemeSource: fb?['scheme_source'] as String? ?? 'singbox_type',







      fallbackScheme: fb?['scheme'] as String?,





      fallbackServerPath: fb?['server_path'] as String?,
      fallbackPortPath: fb?['port_path'] as String?,
    );
  }

  final List<String> source;



  final Map<String, List<String>> sourceByForm;
  final List<String> normalize;
  final Map<String, dynamic> valueMap;
  final String? fallbackTemplate;
  final String fallbackSchemeSource;
  final String? fallbackScheme;
  final String? fallbackServerPath;
  final String? fallbackPortPath;
}


final class ListSpec {
  const ListSpec({this.sep = ',', this.item, this.len, this.coerceScalar = false});

  factory ListSpec.fromJson(Map<String, dynamic> j) => ListSpec(
        sep: j['sep'] as String? ?? ',',
        item: j['item'] as String?,
        len: (j['len'] as num?)?.toInt(),
        coerceScalar: j['coerce_scalar'] as bool? ?? false,
      );

  final String sep;
  final String? item;
  final int? len;
  final bool coerceScalar;
}


final class IniSectionRule {
  const IniSectionRule({this.repeat, this.onExtraCode});

  factory IniSectionRule.fromJson(Map<String, dynamic> j) => IniSectionRule(
        repeat: j['repeat'] as String?,
        onExtraCode: ((j['on_extra'] as Map?)?['code']) as String?,
      );


  final String? repeat;


  final String? onExtraCode;
}








final class IniDialect {
  const IniDialect({
    this.keyCase = 'lower',
    this.valueCase = 'preserve',
    this.lineCommentPrefixes = const ['#', ';'],
    this.inlineComments = false,
    this.repeatedKey = 'last_wins',
    this.sections = const {},
  });

  factory IniDialect.fromJson(Map<String, dynamic> j) => IniDialect(
        keyCase: j['key_case'] as String? ?? 'lower',
        valueCase: j['value_case'] as String? ?? 'preserve',




        lineCommentPrefixes: ((j['line_comment_prefixes'] ??
                    j['comment_prefixes']) as List?)
                ?.cast<String>() ??
            const ['#', ';'],
        inlineComments: j['inline_comments'] as bool? ?? false,
        repeatedKey: j['repeated_key'] as String? ?? 'last_wins',
        sections: {
          for (final e
              in ((j['sections'] as Map?) ?? const {}).cast<String, dynamic>().entries)
            e.key.toLowerCase():
                IniSectionRule.fromJson((e.value as Map).cast<String, dynamic>()),
        },
      );


  final String keyCase;


  final String valueCase;


  final List<String> lineCommentPrefixes;



  final bool inlineComments;


  final String repeatedKey;


  final Map<String, IniSectionRule> sections;

  IniSectionRule? sectionRule(String name) => sections[name.toLowerCase()];
}


final class DecodeExtraSpec {
  const DecodeExtraSpec({
    this.mode = 'query',
    this.passes,
    this.untilStable = false,
    this.max = 16,
    this.plusLiteral,
  });

  factory DecodeExtraSpec.fromJson(Map<String, dynamic> j) {
    final p = j['passes'];
    return DecodeExtraSpec(
      mode: j['mode'] as String? ?? 'query',
      passes: p is num ? p.toInt() : null,
      untilStable: p == 'until_stable',
      max: (j['max'] as num?)?.toInt() ?? 16,
      plusLiteral: j['plus_literal'] as bool?,
    );
  }

  final String mode;
  final int? passes;
  final bool untilStable;
  final int max;


  final bool? plusLiteral;
}


final class ExtractSpec {
  const ExtractSpec({required this.re, this.into = const {}});

  factory ExtractSpec.fromJson(Map<String, dynamic> j) => ExtractSpec(
        re: j['re'] as String? ?? '',
        into: ((j['into'] as Map?) ?? const {}).cast<String, dynamic>(),
      );

  final String re;


  final Map<String, dynamic> into;
}


final class MapperParam {
  const MapperParam({
    required this.name,
    this.source = const [],
    this.sourceByForm = const {},
    this.mapsTo,
    this.mapsToPresent = false,
    this.aliases = const [],
    this.type,
    this.required = false,
    this.selector = false,
    this.priority,
    this.merge,
    this.valueMap = const {},
    this.allow = const [],
    this.sets = const {},
    this.implies = const {},
    this.when = const {},
    this.extract,
    this.compose,
    this.list,
    this.splitInto = const {},
    this.normalize,
    this.decodeExtra,
    this.defaultFrom = const [],
    this.defaultWhen = const {},
    this.materializeDefault = false,
    this.coerceObjectToScalar,
    this.coerceScalarToList = false,
    this.flatten = const [],
    this.lift,
    this.sortKeys = false,
    this.empty = 'absent',
    this.format,
    this.onInvalid = const {},
    this.onPresent = const {},
    this.onLenGt = const {},
    this.onNoMatch = const {},
    this.onWhenFalse = const {},
    this.onImpliesWritten = const {},
    this.onItemInvalid = const {},
    this.onEmpty = const {},
    this.valueMapCase,
    this.implicit = false,
    this.roundTripOnly,
    this.raw = const {},
  });

  factory MapperParam.fromJson(String name, Map<String, dynamic> j) {
    final srcRaw = j['source'];
    var source = <String>[];
    var byForm = <String, List<String>>{};
    if (srcRaw is String) {
      source = [srcRaw];
    } else if (srcRaw is List) {
      source = srcRaw.cast<String>();
    } else if (srcRaw is Map) {
      byForm = srcRaw.map((k, v) =>
          MapEntry(k as String, _stringList(v, fallback: const [])));
    }

    final coerce = (j['coerce'] as Map?)?.cast<String, dynamic>();
    final de = (j['decode_extra'] as Map?)?.cast<String, dynamic>();
    final ex = (j['extract'] as Map?)?.cast<String, dynamic>();
    final ls = (j['list'] as Map?)?.cast<String, dynamic>();

    return MapperParam(
      name: name,
      source: source,
      sourceByForm: byForm,
      mapsTo: j['maps_to'] as String?,



      mapsToPresent: j.containsKey('maps_to'),
      aliases: ((j['aliases'] as List?) ?? const []).cast<String>(),
      type: j['type'] as String?,
      required: j['required'] as bool? ?? false,
      selector: j['selector'] as bool? ?? false,
      priority: (j['priority'] as num?)?.toInt(),
      merge: j['merge'] as String?,
      valueMap: ((j['value_map'] as Map?) ?? const {}).cast<String, dynamic>(),
      allow: ((j['allow'] as List?) ?? const []).cast<String>(),
      sets: ((j['sets'] as Map?) ?? const {}).cast<String, dynamic>(),
      implies: ((j['implies'] as Map?) ?? const {}).cast<String, dynamic>(),
      when: ((j['when'] as Map?) ?? const {}).cast<String, dynamic>(),
      extract: ex == null ? null : ExtractSpec.fromJson(ex),





      compose: j['compose'] is String ? j['compose'] as String : null,
      list: ls == null ? null : ListSpec.fromJson(ls),
      splitInto:
          ((j['split_into'] as Map?) ?? const {}).cast<String, dynamic>(),
      normalize: j['normalize'] as String?,
      decodeExtra: de == null ? null : DecodeExtraSpec.fromJson(de),
      defaultFrom: _stringList(j['default_from'], fallback: const []),
      defaultWhen:
          ((j['default_when'] as Map?) ?? const {}).cast<String, dynamic>(),
      materializeDefault: j['materialize_default'] as bool? ?? false,
      coerceObjectToScalar: coerce?['object_to_scalar'] as String?,
      coerceScalarToList: coerce?['scalar_to_list'] as bool? ?? false,
      flatten: ((j['flatten'] as List?) ?? const []).cast<String>(),
      lift: j['lift'] as String?,
      sortKeys: j['sort_keys'] as bool? ?? false,
      empty: j['empty'] as String? ?? 'absent',
      format: j['format'] as String?,
      onInvalid:
          ((j['on_invalid'] as Map?) ?? const {}).cast<String, dynamic>(),
      onPresent:
          ((j['on_present'] as Map?) ?? const {}).cast<String, dynamic>(),
      onLenGt:
          ((j['on_len_gt'] as Map?) ?? const {}).cast<String, dynamic>(),
      onNoMatch:
          ((j['on_no_match'] as Map?) ?? const {}).cast<String, dynamic>(),
      onWhenFalse:
          ((j['on_when_false'] as Map?) ?? const {}).cast<String, dynamic>(),
      onImpliesWritten: ((j['on_implies_written'] as Map?) ?? const {})
          .cast<String, dynamic>(),
      onItemInvalid:
          ((j['on_item_invalid'] as Map?) ?? const {}).cast<String, dynamic>(),
      onEmpty: ((j['on_empty'] as Map?) ?? const {}).cast<String, dynamic>(),
      valueMapCase: j['value_map_case'] as String?,
      implicit: j['implicit'] as bool? ?? false,
      roundTripOnly: j['round_trip_only'] as String?,
      raw: j,
    );
  }

  final String name;
  final List<String> source;
  final Map<String, List<String>> sourceByForm;
  final String? mapsTo;
  final bool mapsToPresent;
  final List<String> aliases;
  final String? type;
  final bool required;
  final bool selector;
  final int? priority;
  final String? merge;
  final Map<String, dynamic> valueMap;










  final List<String> allow;
  final Map<String, dynamic> sets;
  final Map<String, dynamic> implies;
  final Map<String, dynamic> when;
  final ExtractSpec? extract;
  final String? compose;
  final ListSpec? list;
  final Map<String, dynamic> splitInto;
  final String? normalize;
  final DecodeExtraSpec? decodeExtra;
  final List<String> defaultFrom;
  final Map<String, dynamic> defaultWhen;
  final bool materializeDefault;
  final String? coerceObjectToScalar;
  final bool coerceScalarToList;
  final List<String> flatten;
  final String? lift;
  final bool sortKeys;
  final String empty;



  final String? format;
  final Map<String, dynamic> onInvalid;
  final Map<String, dynamic> onPresent;





  final Map<String, dynamic> onLenGt;



  final Map<String, dynamic> onNoMatch;





  final Map<String, dynamic> onWhenFalse;





  final Map<String, dynamic> onImpliesWritten;




  final Map<String, dynamic> onItemInvalid;












  final Map<String, dynamic> onEmpty;





  final String? valueMapCase;

  final bool implicit;



  final String? roundTripOnly;








  final Map<String, dynamic> raw;



  Map<String, dynamic>? get deref => (raw['deref'] as Map?)?.cast<String, dynamic>();



  Map<String, dynamic>? get substitute =>
      (raw['substitute'] as Map?)?.cast<String, dynamic>();



  bool get isService => name.startsWith(DraftNames.serviceParamPrefix);


  bool get plusLiteral =>
      decodeExtra?.plusLiteral ?? (format?.startsWith('base64') ?? false);


  Iterable<String> get spellings sync* {
    yield name;
    yield* aliases;
  }
}


final class MapperSection {
  const MapperSection({
    required this.kind,
    required this.singboxType,
    this.detect,
    this.bodySource = 'uri',
    this.forms = const [],
    this.userinfo,
    this.label = const LabelSpec(),
    this.params = const {},
    this.include = const [],
    this.overlays = const [],
    this.schemeSets = const {},
    this.typeSynonyms = const {},
    this.defaults = const {},
    this.unknownKeyAction = 'drop',
    this.unknownKeyCode,
    this.ignoredKeys = const {},
    this.nestedQuiet = const {},
    this.kindWhen = const {},
    this.iniDialect,
    this.emit,
  });

  factory MapperSection.fromJson(
    String kind,
    String singboxType,
    Map<String, dynamic> j,
  ) {
    final uk = (j['unknown_key'] as Map?)?.cast<String, dynamic>();
    final params = <String, MapperParam>{};






    final nullParams = <String>{};
    final rawParams = (j['params'] as Map?)?.cast<String, dynamic>() ?? const {};
    for (final e in rawParams.entries) {
      if (e.value == null) {
        nullParams.add(e.key);
        continue;
      }
      params[e.key] =
          MapperParam.fromJson(e.key, (e.value as Map).cast<String, dynamic>());
    }
    return MapperSection(
      kind: kind,
      singboxType: singboxType,
      detect: (j['detect'] as Map?)?.cast<String, dynamic>(),
      bodySource: j['body_source'] as String? ?? 'uri',
      forms: ((j['forms'] as List?) ?? const [])
          .map((f) => MapperForm.fromJson((f as Map).cast<String, dynamic>()))
          .toList(),
      userinfo: j['userinfo'] == null
          ? null
          : UserinfoSpec.fromJson((j['userinfo'] as Map).cast<String, dynamic>()),
      label: j['label'] == null
          ? const LabelSpec()
          : LabelSpec.fromJson((j['label'] as Map).cast<String, dynamic>()),
      params: params,
      include: ((j['include'] as List?) ?? const []).cast<String>(),
      overlays: ((j['overlays'] as List?) ?? const [])
          .map((o) => OverlaySpec.fromJson((o as Map).cast<String, dynamic>()))
          .toList(),
      schemeSets:
          ((j['scheme_sets'] as Map?) ?? const {}).cast<String, dynamic>(),
      typeSynonyms:
          ((j['type_synonyms'] as Map?) ?? const {}).cast<String, String>(),
      defaults: ((j['defaults'] as Map?) ?? const {}).cast<String, dynamic>(),
      unknownKeyAction: uk?['action'] as String? ?? 'drop',
      unknownKeyCode: uk?['code'] as String?,
      ignoredKeys: <String>{
        ...((uk?['ignore'] as List?) ?? const []).cast<String>(),
        ...nullParams,
      },
      nestedQuiet:
          ((uk?['nested_quiet'] as List?) ?? const []).cast<String>().toSet(),
      kindWhen: ((j['kind_when'] as Map?) ?? const {}).cast<String, dynamic>(),
      iniDialect: j[DraftNames.iniDialect] == null
          ? null
          : IniDialect.fromJson(
              (j[DraftNames.iniDialect] as Map).cast<String, dynamic>()),
      emit: (j['emit'] as Map?)?.cast<String, dynamic>(),
    );
  }











  final Map<String, dynamic> kindWhen;


  final String kind;


  final String singboxType;

  final Map<String, dynamic>? detect;
  final String bodySource;
  final List<MapperForm> forms;
  final UserinfoSpec? userinfo;
  final LabelSpec label;
  final Map<String, MapperParam> params;
  final List<String> include;


  final List<OverlaySpec> overlays;
  final Map<String, dynamic> schemeSets;
  final Map<String, String> typeSynonyms;
  final Map<String, dynamic> defaults;
  final String unknownKeyAction;
  final String? unknownKeyCode;





  final Set<String> ignoredKeys;









  final Set<String> nestedQuiet;



  final IniDialect? iniDialect;

  final Map<String, dynamic>? emit;


  MapperSection withParams(Map<String, MapperParam> merged) => MapperSection(
        kind: kind,
        singboxType: singboxType,
        detect: detect,
        bodySource: bodySource,
        forms: forms,
        userinfo: userinfo,
        label: label,
        params: merged,
        include: include,
        overlays: overlays,
        schemeSets: schemeSets,
        typeSynonyms: typeSynonyms,
        defaults: defaults,
        unknownKeyAction: unknownKeyAction,
        unknownKeyCode: unknownKeyCode,
        ignoredKeys: ignoredKeys,
        nestedQuiet: nestedQuiet,
        kindWhen: kindWhen,
        iniDialect: iniDialect,
        emit: emit,
      );
}

List<String> _stringList(dynamic v, {required List<String> fallback}) {
  if (v is String) return [v];
  if (v is List) return v.cast<String>();
  return fallback;
}
