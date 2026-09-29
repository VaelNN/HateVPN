import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/services/parser/body_decoder.dart';
import 'package:lxbox/services/parser/parse_all.dart';

import 'engine_test_setup.dart';






void main() {


  setUpAll(loadEngineSections);




  Map<String, dynamic> vless(String addr,
          {String uuid = '8f2e1c44-0000-4000-8000-000000000001',
          int port = 443,
          String? tag,
          String? sni}) =>
      {
        'tag': tag ?? 'proxy',
        'protocol': 'vless',
        'settings': {
          'vnext': [
            {
              'address': addr,
              'port': port,
              'users': [
                {'id': uuid, 'encryption': 'none'}
              ],
            }
          ],
        },
        'streamSettings': {
          'network': 'tcp',
          'security': sni == null ? 'none' : 'tls',
          if (sni != null) 'tlsSettings': {'serverName': sni},
        },
      };

  Map<String, dynamic> element(String remarks, List<Map<String, dynamic>> obs) => {
        'remarks': remarks,
        'outbounds': [
          ...obs,
          {'tag': 'direct', 'protocol': 'freedom'},
          {'tag': 'block', 'protocol': 'blackhole'},
        ],
      };

  List<String> labelsOf(List<Map<String, dynamic>> elements) =>
      parseAll(decode(jsonEncode(elements))).map((n) => n.label).toList();






  group('P4/D-086 — дедуп по подписи записи', () {
    test('один сервер в двух элементах → один узел', () {
      final labels = labelsOf([
        element('🇩🇪 Германия', [vless('1.1.1.1')]),
        element('🇪🇺 Авто', [vless('1.1.1.1', tag: 'proxy-1-1-1-1')]),
      ]);
      expect(labels, ['🇩🇪 Германия']);
    });

    test('разный uuid при том же addr:port → два узла', () {
      final labels = labelsOf([
        element('A', [vless('1.1.1.1', uuid: 'u-1')]),
        element('B', [vless('1.1.1.1', uuid: 'u-2')]),
      ]);
      expect(labels, hasLength(2));
    });

    test('разный порт → два узла', () {
      final labels = labelsOf([
        element('A', [vless('1.1.1.1', port: 443)]),
        element('B', [vless('1.1.1.1', port: 8443)]),
      ]);
      expect(labels, hasLength(2));
    });

    test('D-086: разный SNI → ДВА узла (прежний ключ их схлопывал)', () {



      final labels = labelsOf([
        element('первый', [vless('1.1.1.1', sni: 'a.com')]),
        element('второй', [vless('1.1.1.1', sni: 'b.com')]),
      ]);
      expect(labels, ['первый', 'второй']);
    });

    test('D-086: байтовый дубль по-прежнему ОДИН узел', () {


      final labels = labelsOf([
        element('первый', [vless('1.1.1.1', sni: 'a.com')]),
        element('второй', [vless('1.1.1.1', sni: 'a.com', tag: 'other-tag')]),
      ]);
      expect(labels, ['первый'],
          reason: 'тег в подпись не входит: та же запись под другим именем');
    });

    test('D-086: разный ТРАНСПОРТ → два узла', () {
      final tcp = vless('1.1.1.1', sni: 'a.com');
      final ws = vless('1.1.1.1', sni: 'a.com');
      (ws['streamSettings'] as Map)['network'] = 'ws';
      (ws['streamSettings'] as Map)['wsSettings'] = {'path': '/w'};
      expect(labelsOf([element('tcp', [tcp]), element('ws', [ws])]),
          ['tcp', 'ws']);
    });

    test('D-086: прямая запись и BYPASS того же сервера → два узла', () {


      final direct = vless('1.1.1.1', sni: 'a.com');
      final viaRelay = vless('1.1.1.1', sni: 'a.com');
      ((viaRelay['streamSettings'] as Map)['sockopt'] =
          <String, dynamic>{'dialerProxy': 'relay'});
      final relay = {
        'tag': 'relay',
        'protocol': 'socks',
        'settings': {
          'servers': [
            {'address': '192.0.2.10', 'port': 61000},
          ],
        },
      };
      final labels = labelsOf([
        element('прямой', [direct]),
        element('через релей', [viaRelay, relay]),
      ]);
      expect(labels, ['прямой', 'через релей'],
          reason: 'путь дозвона входит в подпись — записи не одинаковы');
    });
  });

  group('P2 — от одиночных к многоузловым', () {
    test('имя даёт одиночный элемент, а не пул', () {


      final labels = labelsOf([
        element('🇪🇺 Авто', [
          vless('1.1.1.1', tag: 'proxy-1-1-1-1'),
          vless('2.2.2.2', tag: 'proxy-2-2-2-2'),
        ]),
        element('🇩🇪 Германия', [vless('1.1.1.1')]),
        element('🇫🇷 Франция', [vless('2.2.2.2')]),
      ]);
      expect(labels, ['🇩🇪 Германия', '🇫🇷 Франция']);
    });

    test('уникальный член пула выживает под именем пула', () {
      final labels = labelsOf([
        element('🇪🇺 Авто', [
          vless('1.1.1.1', tag: 'proxy-1-1-1-1'),
          vless('9.9.9.9', tag: 'proxy-9-9-9-9'),
        ]),
        element('🇩🇪 Германия', [vless('1.1.1.1')]),
      ]);



      expect(labels, ['🇪🇺 Авто proxy-9-9-9-9', '🇩🇪 Германия']);
    });

    test('сортировка стабильная: равные длины сохраняют порядок файла', () {
      final labels = labelsOf([
        element('первый', [vless('1.1.1.1')]),
        element('второй', [vless('2.2.2.2')]),
        element('третий', [vless('3.3.3.3')]),
      ]);
      expect(labels, ['первый', 'второй', 'третий']);
    });

    test('сортировка стабильна и за порогом quicksort (>32 элементов)', () {




      final els = <Map<String, dynamic>>[];
      for (var i = 0; i < 18; i++) {
        els.add(element('first-$i', [vless('10.0.0.$i')]));
        els.add(element('second-$i', [vless('10.0.0.$i', tag: 'proxy-alt')]));
      }
      final labels = labelsOf(els);
      expect(labels, [for (var i = 0; i < 18; i++) 'first-$i']);
    });
  });

  group('§342 — порядок файла сохраняется', () {
    test('пул первым в файле остаётся первым в списке, имена от одиночных',
        () {



      final labels = labelsOf([
        element('🇪🇺 Авто', [
          vless('1.1.1.1', tag: 'proxy-1-1-1-1'),
          vless('2.2.2.2', tag: 'proxy-2-2-2-2'),
        ]),
        element('🇩🇪 Германия', [vless('1.1.1.1')]),
        element('🇫🇷 Франция', [vless('2.2.2.2')]),
      ]);



      expect(labels, ['🇩🇪 Германия', '🇫🇷 Франция']);
    });

    test('одиночный после пула не всплывает наверх', () {
      final labels = labelsOf([
        element('🇳🇱 Нидерланды', [vless('5.5.5.5')]),
        element('🇪🇺 Авто', [
          vless('5.5.5.5', tag: 'proxy-5-5-5-5'),
          vless('9.9.9.9', tag: 'proxy-9-9-9-9'),
        ]),
        element('🇩🇪 Германия', [vless('3.3.3.3')]),
      ]);


      expect(labels, ['🇳🇱 Нидерланды', '🇪🇺 Авто proxy-9-9-9-9', '🇩🇪 Германия']);
    });
  });

  group('P3 — индекс имени не съезжает при пропуске дубля', () {
    test('выживший второй член не занимает имя первого', () {
      final labels = labelsOf([
        element('🇩🇪 Германия', [vless('1.1.1.1')]),
        element('Пул', [
          vless('1.1.1.1', tag: 'proxy-dup'),
          vless('7.7.7.7', tag: 'proxy-new'),
        ]),
      ]);

      expect(labels, ['🇩🇪 Германия', 'Пул proxy-new']);
    });
  });

  test('дедуп не пересекает границы подписок', () {


    final a = labelsOf([
      element('A', [vless('1.1.1.1')])
    ]);
    final b = labelsOf([
      element('B', [vless('1.1.1.1')])
    ]);
    expect(a, ['A']);
    expect(b, ['B']);
  });
}
