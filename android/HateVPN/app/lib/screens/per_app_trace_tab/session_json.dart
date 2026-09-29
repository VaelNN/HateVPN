import '../../services/traffic_profiler.dart';







Map<String, Object?> eventsToJson(List<TrafficEvent> events) {
  final agg = computeTraceAggregates(events);
  return {
    'exported_at': DateTime.now().toIso8601String(),
    'event_count': events.length,
    'events': events.map((e) => e.toJson()).toList(),
    'by_domain': agg.byDomain.values.map((d) => d.toJson()).toList(),
    'by_ip': agg.byIp.values.map((i) => i.toJson()).toList(),
  };
}
