import 'dart:io';

import 'package:flutter_test/flutter_test.dart';











void main() {
  const forbidden = [
    'trojan',
    'vless',
    'vmess',
    'shadowsocks',
    'hysteria',
    'tuic',
    'socks',
    'naive',
    'anytls',
    'wireguard',
    'masque',
    'ssh',
  ];

  test('в lib/services/parser/engine/ нет имён схем', () {
    final dir = Directory('lib/services/parser/engine');
    expect(dir.existsSync(), isTrue, reason: 'пакет движка не найден');

    final hits = <String>[];
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final lower = lines[i].toLowerCase();
        for (final name in forbidden) {
          if (lower.contains(name)) {
            hits.add('${f.path}:${i + 1}: «$name» — ${lines[i].trim()}');
          }
        }
      }
    }

    expect(hits, isEmpty,
        reason: 'движок обязан быть общим: правило схемы живёт в секции '
            'реестра, а не в коде.\n${hits.join('\n')}');
  });












  test('в диспетчере схем ссылки нет литералов схем (§562, §566)', () {
    final files = [
      'lib/services/parser/uri_parsers.dart',
      'lib/services/parser/mappers/uri_pipeline.dart',
      'lib/services/contract/registry.dart',
      'lib/services/subscription/input_helpers.dart',
    ];


    expect(Directory('lib/services/parser/uri_parsers').existsSync(), isFalse);

    const allowed = <String, Map<String, String>>{
      'lib/services/subscription/input_helpers.dart': {



        'http://': 'isSubscriptionUrl',
        'https://': 'isSubscriptionUrl',
      },
    };
    const spellings = [
      ...forbidden,
      'ss', 'hy', 'hy2', 'wg', 'awg', 'amneziawg',
      'socks4', 'socks4a', 'socks5',
      'naive+https', 'naive+quic',
      'proxy-http', 'proxy-https', 'proxy+http', 'proxy+https',
      'vpn', 'incy', 'happ',
      'http', 'https', 'chain', 'group', 'tailscale',
    ];
    final literal = RegExp(r"'([^'\\]*)'" '|' r'"([^"\\]*)"');
    final hits = <String>[];
    for (final path in files) {
      final f = File(path);
      expect(f.existsSync(), isTrue, reason: 'нет файла $path');
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final code = line.trimLeft();
        if (code.startsWith('//')) continue;


        if (line.contains('mapping.kinds.contains(')) continue;
        for (final m in literal.allMatches(line)) {
          final v = (m.group(1) ?? m.group(2) ?? '').toLowerCase();
          final bare =
              v.endsWith('://') ? v.substring(0, v.length - 3) : v;
          if (allowed[path]?.containsKey(v) ?? false) continue;
          if (spellings.contains(bare)) {
            hits.add('$path:${i + 1}: «$v» — ${line.trim()}');
          }
        }
      }
    }
    expect(hits, isEmpty,
        reason: 'написание схемы ведёт реестр (`scheme_in`, `aliases`, '
            '`scheme_sets`, `emit.form_from`), а не диспетчер.\n'
            '${hits.join('\n')}');
  });
}
