import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/controllers/subscription_controller.dart';
import 'package:lxbox/models/node_spec.dart';
import 'package:lxbox/services/parser/uri_parsers.dart';

import '../parser/engine_test_setup.dart';










NodeSpec _node(String uri) => parseUri(uri)!;

String _key(List<NodeSpec> nodes, [Iterable<String> disabled = const []]) =>
    SubscriptionController.compositionKeyForTesting(nodes, disabled);

void main() {


  setUpAll(loadEngineSections);



  late final a = _node('vless://11111111-1111-1111-1111-111111111111@a.example.com:443?type=tcp&security=tls#A');
  late final b = _node('vless://22222222-2222-2222-2222-222222222222@b.example.com:443?type=tcp&security=tls#B');
  late final c = _node('vless://33333333-3333-3333-3333-333333333333@c.example.com:443?type=tcp&security=tls#C');

  group('§331 состав: список узлов', () {
    test('тот же список → тот же ключ', () {
      expect(_key([a, b]), _key([a, b]));
    });

    test('РЕГРЕСС: порядок узлов ЗНАЧИМ (перестановка → другой ключ)', () {



      expect(_key([a, b]), isNot(_key([b, a])));
    });

    test('добавленный узел → другой ключ', () {
      expect(_key([a, b]), isNot(_key([a, b, c])));
    });

    test('удалённый узел → другой ключ', () {
      expect(_key([a, b, c]), isNot(_key([a, c])));
    });

    test('заменённый узел → другой ключ', () {
      expect(_key([a, b]), isNot(_key([a, c])));
    });

    test('пустой список ≠ непустой', () {
      expect(_key(const []), isNot(_key([a])));
    });

    test('два пустых списка равны', () {
      expect(_key(const []), _key(const []));
    });

    test('дубль узла заметен (append, а не set)', () {


      expect(_key([a]), isNot(_key([a, a])));
    });
  });

  group('§331 состав: disable-отметки (§283)', () {
    test('набор отметок ЗНАЧИМ при том же списке узлов', () {

      expect(_key([a, b]), isNot(_key([a, b], const ['hash-a'])));
    });

    test('порядок ключей отметок НЕ значим (сортируем)', () {

      expect(
        _key([a, b], const ['hash-a', 'hash-b']),
        _key([a, b], const ['hash-b', 'hash-a']),
      );
    });

    test('снятая отметка → другой ключ', () {
      expect(
        _key([a, b], const ['hash-a', 'hash-b']),
        isNot(_key([a, b], const ['hash-a'])),
      );
    });

    test('отметки без узлов и узлы без отметок различимы', () {
      expect(_key(const [], const ['hash-a']), isNot(_key([a])));
    });
  });

  group('§331 в состав НЕ входят метаданные', () {
    test('ключ зависит только от узлов и отметок', () {




      final first = _key([a, b], const ['hash-a']);
      final second = _key([a, b], const ['hash-a']);
      expect(first, second);
      expect(first, contains('|'), reason: 'разделитель узлы|отметки на месте');
    });

    test('разделитель не даёт коллизии между секциями', () {


      expect(
        _key(const [], const ['x', 'y']),
        isNot(_key(const [], const ['x,y'])),
      );
    });
  });
}
