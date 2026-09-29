














library;

import 'body_sanitizer.dart' show coreAtLeast;
import 'registry.dart';


final class CoreInfo {
  const CoreInfo({this.version = '', this.tags});


  final String version;


  final Set<String>? tags;


  String? unmet(String? buildTag, String? minCore, String what) {
    final tags = this.tags;
    if (buildTag != null && buildTag.isNotEmpty && tags != null) {
      if (!tags.contains(buildTag)) {
        return 'the core is built without $buildTag';
      }
    }
    if (minCore != null &&
        minCore.isNotEmpty &&
        version.trim().isNotEmpty &&
        !coreAtLeast(version, minCore)) {
      return 'core ${version.trim()} does not support $what '
          '(needs $minCore or newer)';
    }
    return null;
  }
}


final class CoreRefusal {
  const CoreRefusal({required this.code, required this.reason, this.path});


  final String code;



  final String? path;


  final String reason;
}


bool isAwgRangeValue(Object? v) => v is String && v.trim().contains('-');





CoreRefusal? nodeCoreRefusal(
  String scheme,
  Map<String, dynamic> body,
  CoreInfo core,
) {
  if (!ContractRegistry.I.isLoaded) return null;
  final schema = ContractRegistry.I.schemaFor(scheme);
  if (schema == null) return null;
  final top = schema.onCoreUnsupported;
  if (top != null && top.dropsNode) {
    final reason = core.unmet(schema.buildTag, schema.minCore, scheme);
    if (reason != null) return CoreRefusal(code: top.code, reason: reason);
  }
  return _walk('', schema.order, schema.fields, body, scheme, core);
}

CoreRefusal? _walk(
  String prefix,
  List<String> order,
  Map<String, FieldSchema> fields,
  Map<String, dynamic> m,
  String scheme,
  CoreInfo core,
) {
  for (final name in order) {
    final f = fields[name];
    if (f == null) continue;
    final v = m[name];
    if (v == null) continue;
    final path = prefix.isEmpty ? name : '$prefix.$name';
    final what = '$scheme.$path';

    final own = f.onCoreUnsupported;
    if (own != null && own.dropsNode) {
      final reason = core.unmet(f.buildTag, f.minCore, what);
      if (reason != null) {
        return CoreRefusal(code: own.code, path: path, reason: reason);
      }
    }
    final rf = f.rangeForm;
    final rfGate = rf?.onCoreUnsupported;
    if (rf != null && rfGate != null && rfGate.dropsNode && isAwgRangeValue(v)) {
      final reason = core.unmet(rf.buildTag, rf.minCore, '$what as a range');
      if (reason != null) {
        return CoreRefusal(code: rfGate.code, path: path, reason: reason);
      }
    }

    if (v is Map) {
      final inner = v.cast<String, dynamic>();
      final variants = f.variants;
      if (variants != null) {
        final disc = inner[f.discriminator ?? 'type'];
        final vf = disc is String ? variants[disc.trim()] : null;
        if (vf != null) {
          final r = _walk(path, vf.order ?? const [], vf.fields ?? const {},
              inner, scheme, core);
          if (r != null) return r;
        }
        continue;
      }
      final sub = f.fields;
      if (sub != null && sub.isNotEmpty) {
        final r =
            _walk(path, f.order ?? const [], sub, inner, scheme, core);
        if (r != null) return r;
      }
    } else if (v is List) {
      final items = f.items;
      final sub = items?.fields;
      if (items == null || sub == null || sub.isEmpty) continue;
      for (final it in v) {
        if (it is! Map) continue;
        final r = _walk('$path[]', items.order ?? const [], sub,
            it.cast<String, dynamic>(), scheme, core);
        if (r != null) return r;
      }
    }
  }
  return null;
}
