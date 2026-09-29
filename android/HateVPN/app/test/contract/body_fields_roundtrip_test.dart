





















library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/template_vars.dart';
import 'package:lxbox/services/contract/body_sanitizer.dart';
import 'package:lxbox/services/contract/registry.dart';
import 'package:lxbox/services/parser/json_parsers.dart';

import 'body_field_generator.dart';





const _registryRoot = 'assets/contract';


const _kParseTimeCore = '0.0.0';





const _kSchemes = <String>[
  'vless',
  'vmess',
  'trojan',
  'shadowsocks',
  'hysteria2',
  'naive',
  'tuic',
  'anytls',
  'socks',
  'http',
  'ssh',
  'wireguard',
  'masque',
];

















const kNotModelled = <String, String>{

  '*.detour': 'ставит сборка конфига из Направлений и цепочек, не тело узла',
  '*.domain_resolver': 'ставит сборка конфига (§263: два резолвера), не тело',







  '*.tcp_fast_open': 'dial-поле ядра: ни в модели, ни в эмиттере',



  'tls.kernel_tx': 'kTLS: ядро LxBox на Android не поддерживает',
  'tls.kernel_rx': 'kTLS: ядро LxBox на Android не поддерживает',




  'ssh.private_key': 'реестр зовёт поле listable_string, модель держит строку',


  'masque.tls': 'шаг 7 фичи 472, сверить после',
};


({Map<String, dynamic> sanitized, Map<String, dynamic> emitted})? _roundTrip(
  Map<String, dynamic> body,
) {
  final res = RegistrySanitizer.sanitize(
    Map<String, dynamic>.from(body),
    scheme: body['type'] as String,
    coreVersion: _kParseTimeCore,
    applyCoreGates: false,
  );
  final clean = res.body;
  if (clean == null) return null;

  final withTag = <String, dynamic>{...clean, 'tag': 'roundtrip'};


  final node = parseSingboxEntry(withTag, sanitizedFrom: BodySource.singbox);
  if (node == null) return null;
  return (sanitized: clean, emitted: node.emit(TemplateVars.empty).map);
}


Set<String> _leafPaths(Object? v, String prefix) {
  final out = <String>{};
  if (v is Map) {
    if (v.isEmpty) out.add(prefix);
    for (final e in v.entries) {
      final p = prefix.isEmpty ? '${e.key}' : '$prefix.${e.key}';
      out.addAll(_leafPaths(e.value, p));
    }
    return out;
  }
  if (v is List) {
    if (v.isEmpty) out.add(prefix);
    for (var i = 0; i < v.length; i++) {
      out.addAll(_leafPaths(v[i], '$prefix[$i]'));
    }
    return out;
  }
  out.add(prefix);
  return out;
}

Object? _at(Object? root, String path) {
  Object? cur = root;
  for (final seg in path.split('.')) {
    final m = RegExp(r'^(.*?)\[(\d+)\]$').firstMatch(seg);
    if (m != null) {
      if (cur is! Map) return null;
      cur = cur[m.group(1)];
      if (cur is! List) return null;
      final i = int.parse(m.group(2)!);
      if (i >= cur.length) return null;
      cur = cur[i];
      continue;
    }
    if (cur is! Map || !cur.containsKey(seg)) return null;
    cur = cur[seg];
  }
  return cur;
}



bool _forbiddenByRegistry(String scheme, String path) =>
    forbiddenByRegistry(scheme, path);









String? _notModelledReason(String scheme, String path) {
  var probe = path;
  while (true) {
    final hit = kNotModelled['$scheme.$probe'] ??
        kNotModelled['*.$probe'] ??
        kNotModelled[probe];
    if (hit != null) return hit;
    final cut = probe.lastIndexOf('.');
    if (cut < 0) return null;
    probe = probe.substring(0, cut);
  }
}

void main() {
  setUpAll(() async {
    await ContractRegistry.I.loadFromDirectory(_registryRoot);
  });

  test('зеркало реестра на месте — страж не имеет права молчать', () {
    expect(Directory('$_registryRoot/registry').existsSync(), isTrue,
        reason: 'страж §476 работает от зеркала в git, без копии app/contract');
    expect(ContractRegistry.I.isLoaded, isTrue);
  });

  group('§476 — каждое поле схемы попадает хотя бы в одно тело', () {
    for (final scheme in _kSchemes) {
      test(scheme, () {
        final variants = generateBodies(scheme);
        expect(variants, isNotEmpty, reason: 'схемы $scheme нет в реестре');
        final covered = <String>{};
        for (final v in variants) {
          covered.addAll(v.covered);
        }
        final all = allFieldPaths(scheme);





        final missing = all
            .where((p) => !covered.contains(p))
            .where((p) => !_forbiddenByRegistry(scheme, p))
            .where((p) => _notModelledReason(scheme, p) == null)
            .toList()
          ..sort();
        expect(missing, isEmpty,
            reason: 'поля $scheme не попали ни в одно тело — круг их не '
                'проверяет: ${missing.join(', ')}');
      });
    }
  });

  group('§476 — поле тела переживает круг «тело → модель → emit»', () {
    for (final scheme in _kSchemes) {
      test(scheme, () {
        final variants = generateBodies(scheme);
        final losses = <String>[];
        for (final v in variants) {
          final r = _roundTrip(v.body);
          if (r == null) {
            fail('${v.scheme}/${v.name}: узел не построился из ПОЛНОГО тела — '
                'это либо потерянное required-поле, либо ошибка генератора');
          }
          for (final path in _leafPaths(r.sanitized, '')) {
            if (path.isEmpty || path == 'type' || path == 'tag') continue;
            final want = _at(r.sanitized, path);
            final got = _at(r.emitted, path);
            if (got == want) continue;
            final field = path.replaceAll(RegExp(r'\[\d+\]'), '');
            if (_notModelledReason(scheme, field) != null) continue;
            losses.add('$path: было ${_show(want)}, стало ${_show(got)} '
                '(тело ${v.name})');
          }
        }
        expect(losses, isEmpty,
            reason: 'разбор $scheme теряет поля тела:\n  ${losses.join('\n  ')}');
      });
    }
  });

  test('§476 — kNotModelled: причины на месте, лишних записей нет', () {
    for (final e in kNotModelled.entries) {
      expect(e.value.trim(), isNotEmpty,
          reason: 'запись ${e.key} без причины');
    }



    final used = <String>{};



    void markUsed(String scheme, String path) {
      var probe = path;
      while (true) {
        for (final key in ['$scheme.$probe', '*.$probe', probe]) {
          if (kNotModelled.containsKey(key)) {
            used.add(key);
            return;
          }
        }
        final cut = probe.lastIndexOf('.');
        if (cut < 0) return;
        probe = probe.substring(0, cut);
      }
    }

    for (final scheme in _kSchemes) {
      final all = allFieldPaths(scheme);
      final covered = <String>{};
      for (final v in generateBodies(scheme)) {
        covered.addAll(v.covered);
        final r = _roundTrip(v.body);
        if (r == null) continue;
        for (final path in _leafPaths(r.sanitized, '')) {
          if (path.isEmpty) continue;
          if (_at(r.emitted, path) == _at(r.sanitized, path)) continue;
          markUsed(scheme, path.replaceAll(RegExp(r'\[\d+\]'), ''));
        }
      }


      for (final p in all.difference(covered)) {
        markUsed(scheme, p);
      }
    }
    final stale = kNotModelled.keys.where((k) => !used.contains(k)).toList()
      ..sort();
    expect(stale, isEmpty,
        reason: 'записи kNotModelled стали лишними — поле переживает круг, '
            'запись пора снять: ${stale.join(', ')}');
  });
}

String _show(Object? v) => v == null ? '<нет>' : '$v';
