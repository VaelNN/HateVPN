import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'engine_test_setup.dart';
import 'package:lxbox/models/node_spec.dart';
import 'package:lxbox/models/template_vars.dart';
import 'package:lxbox/services/parser/uri_parsers.dart';



void main() {
  setUpAll(loadEngineSections);

  final root = Directory('test/fixtures');

  group('URI parsing — fixtures', () {
    for (final proto in [
      'vless',
      'vmess',
      'trojan',
      'shadowsocks',
      'hysteria2',
      'tuic',
      'ssh',
      'socks',
      'wireguard',
    ]) {
      final dir = Directory('${root.path}/$proto');
      if (!dir.existsSync()) continue;
      for (final file in dir.listSync().whereType<File>()) {
        if (!file.path.endsWith('.uri')) continue;
        final name = file.uri.pathSegments.last;
        test('$proto/$name parses + emits + round-trips', () {
          final content = _firstLine(file.readAsStringSync());
          final spec = parseUri(content);
          expect(spec, isNotNull, reason: 'failed to parse $name');
          expect(spec!.server, isNotEmpty);
          expect(spec.port, greaterThan(0));
          expect(spec.tag, isNotEmpty);

          final entry = spec.emit(TemplateVars.empty);
          expect(entry.map['tag'], spec.tag);
          expect(entry.map['type'], isNotNull);


          final uri2 = spec.toUri();
          expect(uri2, isNotEmpty);
          final spec2 = parseUri(uri2);
          expect(spec2, isNotNull,
              reason: 'round-trip parse failed: "$uri2"');
          _expectStructurallyEqual(spec2!, spec, name);
        });
      }
    }
  });
}

String _firstLine(String content) {
  for (final line in content.split(RegExp(r'\r?\n'))) {
    final t = line.trim();
    if (t.isEmpty) continue;
    if (t.startsWith('#') || t.startsWith('//') || t.startsWith(';')) continue;
    return t;
  }
  return content.trim();
}

void _expectStructurallyEqual(NodeSpec a, NodeSpec b, String ctx) {
  expect(a.server, b.server, reason: '$ctx: server');
  expect(a.port, b.port, reason: '$ctx: port');
  expect(a.runtimeType, b.runtimeType, reason: '$ctx: type');

  expect(a.tag, isNotEmpty, reason: '$ctx: tag not empty');
}
