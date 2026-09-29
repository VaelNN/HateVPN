











import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/services/contract/body_sanitizer.dart';
import 'package:lxbox/services/contract/registry.dart';

import '../contract_paths.dart';


const _core = '1.14.1-lx.4';

void main() {
  final corpusRoot = Directory('$kVendorRoot/corpus/body');

  group('Инвариант 24.1.7 — санитайзер идемпотентен на корпусе', () {
    setUpAll(loadTestRegistry);

    if (!hasContractCorpus) {
      test('корпус контракта не синхронизирован', () {}, skip:
          corpusTestSkip('test/contract/registry_invariant_test.dart',
              subpath: 'corpus/body'));
      return;
    }

    final files = corpusRoot
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.expected.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      final rel = file.path.substring(corpusRoot.path.length + 1);
      test(rel, () {
        final data =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final nodes = (data['nodes'] as List?) ?? const [];
        var checked = 0;

        for (final raw in nodes) {
          if (raw is! Map) continue;
          final entry = raw['entry'];
          if (entry is! Map) continue;
          final body = entry.cast<String, dynamic>();
          final type = body['type'];
          if (type is! String) continue;


          if (ContractRegistry.I.schemaFor(type) == null) continue;








          final source =
              rel.startsWith('singbox/') ? BodySource.singbox : BodySource.other;

          final first = RegistrySanitizer.sanitize(
            Map<String, dynamic>.from(body),
            scheme: type,
            coreVersion: _core,
            source: source,
          );


          if (first.body == null) continue;

          final second = RegistrySanitizer.sanitize(
            Map<String, dynamic>.from(first.body!),
            scheme: type,
            coreVersion: _core,
            source: source,
          );






          final kept = second.warnings
              .where((w) =>
                  ContractRegistry.I.textFor(w.code)?.severity != 'info')
              .map((w) => '${w.code}@${w.path}')
              .toList();
          expect(
            kept,
            isEmpty,
            reason: '$rel: после санитайзера в теле ${raw['label']} '
                '($type) остались значения, которые реестр считает негодными',
          );

          expect(second.body, first.body,
              reason: '$rel: санитайзер не идемпотентен на ${raw['label']}');
          checked++;
        }



        if (checked == 0) {
          markTestSkipped('$rel: записей со схемой реестра нет');
        }
      });
    }
  });









  group('§469 — forbidden_codes', () {
    setUpAll(loadTestRegistry);
    final registryDir = Directory('$kRegistryRoot/registry');

    test('ключи — только схемы из forbidden_for, коды — только из warnings.json',
        () {
      final codes = ((jsonDecode(
                      File('$kRegistryRoot/registry/warnings.json')
                          .readAsStringSync())
                  as Map<String, dynamic>)['warnings'] as Map)
          .keys
          .map((e) => '$e')
          .toSet();

      var checkedFields = 0;
      for (final file in registryDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))) {
        final rel = file.path.substring(registryDir.path.length + 1);
        if (rel == 'warnings.json') continue;
        final data = jsonDecode(file.readAsStringSync());

        void walk(Object? node, String path) {
          if (node is Map) {
            final fc = node['forbidden_codes'];
            if (fc is Map) {
              checkedFields++;
              final forbiddenFor = ((node['forbidden_for'] as List?) ?? const [])
                  .map((e) => '$e')
                  .toSet();
              for (final e in fc.entries) {
                expect(forbiddenFor, contains('${e.key}'),
                    reason: '$rel $path: forbidden_codes называет схему '
                        '"${e.key}", которой нет в forbidden_for — правило '
                        'не сработает никогда');
                expect(codes, contains('${e.value}'),
                    reason: '$rel $path: код "${e.value}" из forbidden_codes '
                        'отсутствует в warnings.json — узел получил бы запись '
                        'без текста');
              }
            }
            for (final e in node.entries) {
              walk(e.value, path.isEmpty ? '${e.key}' : '$path.${e.key}');
            }
          } else if (node is List) {
            for (final e in node) {
              walk(e, path);
            }
          }
        }

        walk(data, '');
      }



      expect(checkedFields, greaterThan(0),
          reason: 'forbidden_codes в реестре не встречается вовсе — либо '
              'контракт откатили, либо линтер смотрит не туда');
    });












    test('coerce несёт свой код, а не общий type_invalid', () {
      var checked = 0;
      for (final file in registryDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))) {
        final rel = file.path.substring(registryDir.path.length + 1);
        if (rel == 'warnings.json') continue;
        final data = jsonDecode(file.readAsStringSync());

        void walk(Object? node, String path) {
          if (node is Map) {
            final oi = node['on_invalid'];
            if (oi is Map && oi['action'] == 'coerce') {
              checked++;
              expect(oi['code'], isNotNull,
                  reason: '$rel $path: coerce без кода — подмена значения '
                      'прошла бы молча');
              expect(oi['code'], isNot('type_invalid'),
                  reason: '$rel $path: coerce с общим type_invalid. Текст '
                      'кода описывает СНЯТИЕ поля, а coerce его подменяет — '
                      'заведите свой код у лаунчера');
            }
            for (final e in node.entries) {
              walk(e.value, path.isEmpty ? '${e.key}' : '$path.${e.key}');
            }
          } else if (node is List) {
            for (final e in node) {
              walk(e, path);
            }
          }
        }

        walk(data, '');
      }


      expect(checked, greaterThanOrEqualTo(3),
          reason: 'on_invalid.coerce в реестре почти не встречается — '
              'проверьте, не разъехался ли обход с формой реестра');
    });

    test('санитайзер берёт код из forbidden_codes, а не общий', () {


      Map<String, dynamic> body(String scheme) => {
            'type': scheme,
            'server': 'example-1.com',
            'server_port': 443,
            if (scheme == 'naive') 'username': 'u',
            if (scheme != 'naive') 'password': 'p',


            if (scheme == 'tuic') 'uuid': '11111111-1111-1111-1111-111111111111',
            if (scheme == 'masque') ...{
              'profile': 'cloudflare',
              'private_key': 'k',
              'public_key': 'k',
            },
            'tls': {
              'enabled': true,
              'server_name': 'example-1.com',
              'utls': {'enabled': true, 'fingerprint': 'chrome'},
            },
          };

      for (final (scheme, code) in const [
        ('naive', 'tls_field_unsupported_naive'),
        ('hysteria2', 'tls_not_applicable_quic'),
        ('tuic', 'tls_not_applicable_quic'),
        ('masque', 'tls_not_applicable_quic'),
      ]) {
        final res = RegistrySanitizer.sanitize(body(scheme),
            scheme: scheme, coreVersion: _core);
        final utls = res.warnings.where((w) => w.path == 'tls.utls').toList();
        expect(utls, hasLength(1), reason: '$scheme: один код на блок');
        expect(utls.single.code, code, reason: '$scheme: код не тот');

        expect(utls.single.value, 'map[enabled:true fingerprint:chrome]');
        expect((res.body?['tls'] as Map?)?.containsKey('utls'), isFalse,
            reason: '$scheme: блок обязан быть снят');
      }
    });

    test('§473 — max_when: коды из warnings.json, note_code при except_sources',
        () {






      final codes = ((jsonDecode(
                      File('$kRegistryRoot/registry/warnings.json')
                          .readAsStringSync())
                  as Map<String, dynamic>)['warnings'] as Map)
          .keys
          .map((e) => '$e')
          .toSet();

      var checked = 0;
      for (final file in Directory('$kRegistryRoot/registry')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))) {
        final rel = file.path.split('/').last;
        if (rel == 'warnings.json') continue;

        void walk(Object? node, String path) {
          if (node is Map) {
            final mw = node['max_when'];
            if (mw is Map) {
              checked++;
              expect(codes, contains('${mw['code']}'),
                  reason: '$rel $path: код "${mw['code']}" отсутствует в '
                      'warnings.json — узел получил бы запись без текста');
              if (mw.containsKey('except_sources')) {
                expect(mw['note_code'], isNotNull,
                    reason: '$rel $path: есть except_sources, но нет '
                        'note_code — на исключённом входе правило промолчит '
                        'вовсе, и о завышенном значении не узнает никто');
                expect(codes, contains('${mw['note_code']}'),
                    reason: '$rel $path: note_code "${mw['note_code']}" '
                        'отсутствует в warnings.json');
              }
              final anySet = (mw['when'] as Map?)?['any_set'];
              expect(anySet, isA<List>().having((l) => l.length, 'непустой',
                  greaterThan(0)),
                  reason: '$rel $path: пустое when.any_set сделало бы потолок '
                      'безусловным — он снял бы поле у каждого узла схемы');
            }
            for (final e in node.entries) {
              walk(e.value, path.isEmpty ? '${e.key}' : '$path.${e.key}');
            }
          } else if (node is List) {
            for (final e in node) {
              walk(e, path);
            }
          }
        }

        walk(jsonDecode(file.readAsStringSync()), '');
      }



      expect(checked, greaterThan(0),
          reason: 'max_when в реестре не встречается вовсе — либо контракт '
              'откатили, либо линтер смотрит не туда');
    });












    test('pattern: диалект RE2 ∩ Dart, якоря в выражении, компилируется', () {




      const forbidden = <String, String>{
        r'(?=': 'lookahead',
        r'(?!': 'negative lookahead',
        r'(?<=': 'lookbehind',
        r'(?<!': 'negative lookbehind',
        r'(?i)': 'inline-флаг',
        r'(?m)': 'inline-флаг',
        r'(?s)': 'inline-флаг',
        r'(?U)': 'inline-флаг',
      };

      var checked = 0;
      for (final file in registryDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))) {
        final rel = file.path.substring(registryDir.path.length + 1);
        if (rel == 'warnings.json') continue;

        void walk(Object? node, String path) {
          if (node is Map) {
            final p = node['pattern'];
            if (p != null) {
              checked++;
              expect(p, isA<String>(),
                  reason: '$rel $path: pattern обязан быть строкой');
              final expr = '$p';

              for (final e in forbidden.entries) {
                expect(expr.contains(e.key), isFalse,
                    reason: '$rel $path: pattern содержит ${e.value} '
                        '"${e.key}" — конструкции нет в общем подмножестве '
                        'RE2 и Dart, стороны разойдутся молча');
              }

              expect(RegExp(r'\\[1-9]').hasMatch(expr), isFalse,
                  reason: '$rel $path: pattern содержит обратную ссылку — '
                      'RE2 её не поддерживает');



              expect(expr.startsWith('^'), isTrue,
                  reason: '$rel $path: pattern без якоря ^ — совпадение по '
                      'всей строке задаётся выражением, а не режимом');
              expect(expr.endsWith(r'$'), isTrue,
                  reason: '$rel $path: pattern без якоря \$');



              expect(() => RegExp(expr), returnsNormally,
                  reason: '$rel $path: pattern не компилируется Dart RegExp — '
                      'санитайзер пропустит правило молча');
            }
            for (final e in node.entries) {
              walk(e.value, path.isEmpty ? '${e.key}' : '$path.${e.key}');
            }
          } else if (node is List) {
            for (final e in node) {
              walk(e, path);
            }
          }
        }

        walk(jsonDecode(file.readAsStringSync()), '');
      }



      expect(checked, greaterThan(0),
          reason: 'pattern в реестре не встречается вовсе — либо контракт '
              'откатили, либо линтер смотрит не туда');
    });


    test('absent_values: непустой список строк у строкового поля', () {
      var checked = 0;
      for (final file in registryDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))) {
        final rel = file.path.substring(registryDir.path.length + 1);
        if (rel == 'warnings.json') continue;

        void walk(Object? node, String path) {
          if (node is Map) {
            final av = node['absent_values'];
            if (av != null) {
              checked++;
              expect(av, isA<List>(),
                  reason: '$rel $path: absent_values обязан быть списком');
              final list = (av as List);
              expect(list, isNotEmpty,
                  reason: '$rel $path: пустой absent_values — правило, '
                      'которое выглядит написанным и не делает ничего');
              for (final e in list) {
                expect(e, isA<String>(),
                    reason: '$rel $path: absent_values — литералы СТРОКАМИ: '
                        'сравнение точное и только строковое');
              }


              final values = (node['values'] as List?) ?? const [];
              for (final e in list) {
                expect(values.contains(e), isFalse,
                    reason: '$rel $path: "$e" стоит и в absent_values, и в '
                        'values — поле одновременно выключатель и годное '
                        'значение');
              }
            }
            for (final e in node.entries) {
              walk(e.value, path.isEmpty ? '${e.key}' : '$path.${e.key}');
            }
          } else if (node is List) {
            for (final e in node) {
              walk(e, path);
            }
          }
        }

        walk(jsonDecode(file.readAsStringSync()), '');
      }

      expect(checked, greaterThan(0),
          reason: 'absent_values в реестре не встречается вовсе — либо '
              'контракт откатили, либо линтер смотрит не туда');
    });

    test('REALITY на QUIC — один код на блок, key_share/short_id молчат', () {
      final res = RegistrySanitizer.sanitize({
        'type': 'hysteria2',
        'server': 'example-1.com',
        'server_port': 443,
        'password': 'p',
        'tls': {
          'enabled': true,
          'server_name': 'example-1.com',
          'reality': {
            'enabled': true,
            'public_key': 'AwoRGB8mLTQ7QklQV15lbHN6gYiPlp2kq7K5wMfO1dw',
            'short_id': 'ab',
            'key_share': 'hybrid',
          },
        },
      }, scheme: 'hysteria2', coreVersion: _core);

      expect(res.warnings.map((w) => '${w.code}@${w.path}'),
          ['tls_not_applicable_quic@tls.reality'],
          reason: 'снят не short_id и не key_share, а весь REALITY — '
              'вложенные поля своих кодов не дают');
      expect((res.body?['tls'] as Map?)?.containsKey('reality'), isFalse);
    });
  });
}
