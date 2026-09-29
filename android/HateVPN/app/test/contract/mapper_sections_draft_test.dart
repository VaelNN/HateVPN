import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
















const _draftRoot = 'assets/contract_draft';



const Set<String> _paramKeys = {
  'source', 'maps_to', 'aliases', 'type', 'required', 'selector', 'priority',
  'merge', 'value_map', 'sets', 'implies', 'when', 'extract', 'compose',
  'list', 'split_into', 'normalize', 'decode_extra', 'default_from',
  'default_when', 'materialize_default', 'coerce', 'flatten', 'lift',
  'sort_keys', 'empty', 'on_invalid', 'on_present', 'on_item_invalid',
  'on_no_match', 'on_len_gt', 'emit_when', 'omit_default', 'implicit',
  'since', 'desc_en', 'desc_ru', 'impl',





  'on_when_false', 'on_implies_written',





  '_why',




  'format',







  'emit_as',








  'on_empty',





  r'$code_pending',
};


const Set<String> _mapperKeys = {
  'detect', 'body_source', 'forms', 'userinfo', 'label', 'params', 'include',
  'scheme_sets', 'type_synonyms', 'defaults', 'unknown_key', 'emit',
  'ini_dialect', 'impl',





  'kind_when',
};

const Set<String> _bodySources = {'uri', 'singbox', 'xray', 'wgconf', 'amnezia'};
const Set<String> _types = {
  'string', 'int', 'bool', 'bool_spelled', 'duration', 'base64', 'list',
  'object',
};
















bool _isBlocks(Map<String, dynamic> doc) => doc.containsKey('blocks');

List<File> _sections() {
  final dir = Directory(_draftRoot);
  if (!dir.existsSync()) return const [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .where((f) => !f.path.endsWith('registry_mapper.schema.json'))
      .where((f) => !f.path.endsWith('source_kinds.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}





Map<String, Map<String, dynamic>> _sectionsOf(Map<String, dynamic> doc) {
  if (!_isBlocks(doc)) {
    return (doc['mappers'] as Map).cast<String, dynamic>().map(
          (k, v) => MapEntry(k, (v as Map).cast<String, dynamic>()),
        );
  }
  final out = <String, Map<String, dynamic>>{};
  for (final d in (doc['blocks'] as Map).entries) {
    final v = d.value;
    if (v is! Map) continue;
    final params = <String, dynamic>{};
    for (final e in v.cast<String, dynamic>().entries) {
      final ev = e.value;
      if (ev is! Map) continue;
      if (ev.containsKey('source')) {
        params[e.key] = ev;
      } else if (e.key == 'prefix' || e.key == 'strip') {

        continue;
      } else {
        for (final g in ev.cast<String, dynamic>().entries) {
          if (g.value is Map && (g.value as Map).containsKey('source')) {
            params['${e.key}.${g.key}'] = g.value;
          }
        }
      }
    }
    if (params.isNotEmpty) out['${d.key}'] = {'params': params};
  }
  return out;
}

void main() {
  final files = _sections();

  test('черновики секций вообще есть', () {
    expect(files, isNotEmpty,
        reason: 'в $_draftRoot не найдено ни одной секции — каталог потерян?');
  });

  for (final f in files) {
    group(f.path, () {
      late Map<String, dynamic> doc;

      setUpAll(() {
        doc = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      });

      test('корень несёт mappers либо blocks и ничего постороннего', () {
        final top = doc.keys.where((k) => !k.startsWith('_')).toSet();
        expect(top.contains('mappers') || top.contains('blocks'), isTrue,
            reason: 'корень обязан нести либо mappers (секция протокола), '
                'либо blocks (общий блок, вмонтируемый через include)');
        if (_isBlocks(doc)) return;
        for (final kind in (doc['mappers'] as Map).keys) {
          expect(const {'uri', 'xray', 'singbox', 'conf'}, contains(kind),
              reason: 'вид источника "$kind" вне набора грамматики');
        }
      });

      test('секция: только замороженные ключи, body_source из набора', () {


        if (_isBlocks(doc)) return;


        if (doc['_overlay'] == true) return;
        final mappers = (doc['mappers'] as Map).cast<String, dynamic>();
        for (final e in mappers.entries) {
          final sec = (e.value as Map).cast<String, dynamic>();
          for (final k in sec.keys) {
            if (k.startsWith('_')) continue;
            expect(_mapperKeys, contains(k),
                reason: '${e.key}: ключ секции "$k" вне грамматики');
          }
          expect(_bodySources, contains(sec['body_source']),
              reason: '${e.key}: body_source "${sec['body_source']}"');
        }
      });

      test('записи таблицы: ключи и type из замороженного набора', () {
        for (final e in _sectionsOf(doc).entries) {
          final params =
              (e.value['params'] as Map?)?.cast<String, dynamic>() ?? {};
          for (final p in params.entries) {
            final rec = (p.value as Map).cast<String, dynamic>();
            for (final k in rec.keys) {
              if (k.startsWith('_')) continue;
              expect(_paramKeys, contains(k),
                  reason: '${e.key}.${p.key}: ключ записи "$k" вне грамматики');
            }



            expect(rec.containsKey('source'), isTrue,
                reason: '${e.key}.${p.key}: запись без source не читается');
            final t = rec['type'];
            if (t != null) {
              expect(_types, contains(t),
                  reason: '${e.key}.${p.key}: type "$t" вне набора');
            }
          }
        }
      });

      test('формы: у каждой есть id, ровно одна ветка default', () {
        if (_isBlocks(doc)) return;
        final mappers = (doc['mappers'] as Map).cast<String, dynamic>();
        for (final e in mappers.entries) {
          final sec = (e.value as Map).cast<String, dynamic>();
          final forms = (sec['forms'] as List?) ?? const [];
          if (forms.isEmpty) continue;
          final ids = <String>{};
          var defaults = 0;
          for (final raw in forms) {
            final form = (raw as Map).cast<String, dynamic>();
            final id = form['id'];
            expect(id, isA<String>(), reason: '${e.key}: форма без id');
            expect(ids.add(id as String), isTrue,
                reason: '${e.key}: форма "$id" объявлена дважды');
            if (((form['detect'] as Map?)?['default']) == true) defaults++;
          }





          expect(defaults, lessThanOrEqualTo(1),
              reason: '${e.key}: веток default не может быть больше одной, '
                  'а их $defaults (линтер §0.2)');
          if (forms.length > 1) {
            expect(defaults, 1,
                reason: '${e.key}: у секции с несколькими формами обязана '
                    'быть ветка «всё остальное», иначе часть входов не '
                    'подойдёт ни к одной форме и узел молча исчезнет');
          }
        }
      });

      test('extract: регулярка компилируется, группы покрыты into', () {
        for (final e in _sectionsOf(doc).entries) {
          final params =
              (e.value['params'] as Map?)?.cast<String, dynamic>() ?? {};
          for (final p in params.entries) {
            final ex = ((p.value as Map)['extract'] as Map?)
                ?.cast<String, dynamic>();
            if (ex == null) continue;
            final re = ex['re'] as String;



            final dartRe = re.replaceAll('(?P<', '(?<');
            expect(() => RegExp(dartRe), returnsNormally,
                reason: '${e.key}.${p.key}: extract.re не компилируется');
            final groups = RegExp(r'\(\?P?<([A-Za-z_][A-Za-z0-9_]*)>')
                .allMatches(re)
                .map((m) => m.group(1)!)
                .toSet();
            final into =
                ((ex['into'] as Map?)?.cast<String, dynamic>() ?? {}).keys.toSet();
            expect(groups.difference(into), isEmpty,
                reason: '${e.key}.${p.key}: группы extract не покрыты into — '
                    'значение уехало бы в никуда');
          }
        }
      });
    });
  }
}
