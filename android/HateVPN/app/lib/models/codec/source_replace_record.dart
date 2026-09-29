



library;

import '../direction.dart';
import '../source_replace.dart';


const Set<String> kReplaceRecordKeys = {'mode', 'tag', 'auto'};
const Set<String> kDirectionAutoRecordKeys = {
  'mode',
  'url',
  'interval',
  'tolerance',
  'idle_timeout',
  'interrupt_exist_connections',
  'pool',
  'pool_tolerance',
  'sticky_hash',
};



Map<String, dynamic> sourceReplaceToRecord(SourceReplace r) => {
      'mode': r.mode.name,
      'tag': r.tag,
      if (r.hasAuto && r.auto != null) 'auto': directionAutoToRecord(r.auto!),
    };




SourceReplace? sourceReplaceFromRecord(Object? raw, [List<String>? unknown]) {
  if (raw is! Map) return null;
  final j = raw.cast<String, dynamic>();
  for (final k in j.keys) {
    if (!kReplaceRecordKeys.contains(k)) unknown?.add('replace.$k');
  }
  final mode = ReplaceMode.fromWire(j['mode']);
  final tag = j['tag'] is String ? (j['tag'] as String).trim() : '';
  final rawAuto = j['auto'];
  DirectionAuto? auto;
  if (rawAuto is Map) {
    final a = rawAuto.cast<String, dynamic>();
    for (final k in a.keys) {
      if (!kDirectionAutoRecordKeys.contains(k)) unknown?.add('replace.auto.$k');
    }
    if (mode != ReplaceMode.manual) auto = directionAutoFromRecord(a);
  }
  return SourceReplace(mode: mode, tag: tag, auto: auto);
}


DirectionAuto directionAutoFromRecord(Map<String, dynamic> j) {
  const fallback = DirectionAuto();
  final rawSticky = j['sticky_hash'];



  final sticky = rawSticky is List
      ? (rawSticky.contains('none')
            ? const <StickyHashKey>[]
            : rawSticky
                  .map((e) => StickyHashKey.fromWire(e as String?))
                  .whereType<StickyHashKey>()
                  .toList())
      : fallback.stickyHash;

  return DirectionAuto(
    mode: UrltestMode.fromWire(j['mode'] as String?),
    url: (j['url'] as String?) ?? fallback.url,
    interval: (j['interval'] as String?) ?? fallback.interval,



    tolerance: clampDirectionTolerance(
      (j['tolerance'] as num?)?.toInt() ?? fallback.tolerance,
    ),
    idleTimeout: (j['idle_timeout'] as String?) ?? fallback.idleTimeout,
    interruptExistConnections:
        j['interrupt_exist_connections'] as bool? ??
        fallback.interruptExistConnections,
    pool: clampDirectionPool((j['pool'] as num?)?.toInt() ?? fallback.pool),
    poolTolerance: clampDirectionTolerance(
      (j['pool_tolerance'] as num?)?.toInt() ?? fallback.poolTolerance,
    ),
    stickyHash: sticky,
  );
}


Map<String, dynamic> directionAutoToRecord(DirectionAuto a) => {
  'mode': a.mode.wire,
  'url': a.url,
  'interval': a.interval,
  'tolerance': clampDirectionTolerance(a.tolerance),
  'idle_timeout': a.idleTimeout,
  'interrupt_exist_connections': a.interruptExistConnections,



  if (a.mode == UrltestMode.roundRobin) ...{
    'pool': clampDirectionPool(a.pool),
    'pool_tolerance': clampDirectionTolerance(a.poolTolerance),


    'sticky_hash': a.stickyHash.isEmpty
        ? const ['none']
        : [for (final k in a.stickyHash) k.wire],
  },
};
