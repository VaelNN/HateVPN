import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/services/parser/engine/emitter.dart';
import 'package:lxbox/services/parser/engine/section.dart';






MapperSection _section(Map<String, dynamic> json) =>
    MapperSection.fromJson('uri', 'x', json);

String _emit(Map<String, dynamic> section, Map<String, dynamic> body,
        {String label = ''}) =>
    emitViaSection(_section(section), body, label)!.uri;

void main() {
  group('§480 W7 · value_map⁻¹', () {
    test('инъективная таблица обращается', () {
      expect(invertValueMap({'chrome': 'hellochrome'}), {'hellochrome': 'chrome'});
    });

    test('НЕинъективная таблица: побеждает ПЕРВОЕ объявленное написание', () {



      expect(invertValueMap({'on': 'true', 'true': 'true', '1': 'true'}),
          {'true': 'on'});
    });

    test('пустой ключ — «параметра не было», обратно не пишется', () {
      expect(invertValueMap({'': 'auto', 'aes': 'aes'}), {'aes': 'aes'});
    });

    test('ветка со значением null из обращения выпадает', () {

      expect(invertValueMap({'random': null, 'chrome': 'hellochrome'}),
          {'hellochrome': 'chrome'});
    });

    test('таблица из одних null обращения не даёт', () {
      expect(invertValueMap({'random': null}), isNull);
    });
  });

  group('§480 W7 · сериализация query', () {
    const base = {
      'detect': {
        'scheme_in': ['s']
      },
      'emit': {'form': 'url', 'param_order': 'alphabetical'},
      'params': {
        'server': {'source': 'host', 'maps_to': 'server'},
        'server_port': {'source': 'port', 'maps_to': 'server_port'},
        'b': {'source': 'query.b', 'maps_to': 'b'},
        'a': {'source': 'query.a', 'maps_to': 'a'},
      },
    };

    test('порядок параметров алфавитный, а не порядок объявления', () {
      final uri = _emit(base, {'server': 'h', 'server_port': 1, 'b': '2', 'a': '1'});
      expect(uri, 's://h:1?a=1&b=2');
    });

    test('пробел кодируется %20, не «+»', () {
      expect(_emit(base, {'server': 'h', 'server_port': 1, 'a': 'x y'}),
          's://h:1?a=x%20y');
    });

    test('литеральный «+» кодируется %2B — иначе чтение вернёт пробел', () {


      expect(_emit(base, {'server': 'h', 'server_port': 1, 'a': 'x+y'}),
          's://h:1?a=x%2By');
    });

    test('IPv6 в скобках', () {
      expect(_emit(base, {'server': '2001:db8::1', 'server_port': 1}),
          's://[2001:db8::1]:1');
    });

    test('метка уезжает во фрагмент', () {
      expect(_emit(base, {'server': 'h', 'server_port': 1}, label: 'имя'),
          's://h:1#%D0%B8%D0%BC%D1%8F');
    });
  });

  group('§480 W7 · sets⁻¹', () {
    const section = {
      'detect': {
        'scheme_in': ['s']
      },
      'emit': {
        'form': 'url',
        'param_order': 'alphabetical',
        'omit_default': ['sec'],
      },
      'params': {
        'server': {'source': 'host', 'maps_to': 'server'},
        'server_port': {'source': 'port', 'maps_to': 'server_port'},
        'sec': {
          'source': 'query.sec',
          'selector': true,
          'sets': {
            'on': {'tls.enabled': true},
            'off': {'tls': null},
            '': {'tls.enabled': true},
          },
        },
      },
    };

    test('значение, совпавшее с умолчанием, не пишется', () {
      expect(_emit(section, {'server': 'h', 'server_port': 1, 'tls': {'enabled': true}}),
          's://h:1');
    });

    test('ветка-ОТРИЦАНИЕ пишется, хотя имя в omit_default', () {


      expect(_emit(section, {'server': 'h', 'server_port': 1}), 's://h:1?sec=off');
    });
  });

  group('§480 W7 · источник записи', () {
    test('запись, читающая не query, параметром не повторяется', () {


      final uri = _emit(const {
        'detect': {
          'scheme_in': ['s']
        },
        'emit': {'form': 'url'},
        'params': {
          'server': {'source': 'host', 'maps_to': 'server'},
          'server_port': {'source': 'port', 'maps_to': 'server_port'},
        },
      }, {'server': 'h', 'server_port': 1});
      expect(uri, 's://h:1');
    });
  });

  group('§480 W7 · userinfo into⁻¹', () {
    Map<String, dynamic> withUserinfo(Map<String, dynamic> ui) => {
          'detect': {
            'scheme_in': ['s']
          },
          'emit': {'form': 'url'},
          'userinfo': ui,
          'params': {
            'server': {'source': 'host', 'maps_to': 'server'},
            'server_port': {'source': 'port', 'maps_to': 'server_port'},
          },
        };

    test('один слот — весь userinfo целиком', () {
      expect(
          _emit(withUserinfo({'into': ['password']}),
              {'server': 'h', 'server_port': 1, 'password': 'p@ss:word'}),
          's://p%40ss%3Aword@h:1');
    });

    test('два слота — через разделитель', () {
      expect(
          _emit(
              withUserinfo({
                'split': {'sep': ':', 'limit': 2},
                'into': ['user', 'pass'],
              }),
              {'server': 'h', 'server_port': 1, 'user': 'u', 'pass': 'p'}),
          's://u:p@h:1');
    });

    test('пустая голова, непустой хвост — форма «:pass@»', () {
      expect(
          _emit(
              withUserinfo({
                'split': {'sep': ':', 'limit': 2},
                'into': ['user', 'pass'],
              }),
              {'server': 'h', 'server_port': 1, 'pass': 'p'}),
          's://:p@h:1');
    });

    test('одиночное имя при single_into=ВТОРОЙ слот несёт двоеточие', () {

      expect(
          _emit(
              withUserinfo({
                'split': {'sep': ':', 'limit': 2},
                'into': ['user', 'pass'],
                'single_into': 'pass',
              }),
              {'server': 'h', 'server_port': 1, 'user': 'u'}),
          's://u:@h:1');
    });

    test('одиночное имя при single_into=ПЕРВЫЙ слот двоеточия не несёт', () {
      expect(
          _emit(
              withUserinfo({
                'split': {'sep': ':', 'limit': 2},
                'into': ['user', 'pass'],
                'single_into': 'user',
              }),
              {'server': 'h', 'server_port': 1, 'user': 'u'}),
          's://u@h:1');
    });

    test('оба пусто — userinfo нет вовсе', () {
      expect(
          _emit(
              withUserinfo({
                'split': {'sep': ':', 'limit': 2},
                'into': ['user', 'pass'],
              }),
              {'server': 'h', 'server_port': 1}),
          's://h:1');
    });
  });

  group('§480 W7 · form_from (scheme_sets⁻¹)', () {
    const section = {
      'detect': {
        'scheme_in': ['s5']
      },
      'emit': {
        'form': 'url',
        'form_from': {
          'version': {'4': 's4', '*': 's5'}
        },
      },
      'scheme_sets': {
        's4': {'version': '4'},
        's5': {'version': '5'},
      },
      'params': {
        'server': {'source': 'host', 'maps_to': 'server'},
        'server_port': {'source': 'port', 'maps_to': 'server_port'},
      },
    };

    test('написание схемы восстанавливается по телу', () {
      expect(_emit(section, {'server': 'h', 'server_port': 1, 'version': '4'}),
          's4://h:1');
    });

    test('ветка «*» — всё остальное', () {
      expect(_emit(section, {'server': 'h', 'server_port': 1, 'version': '5'}),
          's5://h:1');
    });
  });

  group('§480 W7 · emit.omit_port', () {
    test('порт, равный объявленному, опускается', () {
      const section = {
        'detect': {
          'scheme_in': ['s']
        },
        'emit': {'form': 'url', 'omit_port': 443},
        'params': {
          'server': {'source': 'host', 'maps_to': 'server'},
          'server_port': {'source': 'port', 'maps_to': 'server_port'},
        },
      };
      expect(_emit(section, {'server': 'h', 'server_port': 443}), 's://h');
      expect(_emit(section, {'server': 'h', 'server_port': 8443}), 's://h:8443');
    });
  });

  group('§480 W7 · потери на круге', () {
    test('путь, никуда не уехавший, объявлен потерей', () {
      final r = emitViaSection(
        _section(const {
          'detect': {
            'scheme_in': ['s']
          },
          'emit': {'form': 'url'},
          'params': {
            'server': {'source': 'host', 'maps_to': 'server'},
          },
        }),
        {'server': 'h', 'orphan': 'v'},
        '',
      )!;
      expect(r.lost, ['orphan']);
    });

    test('round_trip:false снимает путь с учёта — потеря ОБЪЯВЛЕНА', () {
      final r = emitViaSection(
        _section(const {
          'detect': {
            'scheme_in': ['s']
          },
          'emit': {'form': 'url'},
          'params': {
            'server': {'source': 'host', 'maps_to': 'server'},
            'x': {
              'source': 'query.x',
              'maps_to': 'orphan',
              'round_trip': false,
              'round_trip_why': 'в ссылке этого поля нет ни у одного клиента',
            },
          },
        }),
        {'server': 'h', 'orphan': 'v'},
        '',
      )!;
      expect(r.lost, isEmpty);
      expect(r.uri, 's://h');
    });

    test('consumed первого элемента массива не покрывает остальные', () {



      final r = emitViaSection(
        _section(const {
          'detect': {
            'scheme_in': ['s']
          },
          'emit': {'form': 'url'},
          'params': {
            'server': {'source': 'host', 'maps_to': 'hops[].host'},
            'k': {'source': 'query.k', 'maps_to': 'hops[].key'},
          },
        }),
        {
          'hops': [
            {'host': 'a.example', 'key': 'one'},
            {'host': 'b.example', 'key': 'two'},
          ],
        },
        '',
      )!;
      expect(r.uri, 's://a.example?k=one');
      expect(r.lost, containsAll(['hops[1].host', 'hops[1].key']));
    });
  });

  group('§480 W7 · emit.refuse_when', () {
    const section = {
      'detect': {
        'scheme_in': ['s']
      },
      'emit': {
        'form': 'url',
        'refuse_when': [
          {'path': 'hops', 'len_gt': 1},
        ],
      },
      'params': {
        'server': {'source': 'host', 'maps_to': 'hops[].host'},
      },
    };

    test('длина больше порога — ссылки нет (как у схемы без share_uri)', () {
      final r = emitViaSection(
        _section(section),
        {
          'hops': [
            {'host': 'a.example'},
            {'host': 'b.example'},
          ],
        },
        '',
      );
      expect(r, isNotNull, reason: 'секция emit объявила — это не «нет хода»');
      expect(r!.uri, isEmpty);
    });

    test('один элемент — ссылка собирается', () {
      expect(
        emitViaSection(
          _section(section),
          {
            'hops': [
              {'host': 'a.example'},
            ],
          },
          '',
        )!.uri,
        's://a.example',
      );
    });
  });

  test('секция без блока emit обратного хода не даёт', () {
    expect(
        emitViaSection(
            _section(const {'params': <String, dynamic>{}}), const {}, ''),
        isNull);
  });
  group('§480 W7 · form_from any_set (обращение kind_when)', () {
    const section = {
      'detect': {
        'scheme_in': ['plain', 'special']
      },
      'emit': {
        'form': 'url',
        'form_from': {
          'any_set': {
            'special': ['a', 'b'],
            '*': 'plain',
          }
        },
      },
      'params': {
        'server': {'source': 'host', 'maps_to': 'server'},
        'server_port': {'source': 'port', 'maps_to': 'server_port'},
        'a': {'source': 'query.a', 'maps_to': 'a'},
      },
    };

    test('заполнен хоть один путь набора → написание набора', () {


      expect(_emit(section, {'server': 'h', 'server_port': 1, 'a': 'v'}),
          'special://h:1?a=v');
    });

    test('ни одного пути набора → ветка «*»', () {
      expect(_emit(section, {'server': 'h', 'server_port': 1}), 'plain://h:1');
    });
  });

  group('§480 W8 · emit.names', () {
    Map<String, dynamic> section(Map<String, dynamic> names) => {
          'emit': {'form': 'url', 'param_order': 'alphabetical', 'names': names},
          'params': {
            'server': {'source': 'host', 'maps_to': 'server'},
            'server_port': {'source': 'port', 'maps_to': 'server_port'},
            'insecure': {
              'source': ['query.insecure', 'query.allowInsecure'],
              'maps_to': 'tls.insecure',
              'type': 'bool_spelled',
            },
          },
        };
    const body = {
      'server': 'h',
      'server_port': 1,
      'tls': {'insecure': true},
    };

    test('написание из source записи — пишется оно', () {


      expect(_emit(section({'insecure': 'allowInsecure'}), body),
          'x://h:1?allowInsecure=true');
    });

    test('без объявления — канон записи (первое в aliases)', () {
      expect(_emit(section({}), body), 'x://h:1?insecure=true');
    });

    test('написание, которого запись НЕ читает, отвергается', () {


      expect(_emit(section({'insecure': 'skipVerify'}), body),
          'x://h:1?insecure=true');
    });

    test('readableNames — имя, алиасы и query-написания source', () {
      final p = MapperSection.fromJson('uri', 'x', section({}))
          .params['insecure']!;
      expect(readableNames(p), {'insecure', 'allowInsecure'});
    });
  });

  group('§480 · синк 1.1.37 · написание булева объявляет ЗАПИСЬ, не тип', () {
















    Map<String, dynamic> sectionOf(String type, {String? emitAs}) => {
          'emit': {'form': 'url', 'param_order': 'alphabetical'},
          'params': {
            'server': {'source': 'host', 'maps_to': 'server'},
            'server_port': {'source': 'port', 'maps_to': 'server_port'},
            'flag': {
              'source': 'query.flag',
              'maps_to': 'transport.flag',
              'type': type,
              'emit_as': ?emitAs,
            },
          },
        };
    const body = {
      'server': 'h',
      'server_port': 1,
      'transport': {'flag': true},
    };

    test('bool_spelled БЕЗ объявления — СЛОВО: тип написания не решает', () {
      expect(_emit(sectionOf('bool_spelled'), body), 'x://h:1?flag=true');
    });

    test('bool без объявления — то же слово', () {
      expect(_emit(sectionOf('bool'), body), 'x://h:1?flag=true');
    });

    test('emit_as: bool01 — ЕДИНСТВЕННЫЙ способ получить цифру', () {
      expect(_emit(sectionOf('bool_spelled', emitAs: 'bool01'), body),
          'x://h:1?flag=1');
      expect(_emit(sectionOf('bool', emitAs: 'bool01'), body),
          'x://h:1?flag=1');
    });

    test('emit_as: raw — то же слово, что и умолчание', () {
      expect(_emit(sectionOf('bool_spelled', emitAs: 'raw'), body),
          'x://h:1?flag=true');
      expect(_emit(sectionOf('bool', emitAs: 'raw'), body),
          'x://h:1?flag=true');
    });

    test('ложь не пишется вовсе — ни с объявлением, ни без', () {
      const off = {
        'server': 'h',
        'server_port': 1,
        'transport': {'flag': false},
      };
      expect(_emit(sectionOf('bool_spelled'), off), 'x://h:1');
      expect(_emit(sectionOf('bool_spelled', emitAs: 'raw'), off), 'x://h:1');
      expect(_emit(sectionOf('bool_spelled', emitAs: 'bool01'), off), 'x://h:1');
    });
  });
}
