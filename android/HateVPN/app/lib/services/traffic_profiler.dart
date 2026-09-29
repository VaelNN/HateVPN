









































import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../vpn/cc_channel.dart';
import 'app_log.dart';
import 'dns_health_detector.dart';
import 'format_utils.dart';
import 'selector_info.dart';
import 'settings_storage.dart';

part 'traffic_profiler/models.dart';
part 'traffic_profiler/internal.dart';





class TrafficProfiler extends ChangeNotifier {
  TrafficProfiler._();
  static final TrafficProfiler I = TrafficProfiler._();




  static const Duration _connIdGcInterval = Duration(seconds: 15);





  Duration _globalRollingWindow =
      Duration(seconds: SettingsStorage.profilerRetentionDefaultSec);
  static const int _globalRollingHardCap = 20000;


  Duration get retention => _globalRollingWindow;



  Future<void> loadRetention() async {
    final sec = await SettingsStorage.getProfilerRetentionSec();
    _globalRollingWindow = Duration(seconds: sec);
  }



  Future<void> setRetention(Duration window) async {
    if (window == _globalRollingWindow) return;
    _globalRollingWindow = window;
    await SettingsStorage.setProfilerRetentionSec(window.inSeconds);
    notifyListeners();
  }

  static const int _unattributedBannerThreshold = 5;
  static const Duration _unattributedBannerWindow = Duration(seconds: 30);




  final CcChannel _cc = CcChannel.instance;
  StreamSubscription<List<CcConnection>>? _ccConnSub;
  StreamSubscription<List<CcDnsQuery>>? _ccDnsSub;





  final List<StreamController<Map<String, Object?>>> _globalStreamSinks =
      <StreamController<Map<String, Object?>>>[];









  final ListQueue<TrafficEvent> _globalRollingBuffer =
      ListQueue<TrafficEvent>();



  bool _globalRecordingActive = false;
  DateTime? _globalRecordingStartedAt;




  final ListQueue<TrafficEvent> _globalUnattributedEvents =
      ListQueue<TrafficEvent>();
  static const int _globalUnattributedCap = 50;





  Timer? _gcTimer;







  final Map<String, _ConnSnapshot> _connSnapshots = <String, _ConnSnapshot>{};







  final Map<String, DateTime> _closedHandled = <String, DateTime>{};




  List<TrafficEvent> get globalRollingBuffer =>
      List.unmodifiable(_globalRollingBuffer);


  bool get isGlobalRecording => _globalRecordingActive;
  DateTime? get globalRecordingStartedAt => _globalRecordingStartedAt;






  void startGlobalRecording() {
    if (_globalRecordingActive) return;
    _globalRecordingActive = true;
    _globalRecordingStartedAt = DateTime.now();


    _globalRollingBuffer.clear();
    _globalUnattributedEvents.clear();
    _ensureGcTimerStarted();



    _attachCcConnections();
    AppLog.I.info('TrafficProfiler: global recording started');
    notifyListeners();
  }






  void stopGlobalRecording() {
    if (!_globalRecordingActive) return;
    _globalRecordingActive = false;
    _globalRecordingStartedAt = null;
    _maybeStopGcTimer();
    _maybeDetachCcConnections();
    AppLog.I.info('TrafficProfiler: global recording stopped');
    notifyListeners();
  }



  List<TrafficEvent> get globalUnattributedEvents =>
      List.unmodifiable(_globalUnattributedEvents);







  int get recentUnattributedCount {
    final cutoff = DateTime.now().subtract(_unattributedBannerWindow);
    var n = 0;
    for (final e in _globalUnattributedEvents) {
      if (!e.ts.isAfter(cutoff)) continue;
      if (!_isBannerWorthy(e)) continue;
      n++;
    }
    return n;
  }





  bool _isBannerWorthy(TrafficEvent e) {
    if (e.kind == TrafficEventKind.dnsFail) return true;
    if ((e.kind == TrafficEventKind.tcpOpen ||
            e.kind == TrafficEventKind.udpOpen) &&
        (e.process == null || e.process!.isEmpty)) {
      return true;
    }
    return false;
  }

  bool get unattributedBannerActive =>
      recentUnattributedCount > _unattributedBannerThreshold;






  DnsHealthStats _computeDnsHealth() {
    final now = DateTime.now();
    final stats = DnsHealthStats();
    for (final e in _globalRollingBuffer) {
      final ageMs = now.difference(e.ts).inMilliseconds;
      if (ageMs > kDnsHealthWindow.inMilliseconds) continue;
      final kind = switch (e.kind) {
        TrafficEventKind.dnsResolve => DnsHealthEventKind.dnsResolve,
        TrafficEventKind.dnsFail => DnsHealthEventKind.dnsFail,
        TrafficEventKind.tcpOpen ||
        TrafficEventKind.udpOpen ||
        TrafficEventKind.tcpClose =>
          DnsHealthEventKind.connActivity,
      };
      stats.add(DnsHealthSample(kind: kind, ageMs: ageMs));
    }
    return stats;
  }



  bool get dnsHealthUnhealthy => _computeDnsHealth().unhealthy;


  int get dnsHealthFailPercent => (_computeDnsHealth().failRatio * 100).round();








  Stream<Map<String, Object?>> globalLiveStream() {
    late StreamController<Map<String, Object?>> ctrl;
    ctrl = StreamController<Map<String, Object?>>(
      onCancel: () {
        _globalStreamSinks.remove(ctrl);
        if (!ctrl.isClosed) ctrl.close();
      },
    );
    _globalStreamSinks.add(ctrl);
    return ctrl.stream;
  }



  List<TrafficEvent> globalSnapshot({int seconds = 60}) {
    final cutoff =
        DateTime.now().subtract(Duration(seconds: seconds.clamp(1, 600)));
    return _globalRollingBuffer
        .where((e) => e.ts.isAfter(cutoff))
        .toList(growable: false);
  }

  void _emitGlobalStream(Map<String, Object?> event) {
    if (_globalStreamSinks.isEmpty) return;
    for (final c in List.of(_globalStreamSinks)) {
      if (!c.isClosed) c.add(event);
    }
  }








  void _ensureGcTimerStarted() {
    _gcTimer ??= Timer.periodic(_connIdGcInterval, (_) => _gcStaleConnIds());
  }

  void _maybeStopGcTimer() {
    if (_globalRecordingActive) return;
    _gcTimer?.cancel();
    _gcTimer = null;
  }




  void _gcStaleConnIds() {
    final now = DateTime.now();


    final closedCutoff = now.subtract(const Duration(minutes: 5));
    _closedHandled.removeWhere((_, ts) => ts.isBefore(closedCutoff));


    final globalCutoff = now.subtract(_globalRollingWindow);
    var trimmed = false;
    while (_globalRollingBuffer.isNotEmpty &&
        _globalRollingBuffer.first.ts.isBefore(globalCutoff)) {
      _globalRollingBuffer.removeFirst();
      trimmed = true;
    }


    while (_globalUnattributedEvents.isNotEmpty &&
        _globalUnattributedEvents.first.ts.isBefore(globalCutoff)) {
      _globalUnattributedEvents.removeFirst();
      trimmed = true;
    }






    if (trimmed) notifyListeners();
  }





  static String _qtypeToString(int qtype) {
    switch (qtype) {
      case 1:
        return 'A';
      case 28:
        return 'AAAA';
      case 5:
        return 'CNAME';
      case 65:
        return 'HTTPS';
      case 64:
        return 'SVCB';
      case 6:
        return 'SOA';
      case 15:
        return 'MX';
      case 16:
        return 'TXT';
      case 12:
        return 'PTR';
      case 33:
        return 'SRV';
      case 2:
        return 'NS';
      default:
        return 'TYPE$qtype';
    }
  }





  static String _rdataValue(String rdata) {
    final s = rdata.trim();
    if (s.isEmpty) return s;
    final lastSpace = s.lastIndexOf(' ');
    final value = lastSpace >= 0 ? s.substring(lastSpace + 1) : s;
    return value.endsWith('.') ? value.substring(0, value.length - 1) : value;
  }





  void _ingestDnsQueries(List<CcDnsQuery> queries) {

    if (!_globalRecordingActive) return;
    final now = DateTime.now();
    for (final q in queries) {
      _ingestDnsQuery(q, now);
    }
  }

  void _ingestDnsQuery(CcDnsQuery q, DateTime ts) {

    final attributed = q.packageName.isNotEmpty;
    final process = attributed ? q.packageName : null;
    final recordType = _qtypeToString(q.queryType);



    if (q.failed) {
      final reason = q.error.isNotEmpty
          ? q.error
          : (q.noAnswer ? 'no response' : 'rcode ${q.rcode}');

      final failExtra = <String, Object?>{};
      if (q.dnsServer.isNotEmpty) failExtra['dns_server'] = q.dnsServer;
      if (q.dnsServerType.isNotEmpty) {
        failExtra['dns_server_type'] = q.dnsServerType;
      }
      if (q.source.isNotEmpty) failExtra['source'] = q.source;


      _addDnsGroupTrace(failExtra, q);
      _routeEvent(TrafficEvent(
        ts: ts,
        kind: TrafficEventKind.dnsFail,
        domain: q.domain.isNotEmpty ? q.domain : null,
        process: process,
        outboundChain: q.outbound,
        dnsRecordType: recordType,
        confidence:
            attributed ? ConfidenceLevel.verified : ConfidenceLevel.unattributed,
        matchedVia: attributed ? 'dns_stream' : null,
        shownBecause: attributed
            ? null
            : 'system-wide DNS failure (no owner package detected)',
        issues: [
          ConnectionIssue(
              ConnectionIssueKind.dnsTimeout, 'DNS exchange failed: $reason'),
        ],
        extra: failExtra.isEmpty ? null : failExtra,
      ));
      return;
    }








    final cnameChain = <String>[];
    final addresses = <String>[];
    for (final a in q.answers) {
      if (a.isCname) {
        cnameChain.add(_rdataValue(a.rdata));
      } else if (a.isAddress) {
        addresses.add(_rdataValue(a.rdata));
      }
    }
    final ip = addresses.isNotEmpty ? addresses.first : null;




    final outboundChain = q.outbound;



    final extra = <String, Object?>{};
    if (q.dnsServer.isNotEmpty) extra['dns_server'] = q.dnsServer;
    if (q.dnsServerType.isNotEmpty) extra['dns_server_type'] = q.dnsServerType;
    if (q.source.isNotEmpty) extra['source'] = q.source;
    if (ip == null && q.answers.isNotEmpty) {
      extra['answer'] = _rdataValue(q.answers.first.rdata);
    }
    _addDnsGroupTrace(extra, q);

    _routeEvent(TrafficEvent(
      ts: ts,
      kind: TrafficEventKind.dnsResolve,
      domain: q.domain,
      cnameChain: cnameChain,
      ip: ip,
      process: process,
      outboundChain: outboundChain,
      dnsRecordType: recordType,
      confidence:
          attributed ? ConfidenceLevel.verified : ConfidenceLevel.unattributed,
      matchedVia: attributed ? 'dns_stream' : null,
      extra: extra.isEmpty ? null : extra,
    ));
  }











  static void _addDnsGroupTrace(Map<String, Object?> extra, CcDnsQuery q) {
    if (q.groupPath.isNotEmpty) {
      extra['dns_group_path'] = q.groupPath.join(' → ');
    }
    if (q.attempts.isNotEmpty) {
      extra['dns_attempts'] = [
        for (final a in q.attempts)
          '${a.server} ${a.outcome}${a.rttMs > 0 ? ' ${a.rttMs}ms' : ''}',
      ].join(' · ');
    }
    if (q.fanned) extra['dns_fanned'] = 'true';
    if (q.survival) extra['dns_survival'] = 'true';
  }








  void _routeEvent(TrafficEvent ev) {

    _appendToGlobalRollingBuffer(ev);


    if (ev.confidence == ConfidenceLevel.unattributed) {
      _appendToGlobalUnattributed(ev);
    }

    _emitGlobalStream({'event': 'traffic_event', 'data': ev.toJson()});
  }

  void _appendToGlobalRollingBuffer(TrafficEvent ev) {
    _globalRollingBuffer.addLast(ev);


    while (_globalRollingBuffer.length > _globalRollingHardCap) {
      _globalRollingBuffer.removeFirst();
    }
  }

  void _appendToGlobalUnattributed(TrafficEvent ev) {
    _globalUnattributedEvents.addLast(ev);
    while (_globalUnattributedEvents.length > _globalUnattributedCap) {
      _globalUnattributedEvents.removeFirst();
    }
  }









  void _attachCcConnections() {
    if (_ccConnSub != null) return;



    unawaited(_cc.acquireProfiler());
    _ccConnSub = _cc.connections.listen(
      _ingestCcConnections,


      onError: (Object e, StackTrace _) =>
          AppLog.I.warning('TrafficProfiler: cc connections stream error: $e'),
    );


    _ccDnsSub = _cc.dnsQueries.listen(
      _ingestDnsQueries,
      onError: (Object e, StackTrace _) =>
          AppLog.I.warning('TrafficProfiler: cc dns stream error: $e'),
    );
  }



  void _maybeDetachCcConnections() {
    if (_globalRecordingActive) return;
    _detachCcConnections();
  }

  void _detachCcConnections() {
    _ccConnSub?.cancel();
    _ccConnSub = null;
    _ccDnsSub?.cancel();
    _ccDnsSub = null;
    unawaited(_cc.releaseProfiler());
  }





  void _ingestCcConnections(List<CcConnection> conns) {

    if (!_globalRecordingActive) return;
    final now = DateTime.now();

    final seenIds = <String>{};
    for (final c in conns) {
      final id = c.id;
      if (id.isEmpty) continue;



      if (c.isClosed) {
        if (_closedHandled.containsKey(id)) continue;
        _closedHandled[id] = now;




      } else {
        seenIds.add(id);
      }


      final process = c.packageName;
      final processPath = c.processPath;
      final rawProcess = process.isNotEmpty ? process : processPath;


      final host = c.domain;
      final destIp = _ccHostOf(c.destination);
      final destPort = _ccPortOf(c.destination);
      final network = c.network;





      final routeChain = c.chains.isNotEmpty
          ? c.chains
          : (c.outbound.isNotEmpty ? <String>[c.outbound] : <String>[]);
      final detourChain = c.detours;
      final up = c.uplink;
      final down = c.downlink;
      final rule = c.rule;


      const rulePayload = '';

      final prev = _connSnapshots[id];
      if (prev == null) {

        final kind = network == 'udp'
            ? TrafficEventKind.udpOpen
            : TrafficEventKind.tcpOpen;

        final hasProcess = rawProcess.isNotEmpty;
        final globalEv = TrafficEvent(
          ts: now,
          kind: kind,
          domain: host.isNotEmpty ? host : null,
          ip: destIp.isNotEmpty ? destIp : null,
          port: destPort > 0 ? destPort : null,
          outboundChain: routeChain,
          detourChain: detourChain,
          outboundType: c.outboundType.isNotEmpty ? c.outboundType : null,
          upBytes: up,
          downBytes: down,
          process: hasProcess ? rawProcess : null,
          network: network,
          rule: rule.isNotEmpty ? rule : null,
          rulePayload: rulePayload.isNotEmpty ? rulePayload : null,
          confidence: hasProcess
              ? ConfidenceLevel.verified
              : ConfidenceLevel.unattributed,
          matchedVia: hasProcess ? 'connections_meta' : null,
        );
        _appendToGlobalRollingBuffer(globalEv);
        _emitGlobalStream(
            {'event': 'traffic_event', 'data': globalEv.toJson()});








        _connSnapshots[id] = _ConnSnapshot(
          id: id,
          host: host,
          ip: destIp,
          port: destPort,
          network: network,
          chains: routeChain,
          detours: detourChain,
          outboundType: c.outboundType.isNotEmpty ? c.outboundType : null,
          upBytes: up,
          downBytes: down,
          startedAt: _kernelTime(c.createdAt) ?? now,
          process: globalEv.process ?? '',
          confidence: globalEv.confidence,
          matchedVia: globalEv.matchedVia,
          rule: rule,
          rulePayload: rulePayload,
        );
      } else {

        prev.upBytes = up;
        prev.downBytes = down;
      }


      if (c.isClosed) {
        final kernelClosed = _kernelTime(c.closedAt);
        if (kernelClosed != null) {
          _connSnapshots[id]?.kernelClosedAt = kernelClosed;
        }
      }
    }



    final closed =
        _connSnapshots.keys.where((k) => !seenIds.contains(k)).toList();
    for (final id in closed) {
      final snap = _connSnapshots.remove(id);
      if (snap == null) continue;




      final closeTs = snap.kernelClosedAt ?? now;
      final dur = closeTs.difference(snap.startedAt);
      final closeEv = TrafficEvent(
        ts: closeTs,
        kind: TrafficEventKind.tcpClose,
        domain: snap.host.isNotEmpty ? snap.host : null,
        ip: snap.ip.isNotEmpty ? snap.ip : null,
        port: snap.port > 0 ? snap.port : null,
        outboundChain: snap.chains,
        detourChain: snap.detours,
        outboundType: snap.outboundType,
        upBytes: snap.upBytes,
        downBytes: snap.downBytes,
        duration: dur.isNegative ? Duration.zero : dur,
        process: snap.process.isEmpty ? null : snap.process,
        processInferred: snap.confidence == ConfidenceLevel.inferred,
        network: snap.network,
        rule: snap.rule.isEmpty ? null : snap.rule,
        rulePayload: snap.rulePayload.isEmpty ? null : snap.rulePayload,
        confidence: snap.confidence,
        matchedVia: snap.matchedVia,
        issues: _classifyConnectionClose(snap, closeTs),
      );


      _appendToGlobalRollingBuffer(closeEv);
      _emitGlobalStream({'event': 'traffic_event', 'data': closeEv.toJson()});
    }
  }




  static DateTime? _kernelTime(int epochMs) => epochMs > 946684800000
      ? DateTime.fromMillisecondsSinceEpoch(epochMs)
      : null;



  static String _ccHostOf(String destination) {
    final i = destination.lastIndexOf(':');
    return i < 0 ? destination : destination.substring(0, i);
  }


  static int _ccPortOf(String destination) {
    final i = destination.lastIndexOf(':');
    if (i < 0 || i == destination.length - 1) return 0;
    return int.tryParse(destination.substring(i + 1)) ?? 0;
  }















  List<ConnectionIssue> _classifyConnectionClose(
      _ConnSnapshot snap, DateTime closedAt) {
    final out = <ConnectionIssue>[];
    if (snap.network == 'tcp') {
      final dur = closedAt.difference(snap.startedAt);


      if (dur.isNegative) return out;
      if (dur.inMilliseconds < 1000 &&
          snap.upBytes == 0 &&
          snap.downBytes == 0) {
        out.add(const ConnectionIssue(
          ConnectionIssueKind.tcpReset,
          'Connection closed within 1s without bytes (likely RST / blocked)',
        ));
      }
    }
    return out;
  }



  @visibleForTesting
  void resetForTesting() {
    _connSnapshots.clear();
    _closedHandled.clear();
    _globalRollingBuffer.clear();
    _globalUnattributedEvents.clear();
    _globalRecordingActive = false;
    _globalRecordingStartedAt = null;
    _ccConnSub?.cancel();
    _ccConnSub = null;
    _ccDnsSub?.cancel();
    _ccDnsSub = null;
    _gcTimer?.cancel();
    _gcTimer = null;
    for (final c in _globalStreamSinks) {
      if (!c.isClosed) c.close();
    }
    _globalStreamSinks.clear();
  }


  @visibleForTesting
  void ingestForTest(List<CcConnection> conns) => _ingestCcConnections(conns);


  @visibleForTesting
  void ingestDnsForTest(List<CcDnsQuery> queries) => _ingestDnsQueries(queries);

  @visibleForTesting
  void gcOnceForTest() => _gcStaleConnIds();
}
