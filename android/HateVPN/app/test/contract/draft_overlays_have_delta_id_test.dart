import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';



















void main() {
  const root = 'assets/contract_draft';




  const idKey = '_delta_id';





  final idForm = RegExp(r'^(D133-(E|C)?\d+|D-\d+|D533-[a-z0-9-]+)$');




  List<(String, Map<String, dynamic>)> entriesOf(
      String file, Map<String, dynamic> doc) {
    final out = <(String, Map<String, dynamic>)>[];

    void addEntry(String path, Object? v) {
      if (v is Map<String, dynamic>) out.add((path, v));
    }

    final mappers = doc['mappers'];
    if (mappers is Map) {
      for (final MapEntry(key: dialect, value: sec) in mappers.entries) {
        if (sec is! Map) continue;
        for (final MapEntry(key: k, value: v) in sec.entries) {
          if (k.toString().startsWith('_')) continue;
          if (k == 'params') {
            if (v is Map) {
              for (final p in v.entries) {
                addEntry('mappers.$dialect.params.${p.key}', p.value);
              }
            }
          } else {


            addEntry('mappers.$dialect.$k', v);
          }
        }
      }
    }

    final blocks = doc['blocks'];
    if (blocks is Map) {
      for (final MapEntry(key: dialect, value: table) in blocks.entries) {
        if (table is! Map) continue;
        for (final MapEntry(key: name, value: v) in table.entries) {
          if (name == 'note' || name.toString().startsWith('_')) continue;
          if (v is! Map) continue;
          final m = v.cast<String, dynamic>();


          if (!m.containsKey('source') && !m.containsKey(idKey)) {
            for (final g in m.entries) {
              if (g.key == 'note' || g.key.startsWith('_')) continue;
              addEntry('blocks.$dialect.$name.${g.key}', g.value);
            }
            continue;
          }
          addEntry('blocks.$dialect.$name', m);
        }
      }
    }
    return out;
  }

  test('каждая запись contract_draft несёт ID дельты', () {
    final dir = Directory(root);
    expect(dir.existsSync(), isTrue, reason: 'нет каталога $root');

    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final problems = <String>[];
    var checked = 0;

    for (final f in files) {
      final doc =
          (jsonDecode(f.readAsStringSync()) as Map).cast<String, dynamic>();
      for (final (path, entry) in entriesOf(f.path, doc)) {
        checked++;
        final id = entry[idKey];
        if (id == null) {
          problems.add('${f.path}: $path — нет "$idKey". Оверлей это ЗАЯВКА '
              'НА ДЕЛЬТУ: назовите её ID из DELTAS.md, иначе отступление '
              'живёт молча и протухает незаметно');
          continue;
        }
        if (id is! String || !idForm.hasMatch(id)) {
          problems.add('${f.path}: $path — "$idKey" = "$id" не той формы '
              '(ждём D133-<n> / D133-E<n> / D133-C<n> / D-<n> / '
              'D533-<имя>)');
        }
      }
    }




    expect(checked, greaterThan(0),
        reason: 'в $root не нашлось ни одной записи — проверять нечего. '
            'Если оверлеев действительно не осталось, удалите и этот тест '
            'вместе с каталогом');

    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
