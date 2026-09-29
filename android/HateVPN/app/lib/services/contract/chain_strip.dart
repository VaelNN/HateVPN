












library;

import '../../models/source_chain.dart' show kChainOutboundType;
import '../json_clone.dart' show deepCloneJson;
import 'body_sanitizer.dart';
import 'registry.dart';
import 'registry_warning.dart';


final class ChainStripKey {
  const ChainStripKey({
    required this.key,
    required this.stripByDefault,
    required this.schema,
  });



  final String key;


  final bool stripByDefault;

  final FieldSchema schema;

  Map<String, dynamic>? get _onHopRequired =>
      (schema.raw['on_hop_required'] as Map?)?.cast<String, dynamic>();


  String? get unstripCode {
    final r = _onHopRequired;
    if (r == null || r['action'] != 'unstrip') return null;
    return r['code'] as String?;
  }


  String description(RegistryLang lang) =>
      (schema.raw[lang == RegistryLang.ru ? 'desc_ru' : 'desc_en']
          as String?) ??
      '';
}



List<ChainStripKey> chainStripCatalog() {
  final strip = ContractRegistry.I
      .schemaFor(kChainOutboundType)
      ?.fields['strip'];
  final fields = strip?.fields;
  if (fields == null) return const [];
  final order = strip!.order ?? fields.keys.toList();
  return [
    for (final k in order)
      if (fields[k] != null)
        ChainStripKey(
          key: k,
          stripByDefault: fields[k]!.defaultValue == true,
          schema: fields[k]!,
        ),
  ];
}


List<String> chainStripKeys() => [for (final k in chainStripCatalog()) k.key];



bool chainStripKeyKnown(String key) {
  final keys = chainStripKeys();
  return keys.isEmpty || keys.contains(key);
}



Map<String, bool> orderedChainStrip(Map<String, bool> strip) {
  final keys = chainStripKeys();
  return {
    for (final k in keys)
      if (strip.containsKey(k)) k: strip[k]!,
    for (final e in strip.entries)
      if (!keys.contains(e.key)) e.key: e.value,
  };
}




bool chainStripsKey(
  ChainStripKey k, {
  required bool? stripEvasion,
  required Map<String, bool> patch,
}) {
  final explicit = patch[k.key];
  if (explicit != null) return explicit;
  if (stripEvasion == false) return false;
  return k.stripByDefault;
}



bool hopBodyRequiresPath(Map<String, dynamic> body, String path) {
  final type = body['type'];
  if (type is! String) return false;
  final copy = (deepCloneJson(body) as Map).cast<String, dynamic>();
  final parts = path.split('.');
  Map<String, dynamic>? cur = copy;
  for (var i = 0; i < parts.length - 1 && cur != null; i++) {
    final next = cur[parts[i]];
    cur = next is Map ? next.cast<String, dynamic>() : null;
  }


  if (cur == null) return false;
  cur.remove(parts.last);
  final out = RegistrySanitizer.sanitize(
    copy,
    scheme: type,
    coreVersion: '',
    applyCoreGates: false,
  ).body;
  if (out == null) return false;
  Object? v = out;
  for (final p in parts) {
    if (v is! Map) return false;
    v = v[p];
  }
  return v != null;
}


final class ChainUnstrip {
  const ChainUnstrip({
    required this.key,
    required this.code,
    required this.target,
  });

  final String key;
  final String code;


  final String target;
}




List<ChainUnstrip> chainHopUnstrips({
  required bool? stripEvasion,
  required Map<String, bool> patch,
  required List<(String, Map<String, dynamic>?)> hops,
}) {
  final out = <ChainUnstrip>[];
  if (hops.length < 2) return out;
  for (final k in chainStripCatalog()) {
    final code = k.unstripCode;
    if (code == null) continue;
    if (!chainStripsKey(k, stripEvasion: stripEvasion, patch: patch)) continue;
    for (var i = 1; i < hops.length; i++) {
      final body = hops[i].$2;
      if (body == null) continue;
      if (hopBodyRequiresPath(body, k.key)) {
        out.add(ChainUnstrip(key: k.key, code: code, target: hops[i].$1));
      }
    }
  }
  return out;
}


Map<String, bool> applyChainUnstrips(
  Map<String, bool> patch,
  List<ChainUnstrip> unstrips,
) => orderedChainStrip({...patch, for (final u in unstrips) u.key: false});
