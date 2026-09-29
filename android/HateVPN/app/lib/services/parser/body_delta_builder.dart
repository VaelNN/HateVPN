





library;

import '../../models/body_delta.dart';
import '../contract/registry.dart';


BodyDelta? bodyDeltaFor(
  Map<String, dynamic> body,
  Map<String, dynamic> emitted, {
  bool dropDefaults = false,
}) {
  final reg = ContractRegistry.I;
  if (!reg.isLoaded) return null;
  final type = body['type'];
  if (type is! String) return null;
  final schema = reg.schemaFor(type);
  if (schema == null) return null;
  final add = <(BodyPath, Object?)>[];
  final drop = <BodyPath>[];
  _walk(schema.fields, body, emitted, const [], add, drop, canDrop: dropDefaults);
  if (add.isEmpty && drop.isEmpty) return null;
  return BodyDelta(add: add, drop: drop);
}

void _walk(
  Map<String, FieldSchema> fields,
  Map body,
  Map emitted,
  BodyPath path,
  List<(BodyPath, Object?)> add,
  List<BodyPath> drop, {
  required bool canDrop,
}) {
  for (final e in fields.entries) {
    final key = e.key;
    final f = e.value;
    if (f.managed) continue;
    final inBody = body.containsKey(key) && body[key] != null;
    final inEmit = emitted.containsKey(key) && emitted[key] != null;
    final p = [...path, key];
    if (inBody && !inEmit) {


      if (!_isEmptyValue(body[key])) add.add((p, body[key]));
    } else if (!inBody && inEmit) {




      final def = f.defaultValue;
      final v = emitted[key];
      if (canDrop && def != null && v is! Map && v is! List && '$v' == '$def') {
        drop.add(p);
      }
    } else if (inBody && inEmit) {
      final b = body[key];
      final m = emitted[key];
      if (b is! Map || m is! Map) continue;
      final own = f.fields;
      final sub = own ?? _variantFields(f, b);



      if (sub != null) {
        _walk(sub, b, m, p, add, drop, canDrop: canDrop && own != null);
      }
    }
  }
}



Map<String, FieldSchema>? _variantFields(FieldSchema f, Map value) {
  final disc = f.discriminator;
  final variants = f.variants;
  if (disc == null || variants == null) return null;
  return variants['${value[disc]}']?.fields;
}

bool _isEmptyValue(Object? v) =>
    (v is String && v.isEmpty) ||
    (v is List && v.isEmpty) ||
    (v is Map && v.isEmpty);
