import 'package:flutter/foundation.dart' show visibleForTesting;















class SelectorInfo {
  SelectorInfo._();
  static final SelectorInfo I = SelectorInfo._();




  final Set<String> _kernelTags = <String>{};




  final Set<String> _fallbackTags = <String>{};



  final Map<String, String> _selected = <String, String>{};


  void setGroups(Map<String, String> tagToSelected) {
    _kernelTags
      ..clear()
      ..addAll(tagToSelected.keys);
    _selected
      ..clear()
      ..addAll(tagToSelected);
  }



  void setFallbackTags(Iterable<String> tags) {
    _fallbackTags
      ..clear()
      ..addAll(tags);
  }




  void clearSelected() => _selected.clear();

  bool isSelector(String tag) =>
      _kernelTags.contains(tag) || _fallbackTags.contains(tag);


  String? selectedOf(String tag) => _selected[tag];


  @visibleForTesting
  void resetForTesting() {
    _kernelTags.clear();
    _fallbackTags.clear();
    _selected.clear();
  }
}










List<String> foldSelectorPairs(List<String> chain) {
  if (chain.length < 2) return chain;
  final out = <String>[];
  String? carry;
  for (var i = chain.length - 1; i >= 0; i--) {
    final t = chain[i];
    if (carry != null && SelectorInfo.I.isSelector(t)) {
      carry = '$t ($carry)';
    } else {
      if (carry != null) out.add(carry);
      carry = t;
    }
  }
  if (carry != null) out.add(carry);
  return out.reversed.toList();
}
