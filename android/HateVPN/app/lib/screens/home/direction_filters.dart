










class DirectionFilters {
  const DirectionFilters({
    this.regexPattern = '',
    this.regexInvert = false,
    this.protocols = const <String>{},
    this.protocolsInvert = false,
    this.variants = const <String>{},
    this.variantsInvert = false,
    this.subscriptions = const <String>{},
    this.subscriptionsInvert = false,
    this.pingText = '',
    this.pingEnabled = false,
  });


  final String regexPattern;


  final bool regexInvert;


  final Set<String> protocols;


  final bool protocolsInvert;



  final Set<String> variants;


  final bool variantsInvert;


  final Set<String> subscriptions;


  final bool subscriptionsInvert;


  final String pingText;


  final bool pingEnabled;



  static const empty = DirectionFilters();



  bool get isEmpty =>
      regexPattern.isEmpty &&
      !regexInvert &&
      protocols.isEmpty &&
      !protocolsInvert &&
      variants.isEmpty &&
      !variantsInvert &&
      subscriptions.isEmpty &&
      !subscriptionsInvert &&
      pingText.isEmpty &&
      !pingEnabled;
}
