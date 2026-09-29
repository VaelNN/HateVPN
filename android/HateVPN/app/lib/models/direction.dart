













import '../config/consts.dart'
    show kDetourTagPrefix, kDirectOutboundTag, kBlockOutboundTag;
import 'parser_config.dart' show DirectionTemplate, DefaultDirection;







const int kMaxDirections = 10;




const String kDirectionTagPrefix = 'vpn-';










String nextDirectionTag(Iterable<String> usedTags) {
  final used = usedTags.toSet();
  for (var i = 1;; i++) {
    final tag = '$kDirectionTagPrefix$i';
    if (!used.contains(tag)) return tag;
  }
}




String defaultDirectionLabel(int n) {
  if (n < 1 || n > 10) return 'VPN $n';
  return 'VPN ${String.fromCharCode(0x2460 + n - 1)}';
}


int? directionNumberOf(String tag) {
  final m = RegExp(r'^vpn-(\d+)$').firstMatch(tag);
  return m == null ? null : int.tryParse(m.group(1)!);
}





String defaultLabelForTag(String tag) {
  final n = directionNumberOf(tag);
  return n == null ? tag : defaultDirectionLabel(n);
}


const int _kToleranceMax = 65535;



int clampDirectionTolerance(int v) => v < 0 ? 0 : (v > _kToleranceMax ? _kToleranceMax : v);




enum UrltestMode {
  leastTest('least_test'),
  roundRobin('round_robin');

  const UrltestMode(this.wire);


  final String wire;

  static UrltestMode fromWire(String? s) =>
      UrltestMode.values.firstWhere((m) => m.wire == s,
          orElse: () => UrltestMode.leastTest);
}


enum StickyHashKey {
  process('process'),
  domain('domain'),
  sourceIp('source_ip'),
  destIp('dest_ip'),
  destPort('dest_port');

  const StickyHashKey(this.wire);


  final String wire;

  static StickyHashKey? fromWire(String? s) {
    for (final k in StickyHashKey.values) {
      if (k.wire == s) return k;
    }
    return null;
  }
}



const List<StickyHashKey> kDefaultStickyHash = [
  StickyHashKey.process,
  StickyHashKey.domain,
];




int clampDirectionPool(int v) => v < 1 ? 1 : v;




class DirectionAuto {
  const DirectionAuto({
    this.url = 'https://cp.cloudflare.com/generate_204',




    this.interval = '15m',
    this.tolerance = 50,
    this.idleTimeout = '30m',
    this.interruptExistConnections = false,
    this.mode = UrltestMode.leastTest,
    this.pool = 3,
    this.poolTolerance = 0,
    this.stickyHash = kDefaultStickyHash,
  });

  final String url;
  final String interval;
  final int tolerance;
  final String idleTimeout;
  final bool interruptExistConnections;



  final UrltestMode mode;


  final int pool;



  final int poolTolerance;



  final List<StickyHashKey> stickyHash;

  DirectionAuto copyWith({
    String? url,
    String? interval,
    int? tolerance,
    String? idleTimeout,
    bool? interruptExistConnections,
    UrltestMode? mode,
    int? pool,
    int? poolTolerance,
    List<StickyHashKey>? stickyHash,
  }) =>
      DirectionAuto(
        url: url ?? this.url,
        interval: interval ?? this.interval,
        tolerance: tolerance == null ? this.tolerance : clampDirectionTolerance(tolerance),
        idleTimeout: idleTimeout ?? this.idleTimeout,
        interruptExistConnections:
            interruptExistConnections ?? this.interruptExistConnections,
        mode: mode ?? this.mode,
        pool: pool == null ? this.pool : clampDirectionPool(pool),
        poolTolerance:
            poolTolerance == null ? this.poolTolerance : clampDirectionTolerance(poolTolerance),
        stickyHash: stickyHash ?? this.stickyHash,
      );

  factory DirectionAuto.fromJson(Map<String, dynamic> json) {


    final bal = json['balancer'];
    final balMap = bal is Map<String, dynamic> ? bal : const <String, dynamic>{};
    final rawSticky = balMap['sticky_hash'];
    final sticky = rawSticky is List
        ? rawSticky
            .map((e) => StickyHashKey.fromWire(e as String?))
            .whereType<StickyHashKey>()
            .toList()
        : kDefaultStickyHash;
    return DirectionAuto(
      url: json['url'] as String? ?? 'https://cp.cloudflare.com/generate_204',
      interval: json['interval'] as String? ?? '5m',
      tolerance: clampDirectionTolerance((json['tolerance'] as num?)?.toInt() ?? 50),
      idleTimeout: json['idle_timeout'] as String? ?? '30m',
      interruptExistConnections:
          json['interrupt_exist_connections'] as bool? ?? false,
      mode: UrltestMode.fromWire(json['mode'] as String?),
      pool: clampDirectionPool((balMap['pool'] as num?)?.toInt() ?? 3),
      poolTolerance:
          clampDirectionTolerance((balMap['pool_tolerance'] as num?)?.toInt() ?? 0),

      stickyHash: rawSticky is List
          ? sticky
          : kDefaultStickyHash,
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'interval': interval,
        'tolerance': clampDirectionTolerance(tolerance),
        'idle_timeout': idleTimeout,
        'interrupt_exist_connections': interruptExistConnections,


        'mode': mode.wire,
        'balancer': {
          'pool': clampDirectionPool(pool),
          'pool_tolerance': clampDirectionTolerance(poolTolerance),
          'sticky_hash': stickyHash.map((k) => k.wire).toList(),
        },
      };
}



List<String> _parseInclude(Object? raw) {
  if (raw is! List) return const [];
  final out = <String>[];
  for (final e in raw) {
    if (e is! String) continue;
    final t = e.trim();
    if (t.isEmpty || out.contains(t)) continue;
    out.add(t);
  }
  return List.unmodifiable(out);
}





















({List<Direction> healed, int count}) clearIncludeDirectionRefs(
  List<Direction> directions,
  String deletedTag,
) {
  final autoTag = '$deletedTag-auto';
  var count = 0;
  final out = <Direction>[];
  for (final c in directions) {
    final kept = c.include
        .where((t) => t != deletedTag && t != autoTag)
        .toList(growable: false);
    if (kept.length == c.include.length) {
      out.add(c);
      continue;
    }
    count += c.include.length - kept.length;
    out.add(c.copyWith(include: kept));
  }
  return (healed: out, count: count);
}














const Set<String> kReservedDirectionTags = {
  kDirectOutboundTag,
  kBlockOutboundTag,
  'block-out',
  'dns-out',
  'direct',
  'reject',
  'drop',
};



const String kDirectionAutoSuffix = '-auto';








String? directionTagConflict(String tag, Iterable<String> existingTags) {
  final t = tag.trim();
  if (t.isEmpty) return 'empty';
  if (kReservedDirectionTags.contains(t)) return 'reserved';
  final existing = existingTags.toSet();
  if (existing.contains(t)) return 'duplicate';


  if (t.endsWith(kDirectionAutoSuffix) &&
      existing.contains(
          t.substring(0, t.length - kDirectionAutoSuffix.length))) {
    return 'auto_twin';
  }


  if (existing.contains('$t$kDirectionAutoSuffix')) return 'auto_twin';
  return null;
}




class Direction {
  const Direction({
    required this.tag,
    required this.label,
    this.enabled = true,
    this.includeDirect = false,
    this.includeBlock = false,
    this.include = const [],
    this.nodeFilter = '',
    this.nodeFilterInvert = false,
    this.defaultFilter = '',
    this.interruptExistConnections = true,
    this.auto,
    this.isDetour = false,
  });



  final String tag;


  final String label;


  final bool enabled;


  final bool includeDirect;


  final bool includeBlock;






















  final List<String> include;



  final String nodeFilter;




  final bool nodeFilterInvert;


  final String defaultFilter;


  final bool interruptExistConnections;


  final DirectionAuto? auto;








  final bool isDetour;








  String get displayLabel {
    final base = label.isNotEmpty ? label : tag;
    if (!isDetour || base.startsWith(kDetourTagPrefix)) return base;
    return '$kDetourTagPrefix$base';
  }






  static String normalizeLabel(String label, bool isDetour) {
    if (label.isEmpty) return label;
    final marked = label.startsWith(kDetourTagPrefix);
    if (isDetour && !marked) return '$kDetourTagPrefix$label';
    if (!isDetour && marked) return label.substring(kDetourTagPrefix.length);
    return label;
  }







  String get autoTag => '$tag-auto';



  bool get isRequired => tag == 'vpn-1';

  Direction copyWith({
    String? label,
    bool? enabled,
    bool? includeDirect,
    bool? includeBlock,
    List<String>? include,
    String? nodeFilter,
    bool? nodeFilterInvert,
    String? defaultFilter,
    bool? interruptExistConnections,
    DirectionAuto? auto,
    bool clearAuto = false,
    bool? isDetour,
  }) =>
      Direction(
        tag: tag,

        label: normalizeLabel(label ?? this.label, isDetour ?? this.isDetour),
        enabled: enabled ?? this.enabled,
        includeDirect: includeDirect ?? this.includeDirect,
        includeBlock: includeBlock ?? this.includeBlock,
        include: include ?? this.include,
        nodeFilter: nodeFilter ?? this.nodeFilter,
        nodeFilterInvert: nodeFilterInvert ?? this.nodeFilterInvert,
        defaultFilter: defaultFilter ?? this.defaultFilter,
        interruptExistConnections:
            interruptExistConnections ?? this.interruptExistConnections,
        auto: clearAuto ? null : (auto ?? this.auto),
        isDetour: isDetour ?? this.isDetour,
      );

  factory Direction.fromJson(Map<String, dynamic> json) {
    final rawAuto = json['auto'];
    final tag = json['tag'] as String? ?? '';





    final isDetour = tag != 'vpn-1' && (json['detour'] as bool? ?? false);
    return Direction(
      tag: tag,

      label: normalizeLabel(json['label'] as String? ?? tag, isDetour),
      enabled: json['enabled'] as bool? ?? true,
      includeDirect: json['include_direct'] as bool? ?? false,
      includeBlock: json['include_block'] as bool? ?? false,




      include: _parseInclude(json['include']),
      nodeFilter: json['node_filter'] as String? ?? '',
      nodeFilterInvert: json['node_filter_invert'] as bool? ?? false,
      defaultFilter: json['default_filter'] as String? ?? '',
      interruptExistConnections:
          json['interrupt_exist_connections'] as bool? ?? true,
      auto: rawAuto is Map<String, dynamic>
          ? DirectionAuto.fromJson(rawAuto)
          : null,
      isDetour: isDetour,
    );
  }

  Map<String, dynamic> toJson() => {
        'tag': tag,
        'label': label,
        'enabled': enabled,
        'include_direct': includeDirect,
        'include_block': includeBlock,



        if (include.isNotEmpty) 'include': include,
        'node_filter': nodeFilter,
        'node_filter_invert': nodeFilterInvert,
        'default_filter': defaultFilter,
        'interrupt_exist_connections': interruptExistConnections,
        'auto': auto?.toJson(),
        'detour': isDetour,
      };






  static Direction seedFromDefault(
    DefaultDirection dc,
    DirectionTemplate tpl, {
    required bool enabled,
    DirectionAuto? auto,
  }) =>
      Direction(
        tag: dc.tag,
        label: dc.label.isEmpty ? dc.tag : dc.label,
        enabled: enabled,
        includeDirect: tpl.include.contains('direct'),
        includeBlock: tpl.include.contains('block'),
        nodeFilter: '',
        defaultFilter: '',
        interruptExistConnections:
            tpl.options['interrupt_exist_connections'] as bool? ?? true,
        auto: auto,
      );
}
