


















library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;

import '../../contract/registry.dart';
import 'document.dart';
import 'interpreter.dart' show detectMatchesJson;
import 'section.dart';



const kDraftRoot = 'assets/contract_draft';






final class MapperSections {
  MapperSections._();

  static final MapperSections I = MapperSections._();


  final Map<String, MapperSection?> _cache = {};





  final Map<String, List<String>> _typesCache = {};



  int _typesRegistryGen = -1;




  final Map<String, Map<String, dynamic>> _draft = {};

  bool _draftLoaded = false;


  String? _draftDir;













  Future<void> loadDrafts({String? dir, List<String> files = const []}) async {
    _draftDir = dir;
    _draft.clear();
    _cache.clear();
    _typesCache.clear();
    _documents = null;
    for (final name in files) {
      final rel = name.contains('/') ? name : 'uri/$name';
      var text = await _readDraft('$rel.json');
      var key = rel;
      if (text == null && !name.contains('/')) {


        text = await _readDraft('$name.json');
        key = name;
      }
      if (text == null) continue;
      _draft[key] = jsonDecode(text) as Map<String, dynamic>;


      _typesCache.clear();
    }
    _draftLoaded = true;
  }



  @visibleForTesting
  void resetForTesting() {
    _cache.clear();
    _typesCache.clear();
    _draft.clear();
    _documents = null;
    _draftLoaded = false;
    _draftDir = null;
  }












  void _loadDraftsFromDiskSync() {
    _draftLoaded = true;
    final dir = _draftDir ?? kDraftRoot;
    for (final sub in const ['uri', 'xray', 'singbox', 'conf', '']) {
      final root = Directory(sub.isEmpty ? dir : '$dir/$sub');
      if (!root.existsSync()) continue;
      for (final f in root.listSync().whereType<File>()) {
        if (!f.path.endsWith('.json')) continue;
        final name = f.uri.pathSegments.last.replaceAll('.json', '');
        final key = sub.isEmpty ? name : '$sub/$name';
        try {
          _draft[key] =
              jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        } catch (_) {

        }
      }
    }
    _typesCache.clear();
  }

  Future<String?> _readDraft(String rel) async {
    final dir = _draftDir;
    try {
      if (dir != null) return await File('$dir/$rel').readAsString();
      if (kIsWeb) return await rootBundle.loadString('$kDraftRoot/$rel');
      return await rootBundle.loadString('$kDraftRoot/$rel');
    } catch (_) {
      return null;
    }
  }



  MapperSection? sectionFor(String kind, String singboxType) {
    final key = '$kind/$singboxType';
    if (_cache.containsKey(key)) return _cache[key];
    final built = _build(kind, singboxType);
    _cache[key] = built;
    return built;
  }



  bool has(String kind, String singboxType) =>
      sectionFor(kind, singboxType) != null;












  DocumentRegistry? get documents {
    if (_documents != null) return _documents;
    if (!_draftLoaded) _loadDraftsFromDiskSync();
    final raw = ContractRegistry.I.rawShared('source_kinds.json') ??
        ContractRegistry.I.rawShared('sources.json') ??
        _draft['source_kinds'] ??
        _draft['uri/source_kinds'];
    if (raw == null) return null;
    return _documents = DocumentRegistry.fromJson(raw);
  }

  DocumentRegistry? _documents;










  List<String> typesFor(String kind) {
    if (!_draftLoaded) _loadDraftsFromDiskSync();
    final regGen = ContractRegistry.I.generation;
    if (regGen != _typesRegistryGen) {
      _typesCache.clear();
      _typesRegistryGen = regGen;
    }
    return _typesCache[kind] ??= List.unmodifiable(_typesForUncached(kind));
  }

  List<String> _typesForUncached(String kind) {
    final out = <String>{};
    final prefix = '$kind/';
    for (final key in _draft.keys) {
      if (!key.startsWith(prefix)) continue;
      final name = key.substring(prefix.length);

      if (_draft[key]?['mappers'] == null) continue;
      out.add(name);
    }
    for (final name in ContractRegistry.I.protocolNames) {
      final proto = ContractRegistry.I.rawProtocol(name);
      final mappers = (proto?['mappers'] as Map?)?.cast<String, dynamic>();
      final section = (mappers?[kind] as Map?)?.cast<String, dynamic>();
      if (section != null) out.add(name);
    }
    final list = out.toList()..sort();
    return list;
  }







  MapperSection? matchJson(String kind, Map<String, dynamic> element) {
    MapperSection? best;
    var bestPriority = 1 << 30;
    MapperSection? fallback;
    for (final type in typesFor(kind)) {
      final section = sectionFor(kind, type);
      if (section == null) continue;
      final d = section.detect;
      if (d == null) continue;
      if (d['default'] == true) {
        fallback ??= section;
        continue;
      }
      if (!detectMatchesJson(d, element)) continue;
      final pr = (d['priority'] as num?)?.toInt() ?? 0;
      if (pr < bestPriority) {
        best = section;
        bestPriority = pr;
      }
    }
    return best ?? fallback;
  }



  List<MapperSection> matchJsonAll(String kind, Map<String, dynamic> element) {
    final out = <MapperSection>[];
    for (final type in typesFor(kind)) {
      final section = sectionFor(kind, type);
      final d = section?.detect;
      if (section == null || d == null || d['default'] == true) continue;
      if (detectMatchesJson(d, element)) out.add(section);
    }
    return out;
  }

  MapperSection? _build(String kind, String singboxType) {



    if (!_draftLoaded) _loadDraftsFromDiskSync();
    final raw = _rawSection(kind, singboxType);
    if (raw == null) return null;
    final section = MapperSection.fromJson(
        kind, singboxType, _withIniDialect(singboxType, _sectionRefs(raw)));
    return section.include.isEmpty ? section : _withIncludes(section);
  }







  Map<String, dynamic> _withIniDialect(
      String singboxType, Map<String, dynamic> raw) {
    if (raw[DraftNames.iniDialect] != null) return raw;
    final forms = raw['forms'];
    if (forms is! List ||
        !forms.any((f) => f is Map && f['space'] == 'ini')) {
      return raw;
    }
    final mappers = (ContractRegistry.I.rawProtocol(singboxType)?['mappers']
            as Map?)
        ?.cast<String, dynamic>();
    if (mappers == null) return raw;
    for (final m in mappers.values) {
      final d = m is Map ? m[DraftNames.iniDialect] : null;
      if (d is Map) return {...raw, DraftNames.iniDialect: d};
    }
    return raw;
  }














  Map<String, dynamic> _sectionRefs(Map<String, dynamic> raw) {
    final rawParams = (raw['params'] as Map?)?.cast<String, dynamic>();
    if (rawParams == null) return raw;
    Map<String, dynamic>? patched;
    for (final e in rawParams.entries) {
      final v = e.value;
      if (v is! Map) continue;
      final m = v.cast<String, dynamic>();
      final vm = m['value_map'];
      if (vm is! Map) continue;
      final ref = vm[r'$ref'];
      if (ref is! String) continue;


      final parts = ref.split('.');
      if (parts.length < 2) continue;


      Map<String, dynamic>? target =
          (_draftShared(parts.first)?['blocks'] as Map?)?[parts.last]
              as Map<String, dynamic>?;
      target ??= (_registryShared(parts.first)?['blocks'] as Map?)?[parts.last]
          as Map<String, dynamic>?;
      if (target == null) continue;
      (patched ??= {...rawParams})[e.key] = {
        ...m,
        'value_map': target.cast<String, dynamic>(),
      };
    }
    return patched == null ? raw : {...raw, 'params': patched};
  }





  Map<String, dynamic>? _rawSection(String kind, String singboxType) {
    if (!_draftLoaded) _loadDraftsFromDiskSync();


    final file = _draft['$kind/$singboxType'] ??
        (kind == 'uri' ? _draft[singboxType] : null);
    final draft =
        ((file?['mappers'] as Map?)?[kind] as Map?)?.cast<String, dynamic>();

    final fromRegistry = _registrySection(kind, singboxType);

    if (fromRegistry == null) return draft;

    if (draft == null || file?['_overlay'] != true) return fromRegistry;

    return _mergeOverlay(fromRegistry, draft);
  }

  Map<String, dynamic>? _registrySection(String kind, String singboxType) {
    final proto = ContractRegistry.I.rawProtocol(singboxType);
    if (proto == null) return null;
    final mappers = (proto['mappers'] as Map?)?.cast<String, dynamic>();






    final section = (mappers?[kind] as Map?)?.cast<String, dynamic>();
    if (section != null) return section;




    final legacy = (proto[kind] as Map?)?.cast<String, dynamic>();
    if (legacy != null && _isExecutable(legacy)) return legacy;
    return null;
  }


  static bool _isExecutable(Map<String, dynamic> section) {
    final params = (section['params'] as Map?)?.cast<String, dynamic>();
    if (params == null) return false;
    for (final v in params.values) {
      if (v is Map && v.containsKey('source')) return true;
    }
    return false;
  }












































  MapperSection _withIncludes(MapperSection section) {
    final merged = <String, MapperParam>{};
    final own = <String>{
      for (final p in section.params.values)
        if (p.when.isEmpty) ..._overrideKeys(p),
    };
    for (final ref in section.include) {
      for (final e in _blockParams(ref).entries) {
        if (_overrideKeys(e.value).any(own.contains)) continue;
        merged[e.key] = e.value;
      }
    }
    for (final e in section.params.entries) {
      merged[e.key] = e.value;
    }
    return section.withParams(merged);
  }














  static Iterable<String> _overrideKeys(MapperParam p) sync* {



    const sep = '\u0000';
    final all = <String>{
      ...p.source,
      for (final l in p.sourceByForm.values) ...l,
    };
    if (all.isEmpty) {
      yield '${p.name}$sep';
      return;
    }
    for (final src in all) {


      final bare = src.startsWith('json.')
          ? src.substring('json.'.length)
          : src.startsWith('query.')
              ? src.substring('query.'.length)
              : src;
      yield '${p.name}$sep$bare';
    }
  }













  Map<String, MapperParam> _blockParams(String ref) {
    final hash = ref.indexOf('#');
    final fileName = hash < 0 ? ref : ref.substring(0, hash);
    final dialect = hash < 0 ? 'uri' : ref.substring(hash + 1);









    final draft = _draftShared(fileName);
    final overlay = draft != null && draft['_overlay'] == true ? draft : null;
    final file = (overlay == null ? draft : null) ?? _registryShared(fileName);
    if (file == null) return const {};
    final blocks = (file['blocks'] as Map?)?.cast<String, dynamic>();
    var byDialect = (blocks?[dialect] as Map?)?.cast<String, dynamic>();
    if (byDialect == null) return const {};

    if (overlay != null) {
      final ov = ((overlay['blocks'] as Map?)?[dialect] as Map?)
          ?.cast<String, dynamic>();
      if (ov != null) byDialect = _mergeOverlay(byDialect, ov);
    }

    final out = <String, MapperParam>{};
    for (final e in byDialect.entries) {
      final v = e.value;






      if (v == null) {
        out['$fileName.${e.key}'] =
            MapperParam.fromJson(e.key, const {'source': <String>[]});
        continue;
      }

      if (v is! Map) continue;
      final m = v.cast<String, dynamic>();
      if (m.containsKey('source')) {






        out['$fileName.${e.key}'] = MapperParam.fromJson(
            e.key, _withAliases(e.key, _withRefs(m, blocks!), fileName));
        continue;
      }

      for (final g in m.entries) {
        final gv = g.value;
        if (gv is! Map) continue;
        final gm = gv.cast<String, dynamic>();
        if (!gm.containsKey('source')) continue;
        out['$fileName.${e.key}.${g.key}'] = MapperParam.fromJson(
            g.key, _withAliases(g.key, _withRefs(gm, blocks!), fileName));
      }
    }
    return out;
  }








  Map<String, dynamic> _withAliases(
    String name,
    Map<String, dynamic> param,
    String fileName,
  ) {
    if (param.containsKey('aliases')) return param;


    for (final file in [
      _draftShared(fileName),
      ContractRegistry.I.rawShared('$fileName.json'),
    ]) {
      if (file == null) continue;
      for (final top in file.values) {
        if (top is! Map) continue;
        final params = (top['params'] as Map?)?.cast<String, dynamic>();
        final decl = (params?[name] as Map?)?.cast<String, dynamic>();
        final aliases = decl?['aliases'];
        if (aliases is List && aliases.isNotEmpty) {
          return {...param, 'aliases': aliases};
        }
      }
    }
    return param;
  }













  static Map<String, dynamic> _mergeOverlay(
    Map<String, dynamic> base,
    Map<String, dynamic> overlay,
  ) {
    final out = {...base};
    for (final e in overlay.entries) {
      final ov = e.value;
      final b = out[e.key];


      final isEntry = (ov is Map && ov.containsKey('source')) ||
          (b is Map && b.containsKey('source'));
      if (ov is Map && b is Map && !isEntry) {
        out[e.key] = {...b.cast<String, dynamic>(), ...ov.cast<String, dynamic>()};
      } else {
        out[e.key] = ov;
      }
    }
    return out;
  }


  @visibleForTesting
  static Map<String, dynamic> mergeOverlayForTest(
    Map<String, dynamic> base,
    Map<String, dynamic> overlay,
  ) =>
      _mergeOverlay(base, overlay);






  static Map<String, dynamic> _withRefs(
    Map<String, dynamic> param,
    Map<String, dynamic> blocks,
  ) {
    final vm = param['value_map'];
    if (vm is! Map) return param;
    final ref = vm[r'$ref'];
    if (ref is! String) return param;
    final target = blocks[ref.split('.').last];
    if (target is! Map) return param;
    return {...param, 'value_map': target.cast<String, dynamic>()};
  }



  Map<String, dynamic>? _draftShared(String fileName) {
    if (!_draftLoaded) _loadDraftsFromDiskSync();
    for (final key in ['uri/$fileName', fileName, 'xray/$fileName']) {
      final f = _draft[key];
      if (f != null && f['blocks'] is Map) return f;
    }
    return null;
  }



  Map<String, dynamic>? _registryShared(String fileName) =>
      ContractRegistry.I.rawShared('$fileName.json');

}
