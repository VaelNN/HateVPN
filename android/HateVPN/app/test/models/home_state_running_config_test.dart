import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/home_state.dart';








void main() {
  String cfg(List<String> tags) => jsonEncode({
        'outbounds': [
          for (final t in tags) {'tag': t, 'type': 'vless'},
        ],
      });

  final saved = cfg(['L: zФранция']);
  final running = cfg(['L: ⚡Франция']);

  group('§311 activeModel — выбор среза', () {
    test('туннель down → configModel (снапшота нет и не надо)', () {
      final s = HomeState(configRaw: saved);
      expect(identical(s.activeModel, s.configModel), isTrue);
      expect(s.activeConfigRaw, saved);
    });

    test('туннель up + снапшот → runningModel', () {
      final s = HomeState(
        tunnel: TunnelStatus.connected,
        configRaw: saved,
        runningConfigRaw: running,
      );
      expect(identical(s.activeModel, s.runningModel), isTrue);
      expect(s.activeConfigRaw, running);
    });

    test('туннель up БЕЗ снапшота → configModel (деградация: старое ядро)',
        () {
      final s = HomeState(tunnel: TunnelStatus.connected, configRaw: saved);
      expect(identical(s.activeModel, s.configModel), isTrue);
      expect(s.activeConfigRaw, saved);
    });

    test('туннель down при живом снапшоте → configModel (снапшот протух)', () {


      final s = HomeState(configRaw: saved, runningConfigRaw: running);
      expect(identical(s.activeModel, s.configModel), isTrue);
    });
  });

  group('§311 РЕГРЕСС — смешение срезов', () {
    test('тег из ядра резолвится при переименованном saved', () {


      final s = HomeState(
        tunnel: TunnelStatus.connected,
        configRaw: saved,
        runningConfigRaw: running,
      );
      expect(s.activeModel['L: ⚡Франция'], isNotNull);
      expect(s.activeModel.outboundChain('L: ⚡Франция'), isNotEmpty,
          reason: 'нода из списка (= из ядра) обязана резолвиться');
      expect(s.activeModel['L: zФранция'], isNull,
          reason: 'тега из непримененной пересборки в ядре нет — и не должно');
    });

    test('после рестарта (снапшот пере-захвачен) resolve переезжает', () {
      final s = HomeState(
        tunnel: TunnelStatus.connected,
        configRaw: saved,
        runningConfigRaw: saved,
      );
      expect(s.activeModel['L: zФранция'], isNotNull);
      expect(s.activeModel['L: ⚡Франция'], isNull);
    });
  });

  group('§311 copyWith — снапшот', () {
    test('set / preserve / clear', () {
      final s0 = HomeState(configRaw: saved);
      final s1 = s0.copyWith(runningConfigRaw: running);
      expect(s1.runningConfigRaw, running);
      expect(s1.runningModel, isNotNull);

      final s2 = s1.copyWith(busy: true);
      expect(s2.runningConfigRaw, running);

      final s3 = s2.copyWith(runningConfigRaw: null);
      expect(s3.runningConfigRaw, isNull);
      expect(s3.runningModel, isNull, reason: 'модель гаснет вместе с raw');
    });

    test('runningModel шарится между copyWith без смены raw (§091)', () {
      final s1 = HomeState(configRaw: saved, runningConfigRaw: running);
      final s2 = s1.copyWith(busy: true);
      expect(identical(s2.runningModel, s1.runningModel), isTrue,
          reason: 'лишний jsonDecode на каждый copyWith недопустим');
      final s3 = s1.copyWith(runningConfigRaw: running);
      expect(identical(s3.runningModel, s1.runningModel), isFalse,
          reason: 'явная передача raw → честный ре-парс');
    });

    test('configModel не зависит от снапшота', () {
      final s1 = HomeState(configRaw: saved);
      final s2 = s1.copyWith(runningConfigRaw: running);
      expect(identical(s2.configModel, s1.configModel), isTrue);
    });
  });

  group('§311 kernel-style JSON (re-marshal форма SPEC 036)', () {
    test('парсится: null-поля, endpoints, подмешанный tun', () {



      final kernelStyle = jsonEncode({
        'inbounds': [
          {
            'type': 'tun',
            'tag': 'tun-in',
            'include_package': ['com.example.app'],
          },
        ],
        'outbounds': [
          {
            'tag': 'L: ⚡Франция',
            'type': 'vless',
            'server': '45.192.2.51',
            'tls': {'enabled': true, 'alpn': null},
          },
          {'tag': 'vpn-1', 'type': 'selector', 'outbounds': null},
        ],
        'endpoints': [
          {'tag': 'warp-out', 'type': 'wireguard'},
        ],
      });
      final s = HomeState(
        tunnel: TunnelStatus.connected,
        configRaw: saved,
        runningConfigRaw: kernelStyle,
      );
      expect(s.activeModel['L: ⚡Франция']?.type, 'vless');
      expect(s.activeModel['warp-out']?.kind, 'endpoint');
      expect(s.activeModel['vpn-1']?.isControl, isTrue);
    });
  });

  group('§311 потребители типа узла', () {
    test('isControlTag / sortedNodes pin-by-type берут тип из снапшота', () {


      final runningWithDirect = jsonEncode({
        'outbounds': [
          {'tag': 'direct-out', 'type': 'direct'},
          {'tag': 'L: ⚡Франция', 'type': 'vless'},
        ],
      });
      final s = HomeState(
        tunnel: TunnelStatus.connected,
        configRaw: cfg(['что-то-другое']),
        runningConfigRaw: runningWithDirect,
        nodes: ['direct-out', 'L: ⚡Франция'],
      );
      expect(s.isControlTag('direct-out'), isTrue);
      expect(s.sortedNodes.first, 'direct-out',
          reason: 'pin-by-type (§125) обязан видеть direct в срезе ядра');
    });
  });
}
