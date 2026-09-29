























import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../contract_paths.dart';
import 'package:lxbox/services/contract/registry.dart';
import 'package:lxbox/services/contract/registry_warning.dart';



final _placeholder = RegExp(r'\{([a-z_][a-z0-9_]*)\}');






const Map<String, String> _knownUndeclared = {};

void main() {
  setUpAll(loadTestRegistry);

  group('§474 — тексты кодов реестра рендерятся без дыр', () {
    test('у каждого кода все тексты заполнены на en и ru', () {
      final codes = _allCodes();
      expect(codes, isNotEmpty, reason: 'warnings.json не прочитан');

      final holes = <String>[];
      for (final code in codes) {
        final declared = ContractRegistry.I.textFor(code)?.params ?? const [];



        final params = <String, String>{
          for (final p in declared)
            if (p != 'path' && p != 'value') p: '<$p>',
        };
        for (final lang in RegistryLang.values) {
          final rendered = <String>[
            registryTitle(code, lang,
                path: '<path>', value: '<value>', params: params),
            registryText(code, lang,
                path: '<path>', value: '<value>', params: params),
            registryCause(code, lang,
                    path: '<path>', value: '<value>', params: params) ??
                '',
            ...registryFix(code, lang,
                path: '<path>', value: '<value>', params: params),
          ];
          for (final s in rendered) {
            for (final m in _placeholder.allMatches(s)) {
              final name = m.group(1)!;
              if (_knownUndeclared.containsKey(code)) continue;
              holes.add('$code [${lang.name}]: {$name} не заполнен');
            }
          }
        }
      }
      expect(holes, isEmpty,
          reason: 'плейсхолдеры без подстановки:\n${holes.join('\n')}');
    });

    test('у каждого известного расхождения есть причина', () {
      for (final e in _knownUndeclared.entries) {
        expect(e.value.trim(), isNotEmpty,
            reason: 'расхождение ${e.key} без причины');
      }
    });




    test('tls_insecure объявляет path и value, severity info', () {
      final t = ContractRegistry.I.textFor('tls_insecure');
      expect(t, isNotNull);
      expect(t!.severity, 'info');
      expect(t.params, containsAll(<String>['path', 'value']));
    });



    test('vmess_security_unknown объявляет path и value, severity warning', () {
      final t = ContractRegistry.I.textFor('vmess_security_unknown');
      expect(t, isNotNull);
      expect(t!.severity, 'warning');
      expect(t.params, containsAll(<String>['path', 'value']));
    });






    test('снятые классы: severity info и объявленный параметр на месте', () {
      const expected = <String, String?>{
        'ech_ignored': 'query_name',
        'ws_early_data_converted': 'max_early_data',
        'naive_extra_headers_invalid': 'entry',


        'naive_padding_ignored': null,
      };
      for (final e in expected.entries) {
        final t = ContractRegistry.I.textFor(e.key);
        expect(t, isNotNull, reason: 'кода ${e.key} нет в реестре');
        expect(t!.severity, 'info', reason: e.key);
        if (e.value != null) {
          expect(t.params, contains(e.value), reason: e.key);
        }
      }
    });

    test('vision_with_transport объявляет with, severity info', () {
      final t = ContractRegistry.I.textFor('vision_with_transport');
      expect(t, isNotNull);
      expect(t!.severity, 'info');
      expect(t.params, contains('with'));


      expect(t.params, isNot(contains('transport')));
    });
  });
}



List<String> _allCodes() {
  final f = File('$kRegistryRoot/registry/warnings.json');
  if (!f.existsSync()) return const [];
  final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  final byCode = (raw['warnings'] as Map).cast<String, dynamic>();
  return byCode.keys.toList()..sort();
}
