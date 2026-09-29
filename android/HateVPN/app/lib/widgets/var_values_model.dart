import 'package:flutter/foundation.dart';















class VarValuesModel {
  VarValuesModel(Map<String, String> initial) {
    for (final e in initial.entries) {
      _notifiers[e.key] = ValueNotifier<String>(e.value);
    }
  }

  final _notifiers = <String, ValueNotifier<String>>{};
  final _dirty = <String>{};




  ValueNotifier<String> notifier(String name) =>
      _notifiers.putIfAbsent(name, () => ValueNotifier<String>(''));

  String get(String name) => _notifiers[name]?.value ?? '';


  Map<String, String> get snapshot =>
      {for (final e in _notifiers.entries) e.key: e.value.value};



  Set<String> get dirtyKeys => Set.unmodifiable(_dirty);







  bool set(String name, String value, {bool markDirty = true}) {
    final n = notifier(name);
    if (n.value == value) return false;
    n.value = value;
    if (markDirty) _dirty.add(name);
    return true;
  }



  void unstage(String name) => _dirty.remove(name);

  void clearDirty() => _dirty.clear();

  void dispose() {
    for (final n in _notifiers.values) {
      n.dispose();
    }
    _notifiers.clear();
  }
}
