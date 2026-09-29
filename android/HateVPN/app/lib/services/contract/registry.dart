















library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show AssetManifest, rootBundle;



typedef AssetLoader = Future<String> Function(String path);



typedef AssetLister = Future<List<String>> Function();


const _kProtocolsDir = 'registry/protocols/';


const _kSharedRefs = <String, String>{
  'tls': 'tls.json',
  'transports': 'transports.json',
  'multiplex': 'multiplex.json',
  'dialer': 'dialer.json',
  'dialer.common': 'dialer.json',
};



const _kStandaloneShared = <String>['source_kinds.json', 'allowlists.json'];






final class FieldSchema {
  FieldSchema(this.raw)
      : _nested = null,
        _variants = null;



  FieldSchema._expanded(this.raw, this._nested, this._variants);

  final Map<String, dynamic> raw;

  final Map<String, FieldSchema>? _nested;
  final Map<String, FieldSchema>? _variants;

  String get type => raw['type'] as String? ?? 'string';



  String? get ref => raw['ref'] as String?;





  String? get originRef => raw['origin_ref'] as String?;




  String? get discriminator => raw['discriminator'] as String?;

  late final Map<String, FieldSchema>? variants = _variants ?? _parseVariants();

  Map<String, FieldSchema>? _parseVariants() {
    final v = raw['variants'];
    if (v is! Map) return null;
    return {
      for (final e in v.entries)
        e.key as String: FieldSchema((e.value as Map).cast<String, dynamic>()),
    };
  }

  bool get inline => raw['inline'] == true;



  bool get managed => raw['managed'] == true;

  bool get required => raw['required'] == true;

  bool get secret => raw['secret'] == true;

  bool get allOrNothing => raw['all_or_nothing'] == true;



  String? get normalize => raw['normalize'] as String?;




  String? get normalizeCode => raw['normalize_code'] as String?;








  Map<String, dynamic>? get defaultWhen =>
      (raw['default_when'] as Map?)?.cast<String, dynamic>();












  Map<String, dynamic>? get maxWhen =>
      (raw['max_when'] as Map?)?.cast<String, dynamic>();




















  Map<String, dynamic>? get minWhen =>
      (raw['min_when'] as Map?)?.cast<String, dynamic>();












  Map<String, dynamic>? get absentWhen =>
      (raw['absent_when'] as Map?)?.cast<String, dynamic>();

  String? get format => raw['format'] as String?;












  String? get pattern => raw['pattern'] as String?;















  String? get itemPattern => raw['item_pattern'] as String?;








  Map<String, dynamic>? get onItemInvalid =>
      (raw['on_item_invalid'] as Map?)?.cast<String, dynamic>();








  List<String>? get absentValues =>
      (raw['absent_values'] as List?)?.map((e) => '$e').toList();


  String? get minCore => raw['min_core'] as String?;


  String? get platform => raw['platform'] as String?;



  String? get buildTag => raw['build_tag'] as String?;





  CoreUnsupported? get onCoreUnsupported =>
      CoreUnsupported.tryParse(raw['on_core_unsupported']);



  RangeForm? get rangeForm => RangeForm.tryParse(raw['range_form']);




  String? get level => raw['level'] as String?;

  String? get levelMark => raw['level_mark'] as String?;

  num? get min => raw['min'] as num?;

  num? get max => raw['max'] as num?;

  int? get len => raw['len'] as int?;


  String? get lenParity => raw['len_parity'] as String?;

  List<Object?>? get values => (raw['values'] as List?)?.cast<Object?>();

  Map<String, dynamic>? get onInvalid =>
      (raw['on_invalid'] as Map?)?.cast<String, dynamic>();

  List<String>? get forbiddenFor =>
      (raw['forbidden_for'] as List?)?.cast<String>();

  List<String>? get allowedFor => (raw['allowed_for'] as List?)?.cast<String>();


  String? get code => raw['code'] as String?;










  Map<String, String>? get forbiddenCodes =>
      (raw['forbidden_codes'] as Map?)?.map((k, v) => MapEntry('$k', '$v'));



  String? forbiddenCodeFor(String scheme) =>
      forbiddenCodes?[scheme] ?? code;




  late final List<Map<String, dynamic>> conflicts = _relations('conflicts');

  late final List<Map<String, dynamic>> requires = _relations('requires');


  late final List<Map<String, dynamic>> advisory = _relations('advisory');













  List<Map<String, dynamic>> _relations(String key) {
    final raw0 = (raw[key] as List?) ?? const [];
    final out = <Map<String, dynamic>>[];
    for (final e in raw0) {
      if (e is Map) {
        out.add(e.cast<String, dynamic>());
      } else if (e is String && e.isNotEmpty) {


        out.add(key == 'requires' ? {'path': e} : {'with': e});
      }
    }
    return List.unmodifiable(out);
  }

  Object? get defaultValue => raw['default'];


  FieldSchema? get items {
    final it = raw['items'];
    return it is Map ? FieldSchema(it.cast<String, dynamic>()) : null;
  }



  late final List<String>? order =
      (raw['order'] as List?)?.cast<String>().toList(growable: false);



  late final Map<String, FieldSchema>? fields = _nested ?? _parseFields();

  Map<String, FieldSchema>? _parseFields() {
    final f = raw['fields'];
    if (f is! Map) return null;
    return {
      for (final e in f.entries)
        e.key as String: FieldSchema((e.value as Map).cast<String, dynamic>()),
    };
  }
}




final class BodySchema {
  const BodySchema({
    required this.core,
    required this.order,
    required this.fields,
    this.relations = const [],
    this.absentWhen,
    this.exitCapableWhen,
    this.buildTag,
    this.minCore,
    this.onCoreUnsupported,
    this.levels = const [],
    this.fieldsUnchecked = false,
  });




  final bool fieldsUnchecked;


  final String core;



  final String? buildTag;
  final String? minCore;



  final CoreUnsupported? onCoreUnsupported;



  final List<String> levels;

  final List<String> order;

  final Map<String, FieldSchema> fields;








  final List<Map<String, dynamic>> relations;




  final Map<String, dynamic>? absentWhen;




  final Map<String, dynamic>? exitCapableWhen;

}



final class CoreUnsupported {
  const CoreUnsupported({required this.action, required this.code});


  final String action;
  final String code;

  bool get dropsNode => action == 'drop_node';

  static CoreUnsupported? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final action = raw['action'];
    final code = raw['code'];
    if (action is! String || code is! String) return null;
    return CoreUnsupported(action: action, code: code);
  }
}



final class RangeForm {
  const RangeForm({
    this.minCore,
    this.buildTag,
    this.level,
    this.onCoreUnsupported,
  });

  final String? minCore;
  final String? buildTag;
  final String? level;
  final CoreUnsupported? onCoreUnsupported;

  static RangeForm? tryParse(Object? raw) {
    if (raw is! Map) return null;
    return RangeForm(
      minCore: raw['min_core'] as String?,
      buildTag: raw['build_tag'] as String?,
      level: raw['level'] as String?,
      onCoreUnsupported: CoreUnsupported.tryParse(raw['on_core_unsupported']),
    );
  }
}


final class WarningText {
  const WarningText({
    required this.code,
    required this.severity,
    required this.titleEn,
    required this.titleRu,
    required this.textEn,
    required this.textRu,
    required this.params,
    this.causeEn,
    this.causeRu,
    this.fixEn = const [],
    this.fixRu = const [],
  });

  final String code;


  final String severity;

  final String titleEn;
  final String titleRu;
  final String textEn;
  final String textRu;




  final String? causeEn;
  final String? causeRu;


  final List<String> fixEn;
  final List<String> fixRu;


  final List<String> params;
}





final class ContractRegistry {
  ContractRegistry._();

  static final ContractRegistry I = ContractRegistry._();

  static const _assetRoot = 'assets/contract';

  String _version = '';
  final Map<String, Map<String, dynamic>> _protocols = {};
  final Map<String, Map<String, dynamic>> _shared = {};
  final Map<String, WarningText> _warnings = {};




  final Map<String, _SchemaSlot> _schemaCache = {};
  bool _loaded = false;








  int _generation = 0;

  int get generation => _generation;

  bool get isLoaded => _loaded;



  @visibleForTesting
  void resetForTesting() {
    _loaded = false;
    _version = '';
    _protocols.clear();
    _shared.clear();
    _warnings.clear();
    _schemaCache.clear();
    _transportCache.clear();
    _sharedCache.clear();
    _generation++;
  }


  String get version => _version;







  Future<void> load({AssetLoader? loader, AssetLister? lister}) async {
    final read = loader ?? (String p) => rootBundle.loadString(p);
    final list = lister ??
        () async =>
            (await AssetManifest.loadFromAssetBundle(rootBundle)).listAssets();
    const prefix = '$_assetRoot/$_kProtocolsDir';
    await _load(
      (rel) => read('$_assetRoot/$rel'),
      () async => _protocolFileNames(
          (await list()).where((p) => p.startsWith(prefix)).map(
                (p) => p.substring(prefix.length),
              )),
    );
  }





  Future<void> loadFromDirectory(String dir) async {
    await _load(
      (rel) => File('$dir/$rel').readAsString(),
      () async => _protocolFileNames(Directory('$dir/$_kProtocolsDir')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)),
    );
  }



  static List<String> _protocolFileNames(Iterable<String> names) => names
      .where((n) => n.endsWith('.json') && !n.contains('/'))
      .map((n) => n.substring(0, n.length - '.json'.length))
      .toList()
    ..sort();

  Future<void> _load(
    Future<String> Function(String rel) read,
    Future<List<String>> Function() listProtocols,
  ) async {
    _version = (await read('VERSION')).trim();

    for (final entry in _kSharedRefs.entries) {

      if (_shared.containsKey(entry.value)) continue;
      _shared[entry.value] =
          jsonDecode(await read('registry/${entry.value}')) as Map<String, dynamic>;
    }









    for (final name in _kStandaloneShared) {
      if (_shared.containsKey(name)) continue;
      try {
        _shared[name] =
            jsonDecode(await read('registry/$name')) as Map<String, dynamic>;
      } catch (_) {

      }
    }



    for (final scheme in await listProtocols()) {
      final data = jsonDecode(await read('$_kProtocolsDir$scheme.json'))
          as Map<String, dynamic>;



      final singboxType = data['singbox_type'] as String? ?? scheme;
      _protocols[singboxType] = data;
      _generation++;
    }

    final warnings = jsonDecode(await read('registry/warnings.json'))
        as Map<String, dynamic>;
    final byCode = (warnings['warnings'] as Map).cast<String, dynamic>();


    final implicit =
        ((warnings['text_params_implicit'] as List?) ?? const []).cast<String>();
    for (final e in byCode.entries) {
      final w = (e.value as Map).cast<String, dynamic>();
      _warnings[e.key] = WarningText(
        code: e.key,
        severity: w['severity'] as String? ?? 'warning',
        titleEn: w['title_en'] as String? ?? '',
        titleRu: w['title_ru'] as String? ?? '',
        textEn: w['text_en'] as String? ?? '',
        textRu: w['text_ru'] as String? ?? '',



        causeEn: w['cause_en'] as String?,
        causeRu: w['cause_ru'] as String?,
        fixEn: _stringList(w['fix_en']),
        fixRu: _stringList(w['fix_ru']),
        params: [
          ...implicit,
          ...((w['params'] as List?) ?? const []).cast<String>(),
        ],
      );
    }



    _schemaCache.clear();
    _transportCache.clear();
    _sharedCache.clear();
    _generation++;

    _loaded = true;
  }











  BodySchema? schemaFor(String singboxType) {
    final cached = _schemaCache[singboxType];
    if (cached != null) return cached.schema;
    final proto = _protocols[singboxType];
    Map<String, dynamic>? body;
    if (proto != null) body = (proto['body'] as Map?)?.cast<String, dynamic>();
    final schema = body == null ? null : _expand(body);
    _schemaCache[singboxType] = _SchemaSlot(schema);
    return schema;
  }



  BodySchema? transportVariant(String type) {
    final cached = _transportCache[type];
    if (cached != null) return cached.schema;
    final schema = _transportVariant(type);
    _transportCache[type] = _SchemaSlot(schema);
    return schema;
  }

  final Map<String, _SchemaSlot> _transportCache = {};

  BodySchema? _transportVariant(String type) {
    final body =
        (_shared['transports.json']?['body'] as Map?)?.cast<String, dynamic>();
    if (body == null) return null;
    final variant = (body['variants'] as Map?)?[type];
    if (variant is! Map) return null;
    final v = variant.cast<String, dynamic>();
    return BodySchema(
      core: body['core'] as String? ?? '',
      order: ((v['order'] as List?) ?? const []).cast<String>(),
      fields: _fieldsOf(v),
    );
  }








  BodySchema? sharedSchema(String ref) {
    final cached = _sharedCache[ref];
    if (cached != null) return cached.schema;
    final schema = _sharedSchema(ref);
    _sharedCache[ref] = _SchemaSlot(schema);
    return schema;
  }

  final Map<String, _SchemaSlot> _sharedCache = {};

  BodySchema? _sharedSchema(String ref) {
    final file = _kSharedRefs[ref];
    if (file == null) return null;
    final data = _shared[file];
    if (data == null) return null;

    final section = ref == 'dialer.common' ? 'common' : 'body';
    final body = (data[section] as Map?)?.cast<String, dynamic>();
    if (body == null || body.containsKey('variants')) return null;
    return _expand(body);
  }


  WarningText? textFor(String code) => _warnings[code];









  Map<String, dynamic>? rawProtocol(String singboxType) =>
      _protocols[singboxType];




  bool isEndpointType(String singboxType) =>
      _protocols[singboxType]?['kind'] == 'endpoint';




  bool isUncheckedType(String singboxType) =>
      schemaFor(singboxType)?.fieldsUnchecked == true;





  Iterable<String> get protocolNames => _protocols.keys;





  Map<String, dynamic>? rawShared(String fileName) => _shared[fileName];





  Set<String>? allowlistValues(String name) {
    final lists = _shared['allowlists.json']?['allowlists'];
    if (lists is! Map) return null;
    final values = (lists[name] as Map?)?['values'];
    if (values is! List) return null;
    return values.whereType<String>().toSet();
  }
















  BodySchema _expand(Map<String, dynamic> body) {
    final rawFields = _fieldsOf(body);
    final rawOrder = ((body['order'] as List?) ?? const []).cast<String>();

    final order = <String>[];
    final fields = <String, FieldSchema>{};
    for (final key in rawOrder) {
      final f = rawFields[key];
      if (f == null) continue;
      if (f.inline && f.ref != null) {
        final sub = sharedSchema(f.ref!);
        if (sub == null) continue;


        for (final k in sub.order) {
          final sf = sub.fields[k];
          if (sf == null || fields.containsKey(k)) continue;
          order.add(k);
          fields[k] = sf;
        }
        continue;
      }
      order.add(key);
      fields[key] = f.type == 'ref' && f.ref != null
          ? (_resolveRef(key, f, f.ref!) ?? f)
          : f;
    }


    for (final e in rawFields.entries) {
      if (fields.containsKey(e.key)) continue;
      if (e.value.inline) continue;
      final f = e.value;
      order.add(e.key);
      fields[e.key] = f.type == 'ref' && f.ref != null
          ? (_resolveRef(e.key, f, f.ref!) ?? f)
          : f;
    }

    return BodySchema(
      core: body['core'] as String? ?? '',
      order: order,
      fields: fields,
      relations: [
        for (final e in (body['relations'] as List?) ?? const [])
          if (e is Map) e.cast<String, dynamic>(),
      ],
      absentWhen: (body['absent_when'] as Map?)?.cast<String, dynamic>(),
      exitCapableWhen:
          (body['exit_capable_when'] as Map?)?.cast<String, dynamic>(),
      buildTag: body['build_tag'] as String?,
      minCore: body['min_core'] as String?,
      onCoreUnsupported: CoreUnsupported.tryParse(body['on_core_unsupported']),
      levels: [
        for (final e in (body['levels'] as List?) ?? const []) '$e',
      ],
      fieldsUnchecked: body['fields_unchecked'] == true,
    );
  }



  FieldSchema? _resolveRef(String name, FieldSchema src, String ref) {
    final parts = ref.split('.');

    final section = parts.length >= 3 ? parts.take(2).join('.') : ref;
    if (section == 'transports') return _transportsAsObject(src);
    final sub = sharedSchema(section);
    if (sub == null) return null;
    if (ref.contains('.') && sub.fields.isNotEmpty) {
      final target = _resolveNamedRef(name, src, parts, sub);
      if (target == null) return null;
      return _mergeRefAttrs(src, target, section);
    }
    return _refAsObject(src, sub, section);
  }





  static FieldSchema? _resolveNamedRef(
      String name, FieldSchema src, List<String> parts, BodySchema sub) {
    if (parts.length >= 3) return sub.fields[parts.skip(2).join('.')];
    final own = sub.fields[name];
    if (own != null) return own;
    final desc = src.raw['desc_en'];
    if (desc is! String || desc.isEmpty) return null;
    FieldSchema? found;
    for (final k in sub.order) {
      final f = sub.fields[k];
      if (f == null || f.raw['desc_en'] != desc) continue;
      if (found != null) return null;
      found = f;
    }
    return found;
  }







  static FieldSchema _mergeRefAttrs(
      FieldSchema src, FieldSchema target, String section) {
    final raw = <String, dynamic>{...target.raw, 'origin_ref': section};
    final w = src.raw;
    if (w['required'] == true) raw['required'] = true;
    for (final k in const [
      'code',
      'forbidden_for',
      'allowed_for',
      'forbidden_codes',
      'desc_en',
      'desc_ru',
      'impl',
    ]) {
      final v = w[k];
      if (v == null || (v is String && v.isEmpty)) continue;
      if ((v is List && v.isEmpty) || (v is Map && v.isEmpty)) continue;
      raw[k] = v;
    }
    return FieldSchema(Map.unmodifiable(raw));
  }





  static FieldSchema _refAsObject(
      FieldSchema src, BodySchema sub, String section) {
    final raw = _wrapperAttrs(src, section);
    raw['order'] = List<String>.unmodifiable(sub.order);
    raw['fields'] = {
      for (final k in sub.order)
        if (sub.fields[k] != null) k: sub.fields[k]!.raw,
    };
    final aw = src.raw['absent_when'] ?? sub.absentWhen;
    if (aw != null) raw['absent_when'] = aw;
    return FieldSchema._expanded(
        Map.unmodifiable(raw), Map.unmodifiable(sub.fields), null);
  }




  FieldSchema? _transportsAsObject(FieldSchema src) {
    final body =
        (_shared['transports.json']?['body'] as Map?)?.cast<String, dynamic>();
    final disc = body?['discriminator'];
    final vs = body?['variants'];
    if (disc is! String || disc.isEmpty || vs is! Map) return null;
    final variants = <String, FieldSchema>{};
    for (final e in vs.entries) {
      final v = transportVariant(e.key as String);
      if (v == null) continue;
      variants[e.key as String] = FieldSchema._expanded(
        Map.unmodifiable(<String, dynamic>{
          'type': 'object',
          'order': v.order,
          'fields': {for (final f in v.fields.entries) f.key: f.value.raw},
        }),
        Map.unmodifiable(v.fields),
        null,
      );
    }
    final raw = _wrapperAttrs(src, 'transports');
    raw['discriminator'] = disc;
    raw['variants'] = {for (final e in variants.entries) e.key: e.value.raw};
    return FieldSchema._expanded(
        Map.unmodifiable(raw), null, Map.unmodifiable(variants));
  }

  static Map<String, dynamic> _wrapperAttrs(FieldSchema src, String section) =>
      <String, dynamic>{
        for (final e in src.raw.entries)
          if (e.key != 'type' && e.key != 'ref' && e.key != 'inline')
            e.key: e.value,
        'type': 'object',
        'origin_ref': section,
      };

  Map<String, FieldSchema> _fieldsOf(Map<String, dynamic> section) {
    final f = section['fields'];
    if (f is! Map) return const {};
    return {
      for (final e in f.entries)
        e.key as String: FieldSchema((e.value as Map).cast<String, dynamic>()),
    };
  }
}


final class _SchemaSlot {
  const _SchemaSlot(this.schema);

  final BodySchema? schema;
}




List<String> _stringList(Object? v) {
  if (v is! List) return const [];
  return [for (final e in v) if (e is String) e];
}
























int? awgMtuCeilingByRegistry(String type) {
  final ceiling =
      ContractRegistry.I.schemaFor(type)?.fields['mtu']?.maxWhen?['max'];
  return ceiling is num ? ceiling.toInt() : kAwgMtuFallback;
}



String? awgMtuClampCodeByRegistry(String type) => ContractRegistry.I
    .schemaFor(type)
    ?.fields['mtu']
    ?.maxWhen?['code'] as String?;









const kAwgMtuFallback = 1280;
