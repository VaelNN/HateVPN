import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/direction.dart';
import 'package:lxbox/screens/routing_screen/routing_screen_helpers.dart';





void main() {
  test('§274 — detour-Направление попадает в опции с ⚙-префиксом, порядок сохранён',
      () {
    final opts = RoutingHelpers.outboundOptions(const [
      Direction(tag: 'vpn-1', label: 'Main'),
      Direction(tag: 'vpn-2', label: 'Relay', isDetour: true),
      Direction(tag: 'vpn-3', label: 'Plain'),
    ]);
    expect(opts.map((o) => o.tag),
        ['direct-out', 'vpn-1', 'vpn-2', 'vpn-3', 'block']);

    expect(opts.firstWhere((o) => o.tag == 'vpn-2').label, '⚙ Relay');

    expect(opts.firstWhere((o) => o.tag == 'vpn-3').label, 'Plain');
  });

  test('direct-out первый, block последний и danger', () {
    final opts = RoutingHelpers.outboundOptions(const [
      Direction(tag: 'vpn-1', label: 'Main'),
    ]);
    expect(opts.first.tag, 'direct-out');
    expect(opts.last.tag, 'block');
    expect(opts.last.danger, isTrue);
    expect(opts.first.danger, isFalse);
  });

  test('выключенное Направление скрыто, vpn-1 присутствует всегда (required)', () {
    final opts = RoutingHelpers.outboundOptions(const [


      Direction(tag: 'vpn-1', label: 'Main', enabled: false),
      Direction(tag: 'vpn-2', label: 'Off', enabled: false),
    ]);
    expect(opts.map((o) => o.tag), ['direct-out', 'vpn-1', 'block']);
  });

  test('пустой label Направления → tag вместо label', () {
    final opts = RoutingHelpers.outboundOptions(const [
      Direction(tag: 'vpn-1', label: ''),
    ]);
    expect(opts.firstWhere((o) => o.tag == 'vpn-1').label, 'vpn-1');
  });
}
