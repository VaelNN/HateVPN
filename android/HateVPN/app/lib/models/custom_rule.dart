import 'dart:convert';

import '../config/consts.dart' show kDirectOutboundTag;
import '../services/parser/uri_utils.dart' show newUuidV4;
import '../services/l10n/locale_controller.dart';






















const int kDefaultSrsTtlHours = 168;




const List<int> kSrsTtlChoicesHours = [
  0,
  24,
  168,
  336,
  720,
  4320,
  8760,
];

sealed class CustomRule {
  CustomRule({
    String? id,
    required this.name,
    required this.enabled,
    this.orderNum,
  }) : id = id ?? newUuidV4();

  final String id;
  String name;
  bool enabled;








  int? orderNum;



  CustomRuleKind get kind;




  String summary();






  List<String> get domains => switch (this) {
        CustomRuleInline(:final domains) => domains,
        _ => const [],
      };
  List<String> get domainSuffixes => switch (this) {
        CustomRuleInline(:final domainSuffixes) => domainSuffixes,
        _ => const [],
      };
  List<String> get domainKeywords => switch (this) {
        CustomRuleInline(:final domainKeywords) => domainKeywords,
        _ => const [],
      };
  List<String> get ipCidrs => switch (this) {
        CustomRuleInline(:final ipCidrs) => ipCidrs,
        _ => const [],
      };
  List<String> get ports => switch (this) {
        CustomRuleInline(:final ports) => ports,
        CustomRuleSrs(:final ports) => ports,
        _ => const [],
      };
  List<String> get portRanges => switch (this) {
        CustomRuleInline(:final portRanges) => portRanges,
        CustomRuleSrs(:final portRanges) => portRanges,
        _ => const [],
      };
  List<String> get packages => switch (this) {
        CustomRuleInline(:final packages) => packages,
        CustomRuleSrs(:final packages) => packages,
        _ => const [],
      };
  List<String> get protocols => switch (this) {
        CustomRuleInline(:final protocols) => protocols,
        CustomRuleSrs(:final protocols) => protocols,
        _ => const [],
      };




  List<String> get network => switch (this) {
        CustomRuleInline(:final network) => network,
        CustomRuleSrs(:final network) => network,
        _ => const [],
      };
  bool get ipIsPrivate => switch (this) {
        CustomRuleInline(:final ipIsPrivate) => ipIsPrivate,
        CustomRuleSrs(:final ipIsPrivate) => ipIsPrivate,
        _ => false,
      };





  List<String> get sourceIpCidrs => switch (this) {
        CustomRuleInline(:final sourceIpCidrs) => sourceIpCidrs,
        CustomRuleSrs(:final sourceIpCidrs) => sourceIpCidrs,
        _ => const [],
      };




  bool get sourceIpIsPrivate => switch (this) {
        CustomRuleInline(:final sourceIpIsPrivate) => sourceIpIsPrivate,
        CustomRuleSrs(:final sourceIpIsPrivate) => sourceIpIsPrivate,
        _ => false,
      };




  List<String> get inbounds => switch (this) {
        CustomRuleInline(:final inbounds) => inbounds,
        CustomRuleSrs(:final inbounds) => inbounds,
        _ => const [],
      };






  List<String> get wifiSsids => switch (this) {
        CustomRuleInline(:final wifiSsids) => wifiSsids,
        CustomRuleSrs(:final wifiSsids) => wifiSsids,
        _ => const [],
      };



  List<String> get wifiBssids => switch (this) {
        CustomRuleInline(:final wifiBssids) => wifiBssids,
        CustomRuleSrs(:final wifiBssids) => wifiBssids,
        _ => const [],
      };




  RuleDns? get dns => switch (this) {
        CustomRuleInline(:final dns) => dns,
        CustomRuleSrs(:final dns) => dns,
        _ => null,
      };






  bool get dnsMirrorEligible =>
      enabled &&
      (dns?.serverTag.isNotEmpty ?? false) &&
      ports.isEmpty &&
      portRanges.isEmpty &&
      protocols.isEmpty &&
      network.isEmpty;



  bool get dnsMirrorActive => dnsMirrorEligible && (dns?.enabled ?? false);






  bool get forceIpv4Eligible =>
      enabled &&
      ports.isEmpty &&
      portRanges.isEmpty &&
      protocols.isEmpty &&
      network.isEmpty;



  bool get forceIpv4Active => forceIpv4Eligible && (dns?.forceIpv4 ?? false);



  RuleResolve? get resolve => switch (this) {
        CustomRuleInline(:final resolve) => resolve,
        CustomRuleSrs(:final resolve) => resolve,
        _ => null,
      };





  bool get resolveEligible => switch (this) {
        CustomRuleInline() => domains.isNotEmpty ||
            domainSuffixes.isNotEmpty ||
            domainKeywords.isNotEmpty,
        CustomRuleSrs() => true,
        _ => false,
      };




  bool get resolveActive => resolve != null && resolveEligible;

  String get srsUrl => switch (this) {
        CustomRuleSrs(:final srsUrl) => srsUrl,
        _ => '',
      };



  List<String> get srsUrls => switch (this) {
        CustomRuleSrs(:final srsUrls) => srsUrls,
        _ => const [],
      };


  String get json => switch (this) {
        CustomRuleJson(:final json) => json,
        _ => '',
      };
  String get presetId => switch (this) {
        CustomRulePreset(:final presetId) => presetId,
        _ => '',
      };
  Map<String, String> get varsValues => switch (this) {
        CustomRulePreset(:final varsValues) => varsValues,
        _ => const {},
      };







  String get outbound => switch (this) {
        CustomRuleInline(:final outbound) => outbound,
        CustomRuleSrs(:final outbound) => outbound,
        CustomRulePreset(:final varsValues) => varsValues['outbound'] ?? '',


        CustomRuleJson() => '',
      };



  List<int> get intPorts => ports
      .map(int.tryParse)
      .whereType<int>()
      .where((p) => p >= 0 && p <= 65535)
      .toList();






  CustomRule withEnabled(bool enabled);
  CustomRule withName(String name);



  CustomRule withOutbound(String outbound);
}

enum CustomRuleKind { inline, srs, preset, json }






class RuleDns {
  const RuleDns({
    this.enabled = false,
    this.serverTag = '',
    this.forceIpv4 = false,
  });

  final bool enabled;
  final String serverTag;





  final bool forceIpv4;

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'serverTag': serverTag,
        if (forceIpv4) 'forceIpv4': true,
      };


  static RuleDns? fromJson(dynamic j) {
    if (j is! Map) return null;
    return RuleDns(
      enabled: j['enabled'] == true,
      serverTag: j['serverTag']?.toString() ?? '',
      forceIpv4: j['forceIpv4'] == true,
    );
  }

  RuleDns copyWith({bool? enabled, String? serverTag, bool? forceIpv4}) =>
      RuleDns(
        enabled: enabled ?? this.enabled,
        serverTag: serverTag ?? this.serverTag,
        forceIpv4: forceIpv4 ?? this.forceIpv4,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RuleDns &&
          enabled == other.enabled &&
          serverTag == other.serverTag &&
          forceIpv4 == other.forceIpv4);

  @override
  int get hashCode => Object.hash(enabled, serverTag, forceIpv4);
}














class RuleResolve {
  const RuleResolve({
    this.only = false,
    this.strategy = '',
    this.serverTag = '',
    this.disableCache = false,
    this.disableOptimisticCache = false,
    this.rewriteTtl,
    this.timeout = '',
    this.clientSubnet = '',
  });

  final bool only;


  final String strategy;


  final String serverTag;

  final bool disableCache;
  final bool disableOptimisticCache;


  final int? rewriteTtl;


  final String timeout;


  final String clientSubnet;

  Map<String, dynamic> toJson() => {
        'only': only,
        if (strategy.isNotEmpty) 'strategy': strategy,
        if (serverTag.isNotEmpty) 'serverTag': serverTag,
        if (disableCache) 'disableCache': true,
        if (disableOptimisticCache) 'disableOptimisticCache': true,
        if (rewriteTtl != null) 'rewriteTtl': rewriteTtl,
        if (timeout.isNotEmpty) 'timeout': timeout,
        if (clientSubnet.isNotEmpty) 'clientSubnet': clientSubnet,
      };


  static RuleResolve? fromJson(dynamic j) {
    if (j is! Map) return null;
    return RuleResolve(
      only: j['only'] == true,
      strategy: j['strategy']?.toString() ?? '',
      serverTag: j['serverTag']?.toString() ?? '',
      disableCache: j['disableCache'] == true,
      disableOptimisticCache: j['disableOptimisticCache'] == true,
      rewriteTtl: switch (j['rewriteTtl']) {
        final int v when v >= 0 => v,
        final String s => int.tryParse(s),
        _ => null,
      },
      timeout: j['timeout']?.toString() ?? '',
      clientSubnet: j['clientSubnet']?.toString() ?? '',
    );
  }

  RuleResolve copyWith({
    bool? only,
    String? strategy,
    String? serverTag,
    bool? disableCache,
    bool? disableOptimisticCache,
    int? rewriteTtl,
    bool clearRewriteTtl = false,
    String? timeout,
    String? clientSubnet,
  }) =>
      RuleResolve(
        only: only ?? this.only,
        strategy: strategy ?? this.strategy,
        serverTag: serverTag ?? this.serverTag,
        disableCache: disableCache ?? this.disableCache,
        disableOptimisticCache:
            disableOptimisticCache ?? this.disableOptimisticCache,
        rewriteTtl: clearRewriteTtl ? null : (rewriteTtl ?? this.rewriteTtl),
        timeout: timeout ?? this.timeout,
        clientSubnet: clientSubnet ?? this.clientSubnet,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RuleResolve &&
          only == other.only &&
          strategy == other.strategy &&
          serverTag == other.serverTag &&
          disableCache == other.disableCache &&
          disableOptimisticCache == other.disableOptimisticCache &&
          rewriteTtl == other.rewriteTtl &&
          timeout == other.timeout &&
          clientSubnet == other.clientSubnet);

  @override
  int get hashCode => Object.hash(only, strategy, serverTag, disableCache,
      disableOptimisticCache, rewriteTtl, timeout, clientSubnet);
}




const String kOutboundReject = 'reject';




const List<String> kKnownProtocols = [
  'bittorrent',
  'dns',
  'dtls',
  'http',
  'ntp',
  'quic',
  'rdp',
  'ssh',
  'stun',
  'tls',
];




const List<String> kKnownNetworks = [
  'tcp',
  'udp',
  'icmp',
];











class CustomRuleInline extends CustomRule {
  CustomRuleInline({
    super.id,
    required super.name,
    super.enabled = true,
    super.orderNum,
    this.domains = const [],
    this.domainSuffixes = const [],
    this.domainKeywords = const [],
    this.ipCidrs = const [],
    this.ports = const [],
    this.portRanges = const [],
    this.packages = const [],
    this.protocols = const [],
    this.network = const [],
    this.ipIsPrivate = false,
    this.sourceIpCidrs = const [],
    this.sourceIpIsPrivate = false,
    this.inbounds = const [],
    this.wifiSsids = const [],
    List<String> wifiBssids = const [],
    this.outbound = kDirectOutboundTag,
    this.dns,
    this.resolve,
  }) : wifiBssids = _normalizeBssids(wifiBssids);


  @override
  List<String> domains;
  @override
  List<String> domainSuffixes;
  @override
  List<String> domainKeywords;
  @override
  List<String> ipCidrs;


  @override
  List<String> ports;
  @override
  List<String> portRanges;


  @override
  List<String> packages;


  @override
  List<String> protocols;

  @override
  List<String> network;
  @override
  bool ipIsPrivate;



  @override
  List<String> sourceIpCidrs;



  @override
  bool sourceIpIsPrivate;



  @override
  List<String> inbounds;




  @override
  List<String> wifiSsids;
  @override
  List<String> wifiBssids;


  @override
  String outbound;


  @override
  RuleDns? dns;


  @override
  RuleResolve? resolve;

  @override
  CustomRuleKind get kind => CustomRuleKind.inline;

  @override
  String summary() {
    final parts = <String>[];
    if (domains.isNotEmpty) parts.add(getLocalText.plural("%d domains", domains.length));
    if (domainSuffixes.isNotEmpty) {
      parts.add(getLocalText.plural("%d suffixes", domainSuffixes.length));
    }
    if (domainKeywords.isNotEmpty) {
      parts.add(getLocalText.plural("%d keywords", domainKeywords.length));
    }
    if (ipCidrs.isNotEmpty) parts.add(getLocalText.plural("%d cidrs", ipCidrs.length));
    if (ipIsPrivate) parts.add(getLocalText.s("private ip"));
    if (sourceIpCidrs.isNotEmpty) {
      parts.add(getLocalText.plural("%d src", sourceIpCidrs.length));
    }
    if (sourceIpIsPrivate) parts.add(getLocalText.s("private src"));
    final totalPorts = ports.length + portRanges.length;
    if (totalPorts > 0) parts.add(getLocalText.plural("%d ports", totalPorts));
    if (packages.isNotEmpty) parts.add(getLocalText.plural("%d apps", packages.length));
    if (protocols.isNotEmpty) parts.add(getLocalText.plural("%d proto", protocols.length));
    if (network.isNotEmpty) parts.add(getLocalText.plural("%d net", network.length));
    if (inbounds.isNotEmpty) parts.add(getLocalText.s("%d in", inbounds.length));
    if (wifiSsids.isNotEmpty) parts.add(getLocalText.s("%d wifi", wifiSsids.length));
    return parts.join(' · ');
  }

  CustomRuleInline copyWith({
    String? name,
    bool? enabled,
    int? orderNum,
    List<String>? domains,
    List<String>? domainSuffixes,
    List<String>? domainKeywords,
    List<String>? ipCidrs,
    List<String>? ports,
    List<String>? portRanges,
    List<String>? packages,
    List<String>? protocols,
    List<String>? network,
    bool? ipIsPrivate,
    List<String>? sourceIpCidrs,
    bool? sourceIpIsPrivate,
    List<String>? inbounds,
    List<String>? wifiSsids,
    List<String>? wifiBssids,
    String? outbound,
    RuleDns? dns,



    bool clearDns = false,
    RuleResolve? resolve,

    bool clearResolve = false,
  }) =>
      CustomRuleInline(
        id: id,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        orderNum: orderNum ?? this.orderNum,
        domains: domains ?? this.domains,
        domainSuffixes: domainSuffixes ?? this.domainSuffixes,
        domainKeywords: domainKeywords ?? this.domainKeywords,
        ipCidrs: ipCidrs ?? this.ipCidrs,
        ports: ports ?? this.ports,
        portRanges: portRanges ?? this.portRanges,
        packages: packages ?? this.packages,
        protocols: protocols ?? this.protocols,
        network: network ?? this.network,
        ipIsPrivate: ipIsPrivate ?? this.ipIsPrivate,
        sourceIpCidrs: sourceIpCidrs ?? this.sourceIpCidrs,
        sourceIpIsPrivate: sourceIpIsPrivate ?? this.sourceIpIsPrivate,
        inbounds: inbounds ?? this.inbounds,
        wifiSsids: wifiSsids ?? this.wifiSsids,
        wifiBssids: wifiBssids ?? this.wifiBssids,
        outbound: outbound ?? this.outbound,
        dns: clearDns ? null : (dns ?? this.dns),
        resolve: clearResolve ? null : (resolve ?? this.resolve),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CustomRuleInline &&
          id == other.id &&
          name == other.name &&
          enabled == other.enabled &&
          orderNum == other.orderNum &&
          _listEq(domains, other.domains) &&
          _listEq(domainSuffixes, other.domainSuffixes) &&
          _listEq(domainKeywords, other.domainKeywords) &&
          _listEq(ipCidrs, other.ipCidrs) &&
          _listEq(ports, other.ports) &&
          _listEq(portRanges, other.portRanges) &&
          _listEq(packages, other.packages) &&
          _listEq(protocols, other.protocols) &&
          _listEq(network, other.network) &&
          ipIsPrivate == other.ipIsPrivate &&
          _listEq(sourceIpCidrs, other.sourceIpCidrs) &&
          sourceIpIsPrivate == other.sourceIpIsPrivate &&
          _listEq(inbounds, other.inbounds) &&
          _listEq(wifiSsids, other.wifiSsids) &&
          _listEq(wifiBssids, other.wifiBssids) &&
          outbound == other.outbound &&
          dns == other.dns &&
          resolve == other.resolve);

  @override
  int get hashCode => Object.hashAll([
        id,
        name,
        enabled,
        orderNum,
        Object.hashAll(domains),
        Object.hashAll(domainSuffixes),
        Object.hashAll(domainKeywords),
        Object.hashAll(ipCidrs),
        Object.hashAll(ports),
        Object.hashAll(portRanges),
        Object.hashAll(packages),
        Object.hashAll(protocols),
        Object.hashAll(network),
        ipIsPrivate,
        Object.hashAll(sourceIpCidrs),
        sourceIpIsPrivate,
        Object.hashAll(inbounds),
        Object.hashAll(wifiSsids),
        Object.hashAll(wifiBssids),
        outbound,
        dns,
        resolve,
      ]);

  @override
  CustomRuleInline withEnabled(bool enabled) => copyWith(enabled: enabled);
  @override
  CustomRuleInline withName(String name) => copyWith(name: name);
  @override
  CustomRuleInline withOutbound(String outbound) => copyWith(outbound: outbound);
}






class CustomRuleSrs extends CustomRule {
  CustomRuleSrs({
    super.id,
    required super.name,
    super.enabled = true,
    super.orderNum,
    String srsUrl = '',
    List<String> srsUrls = const [],
    this.ports = const [],
    this.portRanges = const [],
    this.packages = const [],
    this.protocols = const [],
    this.network = const [],
    this.ipIsPrivate = false,
    this.sourceIpCidrs = const [],
    this.sourceIpIsPrivate = false,
    this.inbounds = const [],
    this.wifiSsids = const [],
    List<String> wifiBssids = const [],
    this.outbound = kDirectOutboundTag,
    this.dns,
    this.resolve,
    this.updateIntervalHours = kDefaultSrsTtlHours,
  })  : wifiBssids = _normalizeBssids(wifiBssids),
        srsUrls = normalizeSrsUrls(srsUrl, srsUrls);







  @override
  List<String> srsUrls;

  @override
  String get srsUrl => srsUrls.isEmpty ? '' : srsUrls.first;





  static String cacheIdAt(String ruleId, int index) =>
      index == 0 ? ruleId : '$ruleId~$index';


  List<String> get cacheIds =>
      [for (var i = 0; i < srsUrls.length; i++) cacheIdAt(id, i)];





  int updateIntervalHours;




  @override
  List<String> ports;
  @override
  List<String> portRanges;
  @override
  List<String> packages;
  @override
  List<String> protocols;

  @override
  List<String> network;
  @override
  bool ipIsPrivate;




  @override
  List<String> sourceIpCidrs;
  @override
  bool sourceIpIsPrivate;
  @override
  List<String> inbounds;


  @override
  List<String> wifiSsids;
  @override
  List<String> wifiBssids;

  @override
  String outbound;




  @override
  RuleDns? dns;



  @override
  RuleResolve? resolve;

  @override
  CustomRuleKind get kind => CustomRuleKind.srs;

  @override
  String summary() {
    if (srsUrl.trim().isEmpty) return '';
    final host = Uri.tryParse(srsUrl)?.host;
    final first = host?.isNotEmpty == true ? host! : srsUrl;

    if (srsUrls.length > 1) {
      return getLocalText.s("SRS: %s (+%d)", first, srsUrls.length - 1);
    }
    return getLocalText.s("SRS: %s", first);
  }



  static int ttlHoursFrom(Object? v) {
    final n = v is num ? v.toInt() : null;
    if (n == null || n < 0) return kDefaultSrsTtlHours;
    return n;
  }

  CustomRuleSrs copyWith({
    String? name,
    bool? enabled,
    int? orderNum,
    String? srsUrl,
    List<String>? srsUrls,
    List<String>? ports,
    List<String>? portRanges,
    List<String>? packages,
    List<String>? protocols,
    List<String>? network,
    bool? ipIsPrivate,
    List<String>? sourceIpCidrs,
    bool? sourceIpIsPrivate,
    List<String>? inbounds,
    List<String>? wifiSsids,
    List<String>? wifiBssids,
    String? outbound,
    RuleDns? dns,
    bool clearDns = false,
    RuleResolve? resolve,
    bool clearResolve = false,
    int? updateIntervalHours,
  }) =>
      CustomRuleSrs(
        id: id,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        orderNum: orderNum ?? this.orderNum,


        srsUrls: srsUrls ?? (srsUrl != null ? [srsUrl] : this.srsUrls),
        ports: ports ?? this.ports,
        portRanges: portRanges ?? this.portRanges,
        packages: packages ?? this.packages,
        protocols: protocols ?? this.protocols,
        network: network ?? this.network,
        ipIsPrivate: ipIsPrivate ?? this.ipIsPrivate,
        sourceIpCidrs: sourceIpCidrs ?? this.sourceIpCidrs,
        sourceIpIsPrivate: sourceIpIsPrivate ?? this.sourceIpIsPrivate,
        inbounds: inbounds ?? this.inbounds,
        wifiSsids: wifiSsids ?? this.wifiSsids,
        wifiBssids: wifiBssids ?? this.wifiBssids,
        outbound: outbound ?? this.outbound,
        dns: clearDns ? null : (dns ?? this.dns),
        resolve: clearResolve ? null : (resolve ?? this.resolve),
        updateIntervalHours:
            updateIntervalHours ?? this.updateIntervalHours,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CustomRuleSrs &&
          id == other.id &&
          name == other.name &&
          enabled == other.enabled &&
          orderNum == other.orderNum &&
          _listEq(srsUrls, other.srsUrls) &&
          _listEq(ports, other.ports) &&
          _listEq(portRanges, other.portRanges) &&
          _listEq(packages, other.packages) &&
          _listEq(protocols, other.protocols) &&
          _listEq(network, other.network) &&
          ipIsPrivate == other.ipIsPrivate &&
          _listEq(sourceIpCidrs, other.sourceIpCidrs) &&
          sourceIpIsPrivate == other.sourceIpIsPrivate &&
          _listEq(inbounds, other.inbounds) &&
          _listEq(wifiSsids, other.wifiSsids) &&
          _listEq(wifiBssids, other.wifiBssids) &&
          outbound == other.outbound &&
          dns == other.dns &&
          resolve == other.resolve &&
          updateIntervalHours == other.updateIntervalHours);

  @override
  int get hashCode => Object.hashAll([
        id,
        name,
        enabled,
        orderNum,
        Object.hashAll(srsUrls),
        Object.hashAll(ports),
        Object.hashAll(portRanges),
        Object.hashAll(packages),
        Object.hashAll(protocols),
        Object.hashAll(network),
        ipIsPrivate,
        Object.hashAll(sourceIpCidrs),
        sourceIpIsPrivate,
        Object.hashAll(inbounds),
        Object.hashAll(wifiSsids),
        Object.hashAll(wifiBssids),
        outbound,
        dns,
        resolve,
        updateIntervalHours,
      ]);

  @override
  CustomRuleSrs withEnabled(bool enabled) => copyWith(enabled: enabled);
  @override
  CustomRuleSrs withName(String name) => copyWith(name: name);
  @override
  CustomRuleSrs withOutbound(String outbound) => copyWith(outbound: outbound);
}














class CustomRulePreset extends CustomRule {
  CustomRulePreset({
    super.id,
    required super.name,
    super.enabled = true,
    super.orderNum,
    required this.presetId,
    Map<String, String>? varsValues,
  }) : varsValues = Map<String, String>.from(varsValues ?? const {});

  @override
  String presetId;









  @override
  Map<String, String> varsValues;

  @override
  CustomRuleKind get kind => CustomRuleKind.preset;

  @override
  String summary() {




    if (presetId.isEmpty) return '';
    if (varsValues.isEmpty) return '';
    return varsValues.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) => '${e.key}=${e.value}')
        .take(2)
        .join(', ');
  }

  CustomRulePreset copyWith({
    String? name,
    bool? enabled,
    int? orderNum,
    String? presetId,
    Map<String, String>? varsValues,
  }) =>
      CustomRulePreset(
        id: id,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        orderNum: orderNum ?? this.orderNum,
        presetId: presetId ?? this.presetId,
        varsValues: varsValues ?? this.varsValues,
      );


  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CustomRulePreset &&
          id == other.id &&
          name == other.name &&
          enabled == other.enabled &&
          orderNum == other.orderNum &&
          presetId == other.presetId &&
          _mapEq(varsValues, other.varsValues));

  @override
  int get hashCode => Object.hash(
        id,
        name,
        enabled,
        orderNum,
        presetId,
        Object.hashAllUnordered(
            varsValues.entries.map((e) => Object.hash(e.key, e.value))),
      );

  @override
  CustomRulePreset withEnabled(bool enabled) => copyWith(enabled: enabled);
  @override
  CustomRulePreset withName(String name) => copyWith(name: name);







  @override
  CustomRulePreset withOutbound(String outbound) {
    final updated = Map<String, String>.from(varsValues);
    updated['outbound'] = outbound;
    return copyWith(varsValues: updated);
  }
}
















class CustomRuleJson extends CustomRule {
  CustomRuleJson({
    super.id,
    required super.name,
    super.enabled = true,
    super.orderNum,
    this.json = '',
  });


  @override
  final String json;

  @override
  CustomRuleKind get kind => CustomRuleKind.json;

  @override
  String summary() {

    final oneLine = json.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.isEmpty) return '';
    return oneLine.length <= 48 ? oneLine : '${oneLine.substring(0, 48)}…';
  }

  CustomRuleJson copyWith({String? name, bool? enabled, int? orderNum, String? json}) =>
      CustomRuleJson(
        id: id,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        orderNum: orderNum ?? this.orderNum,
        json: json ?? this.json,
      );




  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CustomRuleJson &&
          id == other.id &&
          name == other.name &&
          enabled == other.enabled &&
          orderNum == other.orderNum &&
          (json == other.json ||
              (_canonicalJson(json) ?? json) ==
                  (_canonicalJson(other.json) ?? other.json)));

  @override
  int get hashCode =>
      Object.hash(id, name, enabled, orderNum, _canonicalJson(json) ?? json);

  @override
  CustomRuleJson withEnabled(bool enabled) => copyWith(enabled: enabled);
  @override
  CustomRuleJson withName(String name) => copyWith(name: name);


  @override
  CustomRuleJson withOutbound(String outbound) => this;
}




String? _canonicalJson(String text) {
  try {
    return jsonEncode(jsonDecode(text));
  } on FormatException {
    return null;
  }
}



List<String> normalizeSrsUrls(String srsUrl, List<String> srsUrls) {
  final out = <String>[];
  for (final u in srsUrls.isEmpty ? [srsUrl] : srsUrls) {
    final t = u.trim();
    if (t.isNotEmpty && !out.contains(t)) out.add(t);
  }
  return out;
}



List<String> parseSrsUrlsText(String text) =>
    normalizeSrsUrls('', text.split(RegExp(r'\s+')));

bool _listEq(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEq(Map<String, String> a, Map<String, String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (!b.containsKey(e.key) || b[e.key] != e.value) return false;
  }
  return true;
}





List<String> _normalizeBssids(List<String> bssids) {
  if (bssids.isEmpty) return const [];
  return bssids.map((b) => b.trim().toLowerCase()).toList(growable: false);
}
