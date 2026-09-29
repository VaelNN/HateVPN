import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../contract_paths.dart';
import 'package:lxbox/models/parser_config.dart';
import 'package:lxbox/services/builder/if_engine.dart';



























const _mustRejectOnLoad = <String, String>{

  'grammar/if_without_and_or_is_false': 'нет ни and, ни or',

  'grammar/if_with_both_and_or_is_false': 'оба ключа and+or сразу',

  'enable/both_and_or_is_false': '#enable: оба ключа and+or сразу',

  'enable/invalid_cond_is_false': '#enable: скаляр вместо условия',


  'tpl/extra_key_is_error': '#tpl не допускает других ключей объекта',
};




const _mustLoadFine = <String>[

  'grammar/hashed_keywords_canonical',
  'grammar/legacy_keywords_still_read',
  'grammar/mixed_hashed_and_legacy',
  'grammar/hashed_keywords_in_enable',
  'grammar/tolerant_unknown_var_field',

  'enable/single_string_form',
  'enable/sugar_list_is_and',
  'enable/cond_obj_or',
  'enable/recursive_cond',
  'enable/true_keeps_node_and_strips_key',
  'enable/true_then_if_applies',
  'enable/false_removes_key',
  'enable/false_drops_array_element',
  'enable/inside_if_branch',

  'predicates/nested_and_with_or',
  'predicates/nested_or_with_and',
  'predicates/nested_depth_three',
  'predicates/not_over_and',
  'predicates/p6_not_wraps_equality',
  'map_spread/named_if_two_on_one_object',
  'map_spread/nested_if_in_branch',
];











const _knownDivergence = <String, bool>{




  'predicates/p4_in_text_list_string_form': false,






  'predicates/nested_empty_or_is_false': true,

  'grammar/if_empty_and_is_true': true,


  'grammar/if_missing_value_is_skipped': true,





  'predicates/p4_in_literal_list': false,
  'predicates/p4_notin_literal_list': false,



  'unresolved/undeclared_name_stays_placeholder': false,
};







const _rejectedByUndeclaredName = <String>[
  'enable/unknown_var_is_false',
  'enable/false_skips_inner_evaluation',
  'unresolved/undeclared_in_predicate_is_false',
];


String? _loadVerdict(String base) {
  final tpl = jsonDecode(File('$base.template.json').readAsStringSync())
      as Map<String, dynamic>;
  final byName = <String, WizardVar>{
    for (final v in (tpl['vars'] as List? ?? const []))
      if ((v as Map<String, dynamic>)['name'] is String)
        v['name'] as String: WizardVar.fromJson(v),
  };
  try {
    validateIfConstructs(tpl['config'], byName);
    return null;
  } on TemplateIfError catch (e) {
    return e.message;
  }
}

void main() {
  if (corpusSuiteUnavailable('test/contract/template_load_reject_test.dart')) return;

  final root = Directory('$kVendorRoot/corpus/template');
  if (!root.existsSync()) {

    return;
  }

  String base(String name) => '${root.path}/$name';

  group('contract: load-валидация отвергает невалидные конструкции', () {
    _mustRejectOnLoad.forEach((name, why) {
      test('$name — $why', () {
        expect(File('${base(name)}.template.json').existsSync(), isTrue,
            reason: 'фикстура пропала из корпуса — список выше устарел');
        expect(_loadVerdict(base(name)), isNotNull,
            reason: 'кейс объявлен корпусом невалидным, а загрузка его приняла');
      });
    });

    test('список невалидных кейсов не пуст', () {


      expect(_mustRejectOnLoad, isNotEmpty);
    });
  });

  group('contract: load-валидация принимает законные конструкции', () {
    for (final name in _mustLoadFine) {
      test(name, () {
        expect(File('${base(name)}.template.json').existsSync(), isTrue,
            reason: 'фикстура пропала из корпуса — список выше устарел');
        expect(_loadVerdict(base(name)), isNull,
            reason: 'законная форма языка отвергнута валидатором');
      });
    }
  });

  group('contract: необъявленное имя — рантайм терпит, загрузка отвергает', () {
    for (final name in _rejectedByUndeclaredName) {
      test(name, () {
        expect(_loadVerdict(base(name)), isNotNull,
            reason: 'ссылка на необъявленную var обязана ловиться на load');
      });
    }
  });

  group('contract: вердикты загрузки, не нормированные контрактом', () {
    _knownDivergence.forEach((name, dartRejects) {
      test('$name — Dart ${dartRejects ? "отвергает" : "принимает"}', () {
        expect(_loadVerdict(base(name)) != null, dartRejects,
            reason: 'поведение валидатора изменилось — расхождение с Go либо '
                'закрыто (обнови список и контракт), либо стало другим');
      });
    });
  });

  test('весь корпус классифицирован — новых непокрытых кейсов нет', () {



    final rejected = <String>[];
    for (final f in root.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.template.json')) continue;
      final b = f.path.substring(0, f.path.length - '.template.json'.length);
      final name = b.substring(root.path.length + 1);
      if (_loadVerdict(b) != null) rejected.add(name);
    }
    final accounted = <String>{
      ..._mustRejectOnLoad.keys,
      ..._rejectedByUndeclaredName,
      ...(_knownDivergence.entries.where((e) => e.value).map((e) => e.key)),
    };
    expect(rejected.toSet().difference(accounted), isEmpty,
        reason: 'валидатор отвергает кейсы корпуса, не названные ни в одном '
            'списке этого файла');
  });
}
