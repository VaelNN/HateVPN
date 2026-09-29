











class NodeFilter {
  const NodeFilter({
    required this.regex,
    this.regexInvert = false,
    required this.protocols,
    this.protocolsInvert = false,
    required this.variants,
    this.variantsInvert = false,
    required this.subscriptions,
    this.subscriptionsInvert = false,
    required this.maxPingMs,
    required this.protocolOf,
    required this.variantsOf,
    required this.subscriptionsOf,
    required this.pingOf,
  });



  final RegExp? regex;



  final bool regexInvert;


  final Set<String> protocols;



  final bool protocolsInvert;




  final Set<String> variants;


  final bool variantsInvert;



  final Set<String> subscriptions;




  final bool subscriptionsInvert;



  final int? maxPingMs;




  final String? Function(String) protocolOf;




  final Set<String> Function(String) variantsOf;






  final Set<String> Function(String) subscriptionsOf;


  final int? Function(String) pingOf;





  bool passes(String tag) {
    if (regex != null) {



      final m = regex!.hasMatch(tag);
      if (m == regexInvert) return false;
    }
    if (protocols.isNotEmpty) {
      final p = protocolOf(tag);





      final member = p != null && protocols.contains(p);
      if (member == protocolsInvert) return false;
    }
    if (variants.isNotEmpty) {


      final member = variantsOf(tag).any(variants.contains);
      if (member == variantsInvert) return false;
    }
    if (subscriptions.isNotEmpty) {
      final candidates = subscriptionsOf(tag);




      final effective = candidates.isEmpty ? const {'custom'} : candidates;
      final member = effective.any(subscriptions.contains);
      if (member == subscriptionsInvert) return false;
    }
    final delay = pingOf(tag);

    if (maxPingMs != null && delay != null && delay > maxPingMs!) {
      return false;
    }
    return true;
  }







  static final _emojiRe = RegExp(

    r'(\p{Regional_Indicator}\p{Regional_Indicator}|\p{Extended_Pictographic})',
    unicode: true,
  );






  static List<String> extractEmojis(List<String> tags) {
    final freq = <String, int>{};
    for (final tag in tags) {
      for (final m in _emojiRe.allMatches(tag)) {
        final e = m.group(0)!;
        freq[e] = (freq[e] ?? 0) + 1;
      }
    }
    final list = freq.entries.toList()
      ..sort((a, b) {
        final byFreq = b.value.compareTo(a.value);
        return byFreq != 0 ? byFreq : a.key.compareTo(b.key);
      });
    return list.map((e) => e.key).toList();
  }
}
