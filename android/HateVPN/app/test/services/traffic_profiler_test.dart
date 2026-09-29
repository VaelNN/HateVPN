

import 'package:flutter_test/flutter_test.dart';

import 'package:lxbox/services/traffic_profiler.dart';
import 'package:lxbox/vpn/cc_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TrafficProfiler.I.resetForTesting();
  });



  group('TrafficProfiler — DNS parsing (global buffer)', () {
    test('DNS chain attribution: CNAME-hops в answers, ip = финальный A',
        () async {
      TrafficProfiler.I.startGlobalRecording();


      TrafficProfiler.I.ingestDnsForTest([
        const CcDnsQuery(
          domain: 'cdn.t-bank-app.ru',
          queryType: 1,
          rcode: 0,
          packageName: 'ru.tinkoff.investing',
          answers: [
            CcDnsAnswer(
                name: 'cdn.t-bank-app.ru',
                type: 5,
                rdata: 'cl-ead2c819.edgecdn.ru'),
            CcDnsAnswer(
                name: 'cl-ead2c819.edgecdn.ru', type: 1, rdata: '193.17.93.194'),
          ],
        ),
      ]);
      final resolves = TrafficProfiler.I.globalRollingBuffer
          .where((e) => e.kind == TrafficEventKind.dnsResolve)
          .toList();
      expect(resolves, hasLength(1));



      expect(resolves.first.domain, 'cdn.t-bank-app.ru');
      expect(resolves.first.ip, '193.17.93.194');
      expect(resolves.first.cnameChain, ['cl-ead2c819.edgecdn.ru']);
      expect(resolves.first.process, 'ru.tinkoff.investing');
      expect(resolves.first.confidence, ConfidenceLevel.verified);
    });

    test('§180-fix — ядро шлёт rdata ПОЛНОЙ RR-строкой → берём значение',
        () async {


      TrafficProfiler.I.startGlobalRecording();
      TrafficProfiler.I.ingestDnsForTest([
        const CcDnsQuery(
          domain: 'google.com',
          queryType: 1,
          rcode: 0,
          packageName: 'ru.tinkoff.investing',
          answers: [
            CcDnsAnswer(
                name: 'yt3.ggpht.com',
                type: 5,
                rdata: 'yt3.ggpht.com. 204 IN CNAME wide-youtube.l.google.com.'),
            CcDnsAnswer(
                name: 'google.com',
                type: 1,
                rdata: 'google.com. 29 IN A 64.233.165.139'),
          ],
        ),
      ]);
      final ev = TrafficProfiler.I.globalRollingBuffer
          .firstWhere((e) => e.kind == TrafficEventKind.dnsResolve);
      expect(ev.ip, '64.233.165.139', reason: 'A: последнее поле, не вся строка');
      expect(ev.cnameChain, ['wide-youtube.l.google.com'],
          reason: 'CNAME: target без trailing dot');
    });

    test('DNS fail produces dnsTimeout issue', () async {
      TrafficProfiler.I.startGlobalRecording();

      TrafficProfiler.I.ingestDnsForTest([
        const CcDnsQuery(
          domain: 'some.host',
          queryType: 1,
          rcode: -1,
          failed: true,
          error: 'context deadline exceeded',
          packageName: 'ru.tinkoff.investing',
        ),
      ]);
      final ev = TrafficProfiler.I.globalRollingBuffer.last;
      expect(ev.kind, TrafficEventKind.dnsFail);
      expect(ev.issues.first.kind, ConnectionIssueKind.dnsTimeout);
    });

    test('rc.10 — dnsServer/dnsServerType/outbound пробрасываются', () async {
      TrafficProfiler.I.startGlobalRecording();
      TrafficProfiler.I.ingestDnsForTest([
        const CcDnsQuery(
          domain: 'github.com',
          queryType: 1,
          rcode: 0,
          packageName: 'ru.tinkoff.investing',
          dnsServer: 'https://1.1.1.1/dns-query',
          dnsServerType: 'https',
          outbound: ['🇫🇮Финляндия (vpn-1)'],
          answers: [
            CcDnsAnswer(name: 'github.com', type: 1, rdata: '140.82.121.3'),
          ],
        ),
      ]);
      final ev = TrafficProfiler.I.globalRollingBuffer
          .firstWhere((e) => e.kind == TrafficEventKind.dnsResolve);

      expect(ev.outboundChain, ['🇫🇮Финляндия (vpn-1)']);

      expect(ev.extra?['dns_server'], 'https://1.1.1.1/dns-query');
      expect(ev.extra?['dns_server_type'], 'https');
    });

    test('rc.10 — cached (пустой outbound) → outboundChain пуст', () async {
      TrafficProfiler.I.startGlobalRecording();
      TrafficProfiler.I.ingestDnsForTest([
        const CcDnsQuery(
          domain: 'cached.example',
          queryType: 1,
          rcode: 0,
          source: 'cached',
          packageName: 'ru.tinkoff.investing',

          answers: [
            CcDnsAnswer(name: 'cached.example', type: 1, rdata: '1.2.3.4'),
          ],
        ),
      ]);
      final ev = TrafficProfiler.I.globalRollingBuffer
          .firstWhere((e) => e.kind == TrafficEventKind.dnsResolve);
      expect(ev.outboundChain, isEmpty);
    });

    test('multi-package UID `com.x.y, com.x.z` → verified (process известен)',
        () async {
      TrafficProfiler.I.startGlobalRecording();


      TrafficProfiler.I.ingestDnsForTest([
        const CcDnsQuery(
          domain: 'play.google.com',
          queryType: 1,
          rcode: 0,
          packageName: 'com.google.android.gms, com.google.android.gsf',
          answers: [
            CcDnsAnswer(name: 'play.google.com', type: 1, rdata: '1.2.3.4'),
          ],
        ),
      ]);
      final dns = TrafficProfiler.I.globalRollingBuffer
          .firstWhere((e) => e.kind == TrafficEventKind.dnsResolve);
      expect(dns.confidence, ConfidenceLevel.verified);
      expect(dns.domain, 'play.google.com');
    });
  });



  group('TrafficProfiler — §048 DNS record-type semantics', () {
    test('HTTPS record DNS resolve is parsed with record_type=HTTPS', () async {
      TrafficProfiler.I.startGlobalRecording();

      TrafficProfiler.I.ingestDnsForTest([
        const CcDnsQuery(
          domain: 'example.com',
          queryType: 65,
          rcode: 0,
          packageName: 'com.android.chrome',
          answers: [
            CcDnsAnswer(
                name: 'example.com', type: 65, rdata: '1 . alpn=h2,h3'),
          ],
        ),
      ]);
      final dnsEvents = TrafficProfiler.I.globalRollingBuffer
          .where((e) => e.kind == TrafficEventKind.dnsResolve)
          .toList();
      expect(dnsEvents, hasLength(1));
      expect(dnsEvents.first.dnsRecordType, 'HTTPS');
      expect(dnsEvents.first.confidence, ConfidenceLevel.verified);
    });

    test('SVCB record DNS resolve is parsed', () async {
      TrafficProfiler.I.startGlobalRecording();
      TrafficProfiler.I.ingestDnsForTest([
        const CcDnsQuery(
          domain: '_dns.example.com',
          queryType: 64,
          rcode: 0,
          packageName: 'com.android.chrome',
          answers: [
            CcDnsAnswer(
                name: '_dns.example.com', type: 64, rdata: '1 . alpn=h2'),
          ],
        ),
      ]);
      final ev = TrafficProfiler.I.globalRollingBuffer
          .firstWhere((e) => e.kind == TrafficEventKind.dnsResolve);
      expect(ev.dnsRecordType, 'SVCB');
    });

    test('SOA record (NXDOMAIN) is parsed without IP', () async {
      TrafficProfiler.I.startGlobalRecording();

      TrafficProfiler.I.ingestDnsForTest([
        const CcDnsQuery(
          domain: 'missing.example',
          queryType: 6,
          rcode: 3,
          source: 'cached',
          packageName: 'com.android.chrome',
          answers: [
            CcDnsAnswer(
                name: 'missing.example', type: 6, rdata: 'ns1.example.com.'),
          ],
        ),
      ]);
      final ev = TrafficProfiler.I.globalRollingBuffer
          .firstWhere((e) => e.kind == TrafficEventKind.dnsResolve);
      expect(ev.dnsRecordType, 'SOA');

      expect(ev.ip, isNull);
    });

    test('DNS fail with HTTPS record type — unattributed if no owner', () async {
      TrafficProfiler.I.startGlobalRecording();

      TrafficProfiler.I.ingestDnsForTest([
        const CcDnsQuery(
          domain: '2ip.io',
          queryType: 65,
          rcode: -1,
          failed: true,
          error: 'context deadline exceeded',

        ),
      ]);

      expect(TrafficProfiler.I.globalUnattributedEvents, isNotEmpty);
      final ev = TrafficProfiler.I.globalUnattributedEvents.first;
      expect(ev.kind, TrafficEventKind.dnsFail);
      expect(ev.confidence, ConfidenceLevel.unattributed);
      expect(ev.dnsRecordType, 'HTTPS');
      expect(ev.domain, '2ip.io');
      expect(ev.shownBecause, isNotNull);
    });

    test('DNS fail (attributed) → verified dnsFail with record type', () async {
      TrafficProfiler.I.startGlobalRecording();

      TrafficProfiler.I.ingestDnsForTest([
        const CcDnsQuery(
          domain: 'example.com',
          queryType: 1,
          rcode: -1,
          failed: true,
          error: 'context deadline exceeded',
          packageName: 'com.android.chrome',
        ),
      ]);
      final fail = TrafficProfiler.I.globalRollingBuffer
          .firstWhere((e) => e.kind == TrafficEventKind.dnsFail);
      expect(fail.confidence, ConfidenceLevel.verified);
      expect(fail.domain, 'example.com');
      expect(fail.dnsRecordType, 'A');
    });
  });



  group('TrafficProfiler — connection ingest (§168 CommandClient)', () {
    test('new tcp conn → tcpOpen event (no issue on open)', () async {
      TrafficProfiler.I.startGlobalRecording();
      TrafficProfiler.I.ingestForTest([
        const CcConnection(
          id: 'c1',
          network: 'tcp',
          domain: 'certs.t-bank-app.ru',
          destination: '81.222.127.186:443',
          rule: 'default',
          uplink: 0,
          downlink: 0,
          outbound: '🇫🇮Финляндия (vpn-1)',
          packageName: 'ru.tinkoff.investing',
          createdAt: 0,
          closedAt: 0,
        ),
      ]);
      final buf = TrafficProfiler.I.globalRollingBuffer;
      expect(buf.length, 1);
      final ev = buf.first;
      expect(ev.kind, TrafficEventKind.tcpOpen);
      expect(ev.domain, 'certs.t-bank-app.ru');
      expect(ev.ip, '81.222.127.186');
      expect(ev.port, 443);
      expect(ev.process, 'ru.tinkoff.investing');
      expect(ev.confidence, ConfidenceLevel.verified);


      expect(ev.issues, isEmpty);
    });

    test('tcp conn without owner → unattributed', () async {
      TrafficProfiler.I.startGlobalRecording();
      TrafficProfiler.I.ingestForTest([
        const CcConnection(
          id: 'noown',
          network: 'tcp',
          domain: 'noowner.example',
          destination: '5.5.5.5:443',
          rule: '',
          uplink: 0,
          downlink: 0,
          outbound: 'direct',

          createdAt: 0,
          closedAt: 0,
        ),
      ]);
      final ev = TrafficProfiler.I.globalRollingBuffer.first;
      expect(ev.confidence, ConfidenceLevel.unattributed);
      expect(ev.process, isNull);
    });

    test('closed connection emits tcpClose with duration', () async {
      TrafficProfiler.I.startGlobalRecording();
      TrafficProfiler.I.ingestForTest([
        const CcConnection(
          id: 'c3',
          network: 'tcp',
          domain: 'cdn.t-bank-app.ru',
          destination: '193.17.93.194:443',
          rule: '',
          uplink: 100,
          downlink: 200,
          outbound: 'direct-out',
          packageName: 'ru.tinkoff.investing',
          createdAt: 0,
          closedAt: 0,
        ),
      ]);

      TrafficProfiler.I.ingestForTest([]);
      final buf = TrafficProfiler.I.globalRollingBuffer;
      expect(buf.length, 2);
      expect(buf.last.kind, TrafficEventKind.tcpClose);
      expect(buf.last.duration, isNotNull);
    });

    test('closed connection via closedAt>0 emits tcpClose (§168)', () async {


      TrafficProfiler.I.startGlobalRecording();
      TrafficProfiler.I.ingestForTest([
        const CcConnection(
          id: 'c4',
          network: 'tcp',
          domain: 'api.t-bank-app.ru',
          destination: '193.17.93.195:443',
          rule: '',
          uplink: 100,
          downlink: 200,
          outbound: 'direct-out',
          packageName: 'ru.tinkoff.investing',
          createdAt: 0,
          closedAt: 0,
        ),
      ]);

      TrafficProfiler.I.ingestForTest([
        const CcConnection(
          id: 'c4',
          network: 'tcp',
          domain: 'api.t-bank-app.ru',
          destination: '193.17.93.195:443',
          rule: '',
          uplink: 100,
          downlink: 200,
          outbound: 'direct-out',
          packageName: 'ru.tinkoff.investing',
          createdAt: 0,
          closedAt: 1,
        ),
      ]);
      expect(TrafficProfiler.I.globalRollingBuffer.last.kind,
          TrafficEventKind.tcpClose);
    });

    test('§176 — короткий conn сразу closedAt>0 → обе фазы (open+close)',
        () async {



      TrafficProfiler.I.startGlobalRecording();
      TrafficProfiler.I.ingestForTest([
        const CcConnection(
          id: 'short1',
          network: 'tcp',
          domain: 'short.example',
          destination: '5.6.7.8:443',
          rule: '',
          uplink: 50,
          downlink: 80,
          outbound: 'direct-out',
          packageName: 'ru.tinkoff.investing',
          createdAt: 0,
          closedAt: 1,
        ),
      ]);
      final kinds =
          TrafficProfiler.I.globalRollingBuffer.map((e) => e.kind).toList();
      expect(kinds, contains(TrafficEventKind.tcpOpen),
          reason: 'open не потерян');
      expect(kinds, contains(TrafficEventKind.tcpClose),
          reason: 'close эмитнут');
    });

    test('§353 — kernel-метки: duration от createdAt/closedAt, не от тиков',
        () async {



      TrafficProfiler.I.startGlobalRecording();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      TrafficProfiler.I.ingestForTest([
        CcConnection(
          id: 'k1',
          network: 'tcp',
          domain: 'slowclose.example',
          destination: '9.9.9.9:443',
          rule: '',
          uplink: 0,
          downlink: 0,
          outbound: 'direct-out',
          packageName: 'ru.tinkoff.investing',
          createdAt: nowMs - 5000,
          closedAt: nowMs - 800,
        ),
      ]);
      final close = TrafficProfiler.I.globalRollingBuffer
          .lastWhere((e) => e.kind == TrafficEventKind.tcpClose);
      expect(close.duration, const Duration(milliseconds: 4200),
          reason: 'длительность по часам ядра, детерминированная');
      expect(close.issues, isEmpty,
          reason: '4.2с с 0 байт — НЕ tcpReset (порог 1с)');
    });

    test('§353 — честный быстрый close с kernel-метками даёт tcpReset',
        () async {
      TrafficProfiler.I.startGlobalRecording();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      TrafficProfiler.I.ingestForTest([
        CcConnection(
          id: 'k2',
          network: 'tcp',
          domain: 'fastclose.example',
          destination: '9.9.9.10:443',
          rule: '',
          uplink: 0,
          downlink: 0,
          outbound: 'direct-out',
          packageName: 'ru.tinkoff.investing',
          createdAt: nowMs - 500,
          closedAt: nowMs - 100,
        ),
      ]);
      final close = TrafficProfiler.I.globalRollingBuffer
          .lastWhere((e) => e.kind == TrafficEventKind.tcpClose);
      expect(close.duration, const Duration(milliseconds: 400));
      expect(close.issues, isNotEmpty,
          reason: '400мс с 0 байт — вероятный RST, эвристика остаётся');
    });

    test('§353 — сентинел closedAt=1 не превращается в 1970 год', () async {


      TrafficProfiler.I.startGlobalRecording();
      TrafficProfiler.I.ingestForTest([
        const CcConnection(
          id: 'k3',
          network: 'tcp',
          domain: 'sentinel.example',
          destination: '9.9.9.11:443',
          rule: '',
          uplink: 10,
          downlink: 10,
          outbound: 'direct-out',
          packageName: 'ru.tinkoff.investing',
          createdAt: 0,
          closedAt: 1,
        ),
      ]);
      final close = TrafficProfiler.I.globalRollingBuffer
          .lastWhere((e) => e.kind == TrafficEventKind.tcpClose);
      expect(close.ts.year, greaterThan(2000));
      expect(close.duration, isNotNull);
      expect(close.duration!.isNegative, isFalse);
    });

    test('§176 — тот же closed conn 2 тика → ОДИН close (анти-дубль)', () async {


      TrafficProfiler.I.startGlobalRecording();
      const closedConn = CcConnection(
        id: 'dup1',
        network: 'tcp',
        domain: 'dup.example',
        destination: '9.9.9.9:443',
        rule: '',
        uplink: 10,
        downlink: 20,
        outbound: 'direct-out',
        packageName: 'ru.tinkoff.investing',
        createdAt: 0,
        closedAt: 1,
      );
      TrafficProfiler.I.ingestForTest([closedConn]);
      TrafficProfiler.I.ingestForTest([closedConn]);
      TrafficProfiler.I.ingestForTest([closedConn]);
      final closes = TrafficProfiler.I.globalRollingBuffer
          .where((e) => e.kind == TrafficEventKind.tcpClose)
          .length;
      expect(closes, 1, reason: 'closed обработан ровно раз, не дублируется');
    });

    test('TCP RST early flagged on close (closed <1s, 0 bytes)', () async {
      TrafficProfiler.I.startGlobalRecording();
      TrafficProfiler.I.ingestForTest([
        const CcConnection(
          id: 'rst',
          network: 'tcp',
          domain: 'blocked.example',
          destination: '1.2.3.4:443',
          rule: '',
          uplink: 0,
          downlink: 0,
          outbound: 'direct-out',
          packageName: 'ru.tinkoff.investing',
          createdAt: 0,
          closedAt: 0,
        ),
      ]);

      TrafficProfiler.I.ingestForTest([]);
      final closeEvent = TrafficProfiler.I.globalRollingBuffer.last;
      expect(closeEvent.kind, TrafficEventKind.tcpClose);
      expect(
          closeEvent.issues.any((a) => a.kind == ConnectionIssueKind.tcpReset),
          true);
    });

    test('UID-suffixed package name (com.x (10999)) → verified', () async {
      TrafficProfiler.I.startGlobalRecording();

      TrafficProfiler.I.ingestForTest([
        const CcConnection(
          id: 'c1',
          network: 'tcp',
          domain: 'www.google.com',
          destination: '1.2.3.4:443',
          rule: '',
          uplink: 0,
          downlink: 0,
          outbound: 'direct',
          packageName: 'com.android.chrome (10999)',
          createdAt: 0,
          closedAt: 0,
        ),
      ]);
      final buf = TrafficProfiler.I.globalRollingBuffer;
      expect(buf, isNotEmpty);
      expect(buf.first.kind, TrafficEventKind.tcpOpen);
      expect(buf.first.confidence, ConfidenceLevel.verified);
    });
  });



  group('TrafficProfiler — §048 Live system-wide buffer', () {
    test('globalSnapshot returns events for all apps', () async {
      final sub = TrafficProfiler.I.globalLiveStream().listen((_) {});
      TrafficProfiler.I.startGlobalRecording();

      TrafficProfiler.I.ingestDnsForTest([
        const CcDnsQuery(
          domain: 'a.example',
          queryType: 1,
          rcode: 0,
          packageName: 'com.app.a',
          answers: [CcDnsAnswer(name: 'a.example', type: 1, rdata: '1.1.1.1')],
        ),
        const CcDnsQuery(
          domain: 'b.example',
          queryType: 1,
          rcode: 0,
          packageName: 'com.app.b',
          answers: [CcDnsAnswer(name: 'b.example', type: 1, rdata: '2.2.2.2')],
        ),
      ]);
      final snap = TrafficProfiler.I.globalSnapshot();

      final apps = snap
          .map((e) => e.process)
          .where((p) => p != null)
          .toSet();
      expect(apps.contains('com.app.a'), true);
      expect(apps.contains('com.app.b'), true);
      TrafficProfiler.I.stopGlobalRecording();
      await sub.cancel();
    });

    test('unattributedBannerActive flips when many unattributed events arrive',
        () async {
      final sub = TrafficProfiler.I.globalLiveStream().listen((_) {});
      TrafficProfiler.I.startGlobalRecording();


      TrafficProfiler.I.ingestDnsForTest([
        for (var i = 0; i < 10; i++)
          CcDnsQuery(
            domain: 'x$i.test',
            queryType: 1,
            rcode: -1,
            failed: true,
            error: 'timeout',
          ),
      ]);
      expect(TrafficProfiler.I.recentUnattributedCount, greaterThanOrEqualTo(6));
      expect(TrafficProfiler.I.unattributedBannerActive, true);
      TrafficProfiler.I.stopGlobalRecording();
      await sub.cancel();
    });

    test('§177-A successful unattributed DNS resolves do NOT light the banner',
        () async {
      final sub = TrafficProfiler.I.globalLiveStream().listen((_) {});
      TrafficProfiler.I.startGlobalRecording();


      TrafficProfiler.I.ingestDnsForTest([
        for (var i = 0; i < 12; i++)
          CcDnsQuery(
            domain: 'x$i.test',
            queryType: 1,
            rcode: 0,
            answers: [CcDnsAnswer(name: 'x$i.test', type: 1, rdata: '1.2.3.4')],
          ),
      ]);
      expect(TrafficProfiler.I.recentUnattributedCount, 0,
          reason: 'успешные dnsResolve без владельца — не признак сбоя');
      expect(TrafficProfiler.I.unattributedBannerActive, false);
      TrafficProfiler.I.stopGlobalRecording();
      await sub.cancel();
    });

    test('recording off → events ignored', () async {

      TrafficProfiler.I.ingestDnsForTest([
        const CcDnsQuery(
          domain: 'ignored.example',
          queryType: 1,
          rcode: 0,
          packageName: 'com.app.a',
          answers: [
            CcDnsAnswer(name: 'ignored.example', type: 1, rdata: '1.1.1.1'),
          ],
        ),
      ]);
      expect(TrafficProfiler.I.globalRollingBuffer, isEmpty);
    });
  });



  group('TrafficProfiler — §181 routing axes + routingLine', () {
    test('chains и detours несутся РАЗДЕЛЬНО (не склеены как §178)', () async {
      TrafficProfiler.I.startGlobalRecording();
      TrafficProfiler.I.ingestForTest([
        const CcConnection(
          id: 'd181a',
          network: 'tcp',
          domain: 'www.google.com',
          destination: '1.2.3.4:443',
          rule: 'final',
          uplink: 10,
          downlink: 20,
          outbound: 'BL: [BL]-3',
          chains: ['BL: [BL]-3', 'vpn-1'],
          detours: ['WARP'],
          packageName: 'ru.tinkoff.investing',
          createdAt: 0,
          closedAt: 0,
        ),
      ]);
      final ev = TrafficProfiler.I.globalRollingBuffer.first;
      expect(ev.outboundChain, ['BL: [BL]-3', 'vpn-1'],
          reason: '§181 — outboundChain = только маршрут (БЕЗ detour)');
      expect(ev.detourChain, ['WARP'],
          reason: '§181 — detour в своей оси');
    });

    test(
        'routingLine: полная трассировка [net] proc ⇒ rule ⇒ группа : node → detour → domain',
        () async {
      TrafficProfiler.I.startGlobalRecording();
      TrafficProfiler.I.ingestForTest([
        const CcConnection(
          id: 'd181b',
          network: 'tcp',
          domain: 'play-fe.googleapis.com',
          destination: '74.125.131.102:443',
          rule: '',
          uplink: 10,
          downlink: 0,
          outbound: 'Венгрия',

          chains: ['🇭🇺Венгрия', '✨auto', 'vpn-1'],
          detours: ['WARP'],
          packageName: 'com.android.vending',
          createdAt: 0,
          closedAt: 0,
        ),
      ]);
      final ev = TrafficProfiler.I.globalRollingBuffer.first;

      expect(
        ev.routingLine,
        'com.android.vending ⇒ [tcp] final ⇒ vpn-1 ⇒ ✨auto : WARP → vpn-1 (✨auto (🇭🇺Венгрия)) → play-fe.googleapis.com',
      );


      expect(
        ev.routingLineOf(compact: true),
        'final ⇒ vpn-1 ⇒ ✨auto : WARP → vpn-1 (✨auto (🇭🇺Венгрия)) → play-fe.googleapis.com',
      );
    });

    test('routingLine: с явным rule (не final)', () async {
      TrafficProfiler.I.startGlobalRecording();
      TrafficProfiler.I.ingestForTest([
        const CcConnection(
          id: 'd181c',
          network: 'tcp',
          domain: 'site.ru',
          destination: '5.6.7.8:443',
          rule: 'rule_set=ru-domains',
          uplink: 1,
          downlink: 1,
          outbound: 'direct-out',
          chains: ['direct-out'],
          packageName: 'ru.tinkoff.investing',
          createdAt: 0,
          closedAt: 0,
        ),
      ]);
      final ev = TrafficProfiler.I.globalRollingBuffer.first;

      expect(
        ev.routingLine,
        'ru.tinkoff.investing ⇒ [tcp] rule_set=ru-domains : direct-out → site.ru',
      );
    });

    test('прямой conn (chains пуст) → fallback [outbound], detour пуст', () async {
      TrafficProfiler.I.startGlobalRecording();
      TrafficProfiler.I.ingestForTest([
        const CcConnection(
          id: 'd181d',
          network: 'tcp',
          domain: 'direct.example',
          destination: '9.9.9.9:443',
          rule: '',
          uplink: 5,
          downlink: 5,
          outbound: 'direct-out',

          packageName: 'ru.tinkoff.investing',
          createdAt: 0,
          closedAt: 0,
        ),
      ]);
      final ev = TrafficProfiler.I.globalRollingBuffer.first;
      expect(ev.outboundChain, ['direct-out'],
          reason: 'fallback на [outbound]');
      expect(ev.detourChain, isEmpty);
    });
  });
}
