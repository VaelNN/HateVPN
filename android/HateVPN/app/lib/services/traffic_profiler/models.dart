part of '../traffic_profiler.dart';





enum TrafficEventKind { dnsResolve, dnsFail, tcpOpen, tcpClose, udpOpen }




enum ConfidenceLevel {


  verified,



  secondary,




  inferred,




  unattributed,
}










enum ConnectionIssueKind { dnsTimeout, tcpReset }

class ConnectionIssue {
  const ConnectionIssue(this.kind, this.description);
  final ConnectionIssueKind kind;
  final String description;

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'description': description,
      };
}








({Map<String, DomainStats> byDomain, Map<String, IpStats> byIp})
    computeTraceAggregates(List<TrafficEvent> events) {
  final byDomain = <String, DomainStats>{};
  final byIp = <String, IpStats>{};
  for (final e in events) {
    if (e.confidence == ConfidenceLevel.unattributed) continue;
    if (e.domain != null && e.domain!.isNotEmpty) {
      final d = byDomain.putIfAbsent(e.domain!, () => DomainStats(e.domain!));
      d.firstSeen ??= e.ts;
      d.lastSeen = e.ts;
      if (e.ip != null) d.ips.add(e.ip!);
      for (final c in e.cnameChain) {
        d.cnameTargets.add(c);
      }
      for (final o in e.outboundChain) {
        d.outbounds.add(o);
      }
      if (e.kind == TrafficEventKind.tcpOpen ||
          e.kind == TrafficEventKind.udpOpen) {
        d.connections++;
      }
      if (e.upBytes != null) d.upBytes += e.upBytes!;
      if (e.downBytes != null) d.downBytes += e.downBytes!;
      for (final a in e.issues) {
        if (!d.issues.any((x) => x.kind == a.kind)) d.issues.add(a);
      }
    }
    if (e.ip != null && e.ip!.isNotEmpty) {
      final ip = byIp.putIfAbsent(e.ip!, () => IpStats(e.ip!));
      ip.firstSeen ??= e.ts;
      ip.lastSeen = e.ts;
      if (e.port != null) ip.ports.add(e.port!);
      for (final o in e.outboundChain) {
        ip.outbounds.add(o);
      }
      if (e.kind == TrafficEventKind.tcpOpen ||
          e.kind == TrafficEventKind.udpOpen) {
        ip.connections++;
      }
      if (e.upBytes != null) ip.upBytes += e.upBytes!;
      if (e.downBytes != null) ip.downBytes += e.downBytes!;
    }
  }
  return (byDomain: byDomain, byIp: byIp);
}

class TrafficEvent {
  TrafficEvent({
    required this.ts,
    required this.kind,
    this.domain,
    this.cnameChain = const [],
    this.ip,
    this.port,
    this.outboundChain = const [],
    this.detourChain = const [],
    this.outboundType,
    this.upBytes,
    this.downBytes,
    this.duration,
    this.connId,
    this.process,
    this.processInferred = false,
    this.network,
    this.rule,
    this.rulePayload,
    this.rawLogLine,
    this.confidence = ConfidenceLevel.verified,
    this.matchedVia,
    this.shownBecause,
    this.dnsRecordType,
    this.backfilled = false,
    List<ConnectionIssue>? issues,
    this.extra,
  }) : issues = issues ?? <ConnectionIssue>[];

  final DateTime ts;
  final TrafficEventKind kind;
  final String? domain;
  final List<String> cnameChain;
  final String? ip;
  final int? port;




  final List<String> outboundChain;




  final List<String> detourChain;





  final String? outboundType;
  final int? upBytes;
  final int? downBytes;
  final Duration? duration;
  final String? connId;
  final String? process;






  final bool processInferred;
  final String? network;
  final String? rule;
  final String? rulePayload;





  final String? rawLogLine;




  final ConfidenceLevel confidence;




  final String? matchedVia;



  final String? shownBecause;




  final String? dnsRecordType;




  final bool backfilled;

  final List<ConnectionIssue> issues;
  final Map<String, Object?>? extra;









  String get routingLine => routingLineOf();




  String routingLineOf({bool compact = false}) {
    final sb = StringBuffer();

    final inner = <String>[];
    if (!compact && process != null && process!.isNotEmpty) inner.add(process!);
    final ruleText = (rule != null && rule!.isNotEmpty) ? rule! : 'final';
    inner.add(!compact && network != null && network!.isNotEmpty
        ? '[$network] $ruleText'
        : ruleText);
    if (outboundChain.length > 1) {

      inner.addAll(outboundChain.sublist(1).reversed);
    }
    sb.write(inner.join(' ⇒ '));






    final phys = <String>[...foldSelectorPairs(detourChain).reversed];
    if (outboundChain.isNotEmpty) {
      var exit = outboundChain.first;
      for (final sel in outboundChain.skip(1)) {
        exit = '$sel ($exit)';
      }
      phys.add(exit);
    }
    final dest = (domain != null && domain!.isNotEmpty)
        ? domain
        : (ip != null && ip!.isNotEmpty ? ip : null);
    if (dest != null) phys.add(dest);
    if (phys.isNotEmpty) sb.write(' : ${phys.join(' → ')}');

    if (duration != null) sb.write(' · ${_fmtDuration(duration!)}');
    return sb.toString();
  }



  static String _fmtDuration(Duration d) {
    if (d.inMilliseconds < 1000) return '${d.inMilliseconds}ms';
    return formatDuration(d);
  }

  Map<String, Object?> toJson() => {
        'ts': ts.toUtc().toIso8601String(),
        'kind': kind.name,
        if (domain != null) 'domain': domain,
        if (cnameChain.isNotEmpty) 'cname_chain': cnameChain,
        if (ip != null) 'ip': ip,
        if (port != null) 'port': port,
        if (outboundChain.isNotEmpty) 'outbound_chain': outboundChain,
        if (detourChain.isNotEmpty) 'detour_chain': detourChain,
        if (upBytes != null) 'up_bytes': upBytes,
        if (downBytes != null) 'down_bytes': downBytes,
        if (duration != null) 'duration_ms': duration!.inMilliseconds,
        if (connId != null) 'conn_id': connId,
        if (process != null) 'process': process,
        if (processInferred) 'process_inferred': true,
        if (network != null) 'network': network,
        if (rule != null) 'rule': rule,
        if (rulePayload != null) 'rule_payload': rulePayload,


        'confidence': confidence.name,
        if (matchedVia != null) 'matched_via': matchedVia,
        if (shownBecause != null) 'shown_because': shownBecause,
        if (dnsRecordType != null) 'dns_record_type': dnsRecordType,
        if (backfilled) 'backfilled': true,
        if (issues.isNotEmpty)
          'issues': issues.map((a) => a.toJson()).toList(),




        if (extra != null && extra!.isNotEmpty) 'extra': extra,
      };





  TrafficEvent copyWith({
    ConfidenceLevel? confidence,
    String? matchedVia,
    bool? backfilled,
    List<ConnectionIssue>? issues,
  }) =>
      TrafficEvent(
        ts: ts,
        kind: kind,
        domain: domain,
        cnameChain: cnameChain,
        ip: ip,
        port: port,
        outboundChain: outboundChain,
        detourChain: detourChain,
        outboundType: outboundType,
        upBytes: upBytes,
        downBytes: downBytes,
        duration: duration,
        connId: connId,
        process: process,
        processInferred: processInferred,
        network: network,
        rule: rule,
        rulePayload: rulePayload,
        rawLogLine: rawLogLine,
        confidence: confidence ?? this.confidence,
        matchedVia: matchedVia ?? this.matchedVia,
        shownBecause: shownBecause,
        dnsRecordType: dnsRecordType,
        backfilled: backfilled ?? this.backfilled,
        issues: issues ?? this.issues,
        extra: extra,
      );
}

class DomainStats {
  DomainStats(this.domain);
  final String domain;
  int connections = 0;
  int upBytes = 0;
  int downBytes = 0;
  DateTime? firstSeen;
  DateTime? lastSeen;
  final Set<String> ips = <String>{};
  final Set<String> cnameTargets = <String>{};
  final Set<String> outbounds = <String>{};
  final List<ConnectionIssue> issues = <ConnectionIssue>[];

  Map<String, Object?> toJson() => {
        'domain': domain,
        'connections': connections,
        'up_bytes': upBytes,
        'down_bytes': downBytes,
        'first_seen': firstSeen?.toUtc().toIso8601String(),
        'last_seen': lastSeen?.toUtc().toIso8601String(),
        'ips': ips.toList(),
        'cname_targets': cnameTargets.toList(),
        'outbounds': outbounds.toList(),
        if (issues.isNotEmpty)
          'issues': issues.map((a) => a.toJson()).toList(),
      };
}

class IpStats {
  IpStats(this.ip);
  final String ip;
  final Set<int> ports = <int>{};
  int connections = 0;
  int upBytes = 0;
  int downBytes = 0;
  DateTime? firstSeen;
  DateTime? lastSeen;
  final Set<String> outbounds = <String>{};

  Map<String, Object?> toJson() => {
        'ip': ip,
        'ports': ports.toList()..sort(),
        'connections': connections,
        'up_bytes': upBytes,
        'down_bytes': downBytes,
        'first_seen': firstSeen?.toUtc().toIso8601String(),
        'last_seen': lastSeen?.toUtc().toIso8601String(),
        'outbounds': outbounds.toList(),
      };
}

