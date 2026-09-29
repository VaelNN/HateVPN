import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/services/dns_health_detector.dart';




DnsHealthSample _dns(bool failed, {int ageMs = 0}) => DnsHealthSample(
    kind: failed ? DnsHealthEventKind.dnsFail : DnsHealthEventKind.dnsResolve,
    ageMs: ageMs);

DnsHealthSample _conn({int ageMs = 0}) =>
    DnsHealthSample(kind: DnsHealthEventKind.connActivity, ageMs: ageMs);


List<DnsHealthSample> _mk(int fails, int oks, {bool activity = true}) => [
      for (var i = 0; i < fails; i++) _dns(true),
      for (var i = 0; i < oks; i++) _dns(false),
      if (activity) _conn(),
    ];

void main() {
  group('§262 константы', () {
    test('окно 30с, доля 20%, минимум 3 fail', () {
      expect(kDnsHealthWindow.inSeconds, 30);
      expect(kDnsHealthFailRatio, 0.20);
      expect(kDnsHealthMinFails, 3);
    });
  });

  group('§262 базовые', () {
    test('пусто → healthy', () {
      expect(evaluateDnsUnhealthy([]), isFalse);
    });

    test('3 fail из 10 (30%) + активность → unhealthy', () {
      expect(evaluateDnsUnhealthy(_mk(3, 7)), isTrue);
    });

    test('2 fail (< минимума 3) → healthy, даже при 100%', () {
      expect(evaluateDnsUnhealthy(_mk(2, 0)), isFalse);
    });

    test('3 fail из 20 (15% < 20%) → healthy', () {
      expect(evaluateDnsUnhealthy(_mk(3, 17)), isFalse);
    });

    test('4 fail из 10 (40%) + активность → unhealthy', () {
      expect(evaluateDnsUnhealthy(_mk(4, 6)), isTrue);
    });
  });

  group('§262 гейт активности связи', () {
    test('5 fail 100%, но НЕТ conn-активности → healthy (простой)', () {
      expect(evaluateDnsUnhealthy(_mk(5, 0, activity: false)), isFalse);
    });

    test('те же 5 fail 100% + активность → unhealthy', () {
      expect(evaluateDnsUnhealthy(_mk(5, 0, activity: true)), isTrue);
    });
  });

  group('§262 скользящее окно', () {
    test('старые fail (>30с назад) не учитываются', () {
      final s = [
        for (var i = 0; i < 5; i++) _dns(true, ageMs: 40000),
        for (var i = 0; i < 10; i++) _dns(false),
        _conn(),
      ];
      expect(evaluateDnsUnhealthy(s), isFalse);
    });

    test('fail в окне + старые success за бортом → доля растёт', () {
      final s = [
        for (var i = 0; i < 4; i++) _dns(true),
        for (var i = 0; i < 6; i++) _dns(false),
        for (var i = 0; i < 50; i++) _dns(false, ageMs: 60000),
        _conn(),
      ];
      expect(evaluateDnsUnhealthy(s), isTrue);
    });

    test('старая conn-активность (>30с) не считается живой связью', () {
      final s = [
        for (var i = 0; i < 5; i++) _dns(true),
        _conn(ageMs: 45000),
      ];
      expect(evaluateDnsUnhealthy(s), isFalse);
    });
  });
}
