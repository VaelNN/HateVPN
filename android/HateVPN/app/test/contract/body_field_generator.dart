


























library;

import 'package:lxbox/services/contract/registry.dart';














const _kPatternSamples = <String, String>{
  'encryption': 'mlkem768x25519plus.native.0rtt.'
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
};

final class UnsupportedExpression implements Exception {
  UnsupportedExpression(this.kind, this.name, this.path);


  final String kind;
  final String name;


  final String path;

  @override
  String toString() =>
      'реестр: незнакомое выражение $kind=$name (поле $path). '
      'Генератор §476 обязан уметь строить значение для каждого выражения '
      'схемы — допишите ветку в body_field_generator.dart';
}


final class BodyVariant {
  BodyVariant({
    required this.scheme,
    required this.name,
    required this.body,
    required this.covered,
  });


  final String scheme;


  final String name;


  final Map<String, dynamic> body;


  final Set<String> covered;
}














List<BodyVariant> generateBodies(String scheme) {
  final schema = ContractRegistry.I.schemaFor(scheme);
  if (schema == null) return const [];
  final gen = _Generator(scheme);
  return gen.run(schema);
}





Set<String> allFieldPaths(String scheme) {
  final schema = ContractRegistry.I.schemaFor(scheme);
  if (schema == null) return const {};
  final out = <String>{};
  _collectPaths(schema.order, schema.fields, '', out);
  return out;
}

void _collectPaths(
  List<String> order,
  Map<String, FieldSchema> fields,
  String prefix,
  Set<String> out,
) {
  for (final key in order) {
    final f = fields[key];
    if (f == null) continue;

    if (f.raw['skip'] != null) continue;
    final path = prefix.isEmpty ? key : '$prefix.$key';
    out.add(path);

    final variants = f.variants;
    if (variants != null) {
      for (final t in _kTransportTypes) {
        final v = variants[t];
        final vf = v?.fields;
        if (vf == null) continue;
        _collectPaths(v!.order ?? vf.keys.toList(), vf, '$path.$t', out);
      }
      continue;
    }
    final sub = f.fields;
    if (sub != null) {
      _collectPaths(f.order ?? sub.keys.toList(), sub, path, out);
    }
  }
}







bool forbiddenByRegistry(String scheme, String path) {
  final schema = ContractRegistry.I.schemaFor(scheme);
  if (schema == null) return false;
  Map<String, FieldSchema>? fields = schema.fields;
  Map<String, FieldSchema>? variants;
  for (final seg in path.split('.')) {

    if (variants != null) {
      fields = variants[seg]?.fields;
      variants = null;
      continue;
    }
    final f = fields?[seg];
    if (f == null) return false;
    final forbidden = f.forbiddenFor;
    if (forbidden != null && forbidden.contains(scheme)) return true;
    final allowed = f.allowedFor;
    if (allowed != null && !allowed.contains(scheme)) return true;
    variants = f.variants;
    fields = f.fields;
  }
  return false;
}




const _kTransportTypes = <String>['ws', 'grpc', 'http', 'httpupgrade', 'xhttp', 'quic'];




const _kAwgHeaderBands = <String, String>{
  'h1': '10-20',
  'h2': '30-40',
  'h3': '50-60',
  'h4': '70-80',
};

final class _Generator {
  _Generator(this.scheme);

  final String scheme;

  List<BodyVariant> run(BodySchema schema) {
    final out = <BodyVariant>[];


    out.add(_build(schema, name: 'base', transport: 'ws', tlsMode: _TlsMode.reality));


    for (final t in _kTransportTypes.skip(1)) {
      if (ContractRegistry.I.transportVariant(t) == null) continue;
      out.add(_build(schema, name: 'transport=$t', transport: t, tlsMode: _TlsMode.reality));
    }


    out.add(_build(schema, name: 'tls=ech', transport: 'ws', tlsMode: _TlsMode.ech));



    out.add(_build(schema, name: 'no-transport', transport: null, tlsMode: _TlsMode.reality));



    final alt = _equalsAlternatives(schema);
    for (final a in alt) {
      out.add(_build(schema,
          name: 'equals:${a.key}=${a.value}',
          transport: 'ws',
          tlsMode: _TlsMode.reality,
          equalsOverride: a));
    }



    for (final excl in _kTlsExclusive) {
      out.add(_build(schema,
          name: 'tls-exclusive=$excl',
          transport: 'ws',





          tlsMode: _kTlsExclusiveNeedsNoReality.contains(excl)
              ? _TlsMode.none
              : _TlsMode.reality,
          tlsExclusive: excl));
    }




    for (final key in _rootConflictLosers(schema)) {
      out.add(_build(schema,
          name: 'root-exclusive=$key',
          transport: 'ws',
          tlsMode: _TlsMode.reality,
          rootExclusive: key));
    }




    for (final loser in _nestedConflictLosers(schema)) {
      out.add(_build(schema,
          name: 'nested-exclusive=$loser',
          transport: _transportOfPath(loser) ?? 'ws',
          tlsMode: _TlsMode.reality,
          nestedExclusive: loser));
    }
    return out;
  }


  String? _transportOfPath(String path) {
    final parts = path.split('.');
    if (parts.length < 2 || parts.first != 'transport') return null;
    return _kTransportTypes.contains(parts[1]) ? parts[1] : null;
  }


  List<String> _nestedConflictLosers(BodySchema schema) {
    final out = <String>[];
    void walk(List<String> order, Map<String, FieldSchema> fields, String prefix) {
      for (final key in order) {
        final f = fields[key];
        if (f == null) continue;
        final path = prefix.isEmpty ? key : '$prefix.$key';
        if (prefix.isNotEmpty && f.conflicts.isNotEmpty) {
          final rivals = [
            for (final r in f.conflicts)
              if (r['with'] is String && _rivalExists(r['with'] as String, prefix))
                r['with'] as String,
          ];

          if (rivals.any((r) => r.split('.').last != key)) out.add(path);
        }
        final sub = f.fields;
        if (sub != null) walk(f.order ?? sub.keys.toList(), sub, path);
      }
    }

    for (final t in _kTransportTypes) {
      final v = ContractRegistry.I.transportVariant(t);
      if (v == null) continue;
      walk(v.order, v.fields, 'transport.$t');
    }
    return out;
  }






  List<String> _rootConflictLosers(BodySchema schema) {
    final out = <String>[];
    for (final key in schema.order) {
      final f = schema.fields[key];
      if (f == null || f.conflicts.isEmpty) continue;
      if (f.raw['skip'] != null) continue;

      final rivals = <String>[
        for (final r in f.conflicts)
          if (r['with'] is String) r['with'] as String,
      ].where((p) => p != 'transport' && !p.startsWith('tls.')).toList();
      if (rivals.isEmpty) continue;

      if (rivals.every((r) => _kBuildManaged.contains(r))) continue;
      out.add(key);
    }
    return out;
  }




  List<MapEntry<String, Object?>> _equalsAlternatives(BodySchema schema) {
    final out = <MapEntry<String, Object?>>[];
    final seen = <String>{};
    void walk(List<String> order, Map<String, FieldSchema> fields, String prefix) {
      for (final key in order) {
        final f = fields[key];
        if (f == null) continue;
        final path = prefix.isEmpty ? key : '$prefix.$key';
        for (final r in f.requires) {
          if (!r.containsKey('equals')) continue;
          final target = r['path'] as String?;
          if (target == null) continue;
          final v = r['equals'];
          final id = '$target=$v';
          if (seen.add(id)) out.add(MapEntry(target, v));
        }
        final sub = f.fields;
        if (sub != null) walk(f.order ?? sub.keys.toList(), sub, path);
      }
    }

    walk(schema.order, schema.fields, '');
    return out;
  }

  BodyVariant _build(
    BodySchema schema, {
    required String name,
    required String? transport,
    required _TlsMode tlsMode,
    MapEntry<String, Object?>? equalsOverride,
    String? tlsExclusive,
    String? rootExclusive,
    String? nestedExclusive,
  }) {
    final ctx = _BuildCtx(
      transport: transport,
      tlsMode: tlsMode,
      equalsOverride: equalsOverride,
      tlsExclusive: tlsExclusive,
      rootExclusive: rootExclusive,
      nestedExclusive: nestedExclusive,
    );
    final body = _object(schema.order, schema.fields, '', ctx);
    body['type'] = scheme;
    return BodyVariant(
      scheme: scheme,
      name: name,
      body: body,
      covered: ctx.covered,
    );
  }

  Map<String, dynamic> _object(
    List<String> order,
    Map<String, FieldSchema> fields,
    String prefix,
    _BuildCtx ctx,
  ) {
    final out = <String, dynamic>{};


    for (final key in order) {
      final f = fields[key];
      if (f == null) continue;
      final path = prefix.isEmpty ? key : '$prefix.$key';
      if (_skip(f, path, ctx)) continue;
      final v = _value(f, path, ctx);
      if (v == _kOmit) continue;
      out[key] = v;
      ctx.covered.add(path);
    }
    return out;
  }




  bool _skip(FieldSchema f, String path, _BuildCtx ctx) {



    if (f.raw['skip'] != null) return true;
    final forbidden = f.forbiddenFor;
    if (forbidden != null && forbidden.contains(scheme)) return true;
    final allowed = f.allowedFor;
    if (allowed != null && !allowed.contains(scheme)) return true;


    if (_kBuildManaged.contains(path)) return true;


    if (path == 'tls.reality' && ctx.tlsMode != _TlsMode.reality) return true;
    if (path == 'tls.ech' && ctx.tlsMode != _TlsMode.ech) return true;





    if (_kTlsExclusive.contains(path) && path != ctx.tlsExclusive) return true;


    if (ctx.rootExclusive != null && ctx.rivalsOfRootExclusive.contains(path)) {
      return true;
    }


    final nested = ctx.nestedExclusive;
    if (nested != null && path != nested) {
      final parent = nested.substring(0, nested.lastIndexOf('.'));
      if (path.startsWith('$parent.') &&
          !path.substring(parent.length + 1).contains('.')) {


        for (final rel in f.conflicts) {
          if (rel['with'] is String) return true;
        }


        if (ctx.rivalsOfNested.contains(path.split('.').last)) return true;
      }
    }


    if (path == 'transport' && ctx.transport == null) return true;






    final chosen = path == ctx.tlsExclusive ||
        path == ctx.rootExclusive ||
        path == ctx.nestedExclusive;
    if (!chosen) {
      for (final rel in f.conflicts) {
        final with0 = rel['with'] as String?;
        if (with0 == null) continue;


        if (!_relationWhenHolds(rel['when'], f, path, ctx)) continue;
        if (_willBePresent(with0, ctx)) return true;
      }
    }


    for (final rel in f.requires) {
      if (!rel.containsKey('equals')) continue;
      final target = rel['path'] as String?;
      if (target == null) continue;




      if (!_relationWhenHolds(rel['when'], f, path, ctx)) continue;
      if (ctx.equalsValueFor(target) != rel['equals']) return true;
    }
    return false;
  }






  bool _relationWhenHolds(
      Object? when, FieldSchema f, String path, _BuildCtx ctx) {
    if (when is! Map) return true;
    final own = path.split('.').last;
    for (final e in when.entries) {
      final key = '${e.key}';
      if (key == 'any_set' || key == 'source_kind') continue;
      final Object? got = key.split('.').last == own
          ? (ctx.equalsForcedValue(path) ??
              (f.values == null ? null : _firstUsable(f.values!)))
          : ctx.equalsValueFor(key);
      final present = got != null && !(got is String && got.isEmpty);
      final want = e.value;
      bool holds;
      if (want is Map && want['in'] is List) {
        holds = present && (want['in'] as List).any((v) => '$v' == '$got');
      } else if (want is Map && want['not_in'] is List) {
        holds =
            !present || !(want['not_in'] as List).any((v) => '$v' == '$got');
      } else {
        holds = present && '$want' == '$got';
      }
      if (!holds) return false;
    }
    return true;
  }












  bool _rivalExists(String with0, String prefix) {
    if (with0.contains('.') || prefix.isEmpty) return true;
    final root = ContractRegistry.I.schemaFor(scheme)?.fields;
    Map<String, FieldSchema>? cur = root;
    for (final seg in prefix.split('.')) {
      cur = cur?[seg]?.fields;
    }
    if (cur != null && cur.containsKey(with0)) return true;
    return root?.containsKey(with0) ?? false;
  }

  bool _willBePresent(String path, _BuildCtx ctx) {
    if (!path.contains('.') &&
        !_kBuildManaged.contains(path) &&
        path != 'transport' &&
        !(ContractRegistry.I.schemaFor(scheme)?.fields.containsKey(path) ??
            true)) {
      return false;
    }


    if (_kBuildManaged.contains(path)) return false;
    if (path == 'transport') return ctx.transport != null;
    if (path == 'tls.reality' || path.startsWith('tls.reality.')) {
      return ctx.tlsMode == _TlsMode.reality;
    }
    if (path == 'tls.ech' || path.startsWith('tls.ech.')) {
      return ctx.tlsMode == _TlsMode.ech;
    }




    if (_kTlsExclusive.contains(path)) return ctx.tlsExclusive == path;

    if (ctx.rootExclusive != null && !path.contains('.')) {
      return !ctx.rivalsOfRootExclusive.contains(path);
    }
    return true;
  }

  Object? _value(FieldSchema f, String path, _BuildCtx ctx) {
    switch (f.type) {
      case 'object':

        final variants = f.variants;
        if (variants != null) {
          final t = ctx.transport;
          if (t == null) return _kOmit;
          final v = variants[t];
          final vf = v?.fields;
          if (vf == null) return _kOmit;
          final inner = _object(v!.order ?? vf.keys.toList(), vf, '$path.$t', ctx);
          return <String, dynamic>{f.discriminator ?? 'type': t, ...inner};
        }
        final sub = f.fields;


        if (sub == null) return <String, dynamic>{'X-Sample': 'lxbox'};
        return _object(f.order ?? sub.keys.toList(), sub, path, ctx);
      case 'array':
        final items = f.items;
        if (items == null) return <Object?>['sample'];
        final n = f.len ?? 1;
        return <Object?>[
          for (var i = 0; i < n; i++) _value(items, '$path[$i]', ctx),
        ];
      default:
        return _scalar(f, path, ctx);
    }
  }

  Object? _scalar(FieldSchema f, String path, _BuildCtx ctx) {


    final forced = ctx.equalsForcedValue(path);
    if (forced != null) return forced;







    final values = f.values;
    final pick = values == null ? null : _firstUsable(values);
    if (pick != null && !_kListTypes.contains(f.type)) return pick;





    final format = f.format;

    switch (f.type) {
      case 'string':
        return format != null ? _byFormat(format, f, path) : _string(f, path);
      case 'listable_string':
      case 'string_array':

        final one = pick ??
            (format != null ? _byFormat(format, f, path) : _string(f, path));
        return <Object?>[one];
      case 'int_array':
        final n = f.len ?? 3;
        return <int>[for (var i = 0; i < n; i++) i];
      case 'bool':
        return true;
      case 'int':
      case 'uint16':
        return format != null ? _byFormat(format, f, path) : _int(f, path);
      case 'duration':
        return '30s';
      case 'awg_range':





        final band = _kAwgHeaderBands[path.split('.').last];
        return band ?? '10-20';
      case 'enum':


        throw UnsupportedExpression('enum-without-values', f.type, path);
      default:
        throw UnsupportedExpression('type', f.type, path);
    }
  }



  Object? _firstUsable(List<Object?> values) {
    for (final v in values) {
      if (v == null) continue;
      if (v is String && v.isEmpty) continue;
      return v;
    }
    return null;
  }

  Object _byFormat(String format, FieldSchema f, String path) {
    switch (format) {
      case 'port':
        return 443;
      case 'uuid':
        return 'b831381d-6324-4d53-ad4f-8cda48b30811';
      case 'hex':

        final len = f.len ?? (f.lenParity == 'even' ? 8 : 8);
        return List.filled(len, 'a').join();
      case 'base64':
        return 'c2FtcGxl';
      case 'base64_32':

        return 'AwoRGB8mLTQ7QklQV15lbHN6gYiPlp2kq7K5wMfO1dw';
      case 'host':
        return 'example.com';
      case 'ipv4':
        return '10.0.0.2';
      case 'cidr':
        return '10.0.0.2/32';
      case 'url_path':
        return '/sample';
      default:
        throw UnsupportedExpression('format', format, path);
    }
  }

  Object _string(FieldSchema f, String path) {
    final norm = f.normalize;











    final pattern = f.pattern;
    if (pattern != null) {
      final sample = _kPatternSamples[path];
      if (sample == null) throw UnsupportedExpression('pattern', pattern, path);


      if (!RegExp(pattern).hasMatch(sample)) {
        throw UnsupportedExpression(
            'pattern-sample-mismatch', pattern, path);
      }
      return sample;
    }




    const base = 'sample';
    final len = f.len;
    if (norm == 'hex_only') {
      return List.filled(len ?? 8, 'a').join();
    }
    if (norm != null && !const {'trim', 'lower', 'trim_lower'}.contains(norm)) {
      throw UnsupportedExpression('normalize', norm, path);
    }
    if (len != null) return List.filled(len, 'a').join();
    final min = f.min;
    final max = f.max;
    var s = base;
    if (min != null && s.length < min) s = s.padRight(min.toInt(), 'x');
    if (max != null && s.length > max) s = s.substring(0, max.toInt());
    return s;
  }

  int _int(FieldSchema f, [String path = '']) {




    if (const {'s1', 's2', 's3', 's4'}.contains(path)) return 16;
    final min = f.min?.toInt();
    final max = f.max?.toInt();


    final ceiling = f.maxWhen?['max'];
    var v = 8;
    if (min != null && v < min) v = min;
    if (max != null && v > max) v = max;
    if (ceiling is num && v > ceiling) v = ceiling.toInt();
    return v;
  }
}


const _kBuildManaged = {'tag', 'detour', 'domain_resolver'};




const _kTlsExclusive = <String>[
  'tls.disable_sni',
  'tls.spoof',
  'tls.certificate_public_key_sha256',
];


const _kTlsExclusiveNeedsNoReality = {'tls.disable_sni', 'tls.spoof'};


const _kListTypes = {'listable_string', 'string_array'};


const Object _kOmit = Object();



enum _TlsMode { reality, ech, none }

final class _BuildCtx {
  _BuildCtx({
    required this.transport,
    required this.tlsMode,
    required this.equalsOverride,
    this.tlsExclusive,
    this.rootExclusive,
    this.nestedExclusive,
  });

  final String? transport;
  final _TlsMode tlsMode;


  final String? tlsExclusive;


  final String? rootExclusive;


  final String? nestedExclusive;


  late final Set<String> rivalsOfNested = _nestedRivals();

  Set<String> _nestedRivals() {
    final path = nestedExclusive;
    if (path == null) return const {};
    final t = path.split('.');
    if (t.length < 2) return const {};
    final variant = ContractRegistry.I.transportVariant(t[1]);
    if (variant == null) return const {};
    Map<String, FieldSchema>? fields = variant.fields;
    FieldSchema? f;
    for (final seg in t.skip(2)) {
      f = fields?[seg];
      fields = f?.fields;
    }
    return {
      for (final r in f?.conflicts ?? const <Map<String, dynamic>>[])
        if (r['with'] is String) (r['with'] as String).split('.').last,
    };
  }


  late final Set<String> rivalsOfRootExclusive = _rivals();

  Set<String> _rivals() {
    final key = rootExclusive;
    if (key == null) return const {};
    final out = <String>{};
    for (final scheme in _searchSchemes) {
      final s = ContractRegistry.I.schemaFor(scheme);
      final f = s?.fields[key];
      if (f == null) continue;
      for (final r in f.conflicts) {
        final w = r['with'];
        if (w is String && !w.contains('.')) out.add(w);
      }
    }
    return out;
  }



  final MapEntry<String, Object?>? equalsOverride;

  final covered = <String>{};



  Object? equalsValueFor(String target) {
    final o = equalsOverride;
    if (o != null && o.key == target) return o.value;
    return _defaultEnumValue(target);
  }


  Object? equalsForcedValue(String path) {
    final o = equalsOverride;
    if (o == null) return null;


    return o.key == path ? o.value : null;
  }


  Object? _defaultEnumValue(String target) {
    final parts = target.split('.');


    return _enumCache.putIfAbsent(target, () {
      FieldSchema? f;
      Map<String, FieldSchema>? fields;
      for (final scheme in _searchSchemes) {
        final s = ContractRegistry.I.schemaFor(scheme);
        if (s == null) continue;
        fields = s.fields;
        f = null;
        for (final seg in parts) {
          final cur = fields?[seg];
          if (cur == null) {
            f = null;
            break;
          }
          f = cur;
          fields = cur.fields;
        }
        if (f != null) break;
      }
      final values = f?.values;
      if (values == null) return null;
      for (final v in values) {
        if (v == null) continue;
        if (v is String && v.isEmpty) continue;
        return v;
      }
      return null;
    });
  }

  static final _enumCache = <String, Object?>{};




  static const _searchSchemes = <String>[
    'hysteria2',
    'hysteria',
    'vless',
    'vmess',
    'trojan',
    'tuic',
    'anytls',
    'shadowsocks',
    'naive',
    'socks',
    'http',
    'ssh',
    'wireguard',
    'masque',
    'tailscale',
  ];
}
