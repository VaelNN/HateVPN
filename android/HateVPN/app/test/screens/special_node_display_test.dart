import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/screens/home/special_node_display.dart';


void main() {
  group('specialNodeDisplayForType', () {
    test('direct → «Direct» + public', () {
      final d = specialNodeDisplayForType('direct');
      expect(d, isNotNull);
      expect(d!.label, 'Direct');
      expect(d.icon, Icons.public);
    });

    test('urltest → «Auto» + auto_awesome (✨)', () {
      final d = specialNodeDisplayForType('urltest');
      expect(d, isNotNull);
      expect(d!.label, 'Auto');
      expect(d.icon, Icons.auto_awesome);
    });

    test('§201 — block → «Block» + Icons.block', () {
      final d = specialNodeDisplayForType('block');
      expect(d, isNotNull);
      expect(d!.label, 'Block');
      expect(d.icon, Icons.block);
    });

    test('обычная прокси-нода (vless/null/selector) → null (показываем tag)', () {
      expect(specialNodeDisplayForType('vless'), isNull);
      expect(specialNodeDisplayForType('selector'), isNull);
      expect(specialNodeDisplayForType('shadowsocks'), isNull);
      expect(specialNodeDisplayForType(null), isNull);
      expect(specialNodeDisplayForType(''), isNull);
    });

    test('подмена по ТИПУ — auto-двойник с любым tag-именем ловится', () {


      expect(specialNodeDisplayForType('urltest')!.label, 'Auto');
    });
  });
}
