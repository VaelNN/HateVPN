























library;

import 'dart:convert';

import 'interpreter.dart' show detectMatchesJson, formMatchesText;


final class DocumentSource {
  const DocumentSource({
    required this.kind,
    this.priority = 0,
    this.detect,
    this.unwrap,
    this.redetect = false,
    this.requiresAfterUnwrap,
    this.mapper,
    this.elements,
    this.lineCommentPrefixes = const ['#', '//', ';'],
    this.serviceSchemes,
    this.bannerTargets,
  });

  factory DocumentSource.fromJson(Map<String, dynamic> j) => DocumentSource(




        kind: (j['source_kind'] ?? j['kind']) as String? ?? '',
        priority: (j['priority'] as num?)?.toInt() ?? 0,
        detect: (j['detect'] as Map?)?.cast<String, dynamic>(),
        unwrap: j['unwrap'] as String?,
        redetect: j['redetect'] as bool? ?? false,
        requiresAfterUnwrap:
            (j['requires_after_unwrap'] as Map?)?.cast<String, dynamic>(),
        mapper: j['mapper'] as String?,
        elements: j['elements'] as String?,
        lineCommentPrefixes:
            ((j['line_comment_prefixes'] as List?) ?? const ['#', '//', ';'])
                .cast<String>(),
        serviceSchemes: (j['service_schemes'] as Map?)?.cast<String, dynamic>(),
        bannerTargets: (j['banner_targets'] as Map?)?.cast<String, dynamic>(),
      );


  final String kind;
  final int priority;
  final Map<String, dynamic>? detect;




  final String? unwrap;


  final bool redetect;



  final Map<String, dynamic>? requiresAfterUnwrap;



  final String? mapper;



  final String? elements;

  final List<String> lineCommentPrefixes;








  final Map<String, dynamic>? serviceSchemes;








  String? serviceSchemeCode(String line) {
    final cfg = serviceSchemes;
    if (cfg == null) return null;
    final schemes = (cfg['schemes'] as List?)?.whereType<String>();
    if (schemes == null || schemes.isEmpty) return null;
    final t = line.trim();
    final sep = t.indexOf('://');
    if (sep <= 0) return null;
    final scheme = t.substring(0, sep).toLowerCase();
    if (!schemes.any((s) => s.toLowerCase() == scheme)) return null;
    final prefix = cfg['path_prefix_fold'] as String?;
    if (prefix != null && prefix.isNotEmpty) {
      final rest = t.substring(sep + 3).toLowerCase();
      if (!rest.startsWith(prefix.toLowerCase())) return null;
    }
    return cfg['code'] as String?;
  }












  final Map<String, dynamic>? bannerTargets;








  bool isBannerTarget(String host) {
    final hosts = (bannerTargets?['hosts'] as List?)?.whereType<String>();
    if (hosts == null || hosts.isEmpty) return false;
    var h = host.trim();
    if (h.startsWith('[') && h.endsWith(']')) {
      h = h.substring(1, h.length - 1);
    }
    if (h.isEmpty) return false;
    return hosts.any((t) => t.toLowerCase() == h.toLowerCase());
  }


  String? get bannerCode => bannerTargets?['code'] as String?;

  bool get isDefault => detect?['default'] == true;
}



final class DocumentMatch {
  const DocumentMatch({
    required this.source,
    required this.text,
    this.json,
    this.unwrapDepth = 0,
  });

  final DocumentSource source;


  final String text;



  final Object? json;

  final int unwrapDepth;
}


typedef Unwrapper = String? Function(String text);


final class DocumentRegistry {
  DocumentRegistry(this.sources, {this.maxUnwrapDepth = 2});

  factory DocumentRegistry.fromJson(Map<String, dynamic> j) {





    final envelope =
        (j['source_kinds'] as Map?)?.cast<String, dynamic>() ?? j;
    final list = ((envelope['kinds'] ?? envelope['sources']) as List? ??
            const [])
        .whereType<Map>()
        .map((e) => DocumentSource.fromJson(e.cast<String, dynamic>()))
        .toList();


    final ordered = List<DocumentSource>.from(list)
      ..sort((a, b) => a.priority.compareTo(b.priority));
    return DocumentRegistry(
      ordered,
      maxUnwrapDepth:
          ((envelope['max_unwrap_depth'] ?? j['max_unwrap_depth']) as num?)
                  ?.toInt() ??
              2,
    );
  }

  final List<DocumentSource> sources;
  final int maxUnwrapDepth;



  DocumentSource? sourceByKind(String kind) {
    for (final s in sources) {
      if (s.kind == kind) return s;
    }
    return null;
  }


  DocumentSource? get defaultSource {
    for (final s in sources) {
      if (s.isDefault) return s;
    }
    return null;
  }



  List<DocumentSource> matchAll(String rawText, {Object? parsedJson}) {





    final text = _stripBom(rawText).trim();
    final out = <DocumentSource>[];
    Object? json = parsedJson;
    var parsed = parsedJson != null;
    for (final s in sources) {
      if (s.isDefault) continue;
      final d = s.detect;
      if (d == null) continue;
      if (_needsJson(d)) {
        if (!parsed) {
          json = _tryJson(text);
          parsed = true;
        }
        if (json == null) continue;
        if (!detectMatchesJson(d, json)) continue;
      } else if (!formMatchesText(d, text)) {
        continue;
      }
      out.add(s);
    }
    return out;
  }






  DocumentMatch? detect(
    String text, {
    required Map<String, Unwrapper> unwrappers,
    int depth = 0,
  }) {





    text = _stripBom(text);
    final trimmed = text.trimRight();
    if (trimmed.trim().isEmpty) return null;

    final probe = trimmed.trim();
    Object? json;
    var parsed = false;

    for (final s in sources) {
      if (s.isDefault) continue;
      final d = s.detect;
      if (d == null) continue;

      if (_needsJson(d)) {
        if (!parsed) {
          json = _tryJson(probe);
          parsed = true;
        }
        if (json == null) continue;
        if (!detectMatchesJson(d, json)) continue;
        return DocumentMatch(
            source: s, text: trimmed, json: json, unwrapDepth: depth);
      }

      if (!formMatchesText(d, probe)) continue;

      final name = s.unwrap;
      if (name == null) {
        return DocumentMatch(source: s, text: trimmed, unwrapDepth: depth);
      }




      if (depth >= maxUnwrapDepth && maxUnwrapDepth > 0) {
        return DocumentMatch(source: s, text: trimmed, unwrapDepth: depth);
      }



      final unwrapper = unwrappers[name];
      if (unwrapper == null) continue;
      final inner = unwrapper(trimmed)?.trim();
      if (inner == null || inner.isEmpty) continue;
      if (!formMatchesText(s.requiresAfterUnwrap, inner)) {




        if (s.redetect && formMatchesText(d, inner)) {
          final again =
              detect(inner, unwrappers: unwrappers, depth: depth + 1);
          if (again != null) return again;
        }
        continue;
      }

      if (!s.redetect) {
        return DocumentMatch(source: s, text: inner, unwrapDepth: depth + 1);
      }
      final again =
          detect(inner, unwrappers: unwrappers, depth: depth + 1);
      if (again != null) return again;
      return DocumentMatch(source: s, text: inner, unwrapDepth: depth + 1);
    }

    final fallback = defaultSource;
    if (fallback == null) return null;
    return DocumentMatch(source: fallback, text: trimmed, unwrapDepth: depth);
  }























  static List<Map<String, dynamic>>? groupsFor(String spec, Object? value) {
    if (spec.startsWith('[].')) {
      if (value is! List) return null;
      return value
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    if (spec == r'$self') {
      if (value is! Map) return null;
      return [
        {
          _kOutbounds: [value.cast<String, dynamic>()],
        },
      ];
    }
    if (spec == '[]') {
      if (value is! List) return null;
      return [
        {_kOutbounds: value},
      ];
    }
    if (value is! Map) return null;
    return [value.cast<String, dynamic>()];
  }




  static const _kOutbounds = 'outbounds';








  static bool _needsJson(Map<String, dynamic> d) {
    if (d.containsKey('json')) return true;
    for (final key in const ['any', 'all']) {
      final sub = d[key];
      if (sub is! List) continue;
      for (final s in sub) {
        if (s is Map && _needsJson(s.cast<String, dynamic>())) return true;
      }
    }
    final not = d['not'];
    if (not is Map && _needsJson(not.cast<String, dynamic>())) return true;
    return false;
  }

  static Object? _tryJson(String text) {
    final t = _stripBom(text).trimLeft();
    if (!t.startsWith('{') && !t.startsWith('[')) return null;
    try {
      return jsonDecode(t);
    } catch (_) {
      return null;
    }
  }
}


String _stripBom(String s) {
  const bom = '\uFEFF';
  return s.startsWith(bom) ? s.substring(bom.length) : s;
}
