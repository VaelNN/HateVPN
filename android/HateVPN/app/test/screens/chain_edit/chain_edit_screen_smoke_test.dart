import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/config_node.dart';
import 'package:lxbox/models/direction.dart';
import 'package:lxbox/models/node_link.dart';
import 'package:lxbox/models/source_chain.dart';
import 'package:lxbox/screens/chain_edit_screen.dart';
import 'package:lxbox/services/contract/chain_strip.dart';

import '../../contract_paths.dart';






ParsedConfig _config() => ParsedConfig.parse(jsonEncode({
      'outbounds': [
        {'tag': 'home', 'type': 'vless'},
        {'tag': 'de-exit', 'type': 'vless'},
        {
          'tag': 'de-reality',
          'type': 'vless',
          'server': '203.0.113.7',
          'server_port': 443,
          'uuid': 'b831381d-6324-4d53-ad4f-8cda48b30811',
          'tls': {
            'enabled': true,
            'server_name': 'example.com',
            'utls': {'enabled': true, 'fingerprint': 'chrome'},
            'reality': {
              'enabled': true,
              'public_key': 'jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0',
              'short_id': '0123abcd',
            },
          },
        },
      ],
    }));

Widget _host(SourceChain chain) => MaterialApp(
      home: ChainEditScreen(
        initial: chain,
        config: _config(),
        directions: const [Direction(tag: 'vpn-1', label: 'vpn-1')],
        chains: [chain],
      ),
    );

void main() {
  setUpAll(loadTestRegistry);

  testWidgets('форма поднимается и показывает позиции', (tester) async {
    await tester.pumpWidget(_host(
        const SourceChain(tag: 'via-de', hops: [NodeLink(tag: 'home'), NodeLink(tag: 'de-exit')])));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(find.text('de-exit'), findsOneWidget);
  });

  testWidgets('одна позиция — кнопка сохранения заперта', (tester) async {
    await tester
        .pumpWidget(_host(const SourceChain(tag: 'via-de', hops: [NodeLink(tag: 'home')])));
    await tester.pumpAndSettle();
    final save = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.check));
    expect(save.onPressed, isNull);
  });

  testWidgets('две живые позиции — сохранение доступно', (tester) async {
    await tester.pumpWidget(_host(
        const SourceChain(tag: 'via-de', hops: [NodeLink(tag: 'home'), NodeLink(tag: 'de-exit')])));
    await tester.pumpAndSettle();
    final save = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.check));
    expect(save.onPressed, isNotNull);
  });

  testWidgets('reorder-колбэк меняет порядок пакета', (tester) async {
    await tester.pumpWidget(_host(
        const SourceChain(tag: 'via-de', hops: [NodeLink(tag: 'home'), NodeLink(tag: 'de-exit')])));
    await tester.pumpAndSettle();



    final list = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView));
    list.onReorderItem!(0, 1);
    await tester.pumpAndSettle();

    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    final titles = [
      for (final t in tiles)
        if (t.title is Text) (t.title as Text).data,
    ];
    expect(titles.indexOf('de-exit'), lessThan(titles.indexOf('home')));
  });



  testWidgets('снятый tls.utls на reality-звене сохранение НЕ запирает',
      (tester) async {
    await tester.pumpWidget(_host(const SourceChain(
      tag: 'via-de',
      hops: [NodeLink(tag: 'home'), NodeLink(tag: 'de-reality')],
      strip: {'tls.utls': true},
    )));
    await tester.pumpAndSettle();
    final save = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.check));
    expect(save.onPressed, isNotNull);
  });

  testWidgets('пикер позиций открывается и не предлагает уже занятые',
      (tester) async {
    await tester
        .pumpWidget(_host(const SourceChain(tag: 'via-de', hops: [NodeLink(tag: 'home')])));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();


    expect(find.text('home'), findsOneWidget);
    expect(find.text('de-exit'), findsOneWidget);
  });

  testWidgets('Advanced раскрывается: idle_timeout и каталог strip на месте',
      (tester) async {
    await tester.pumpWidget(_host(
        const SourceChain(tag: 'via-de', hops: [NodeLink(tag: 'home'), NodeLink(tag: 'de-exit')])));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();

    expect(chainStripKeys(), isNotEmpty);
    for (final key in chainStripKeys()) {
      expect(find.text(key), findsOneWidget);
    }
  });

  testWidgets('галка каталога трёхзначна: не тронута → null', (tester) async {
    await tester.pumpWidget(_host(
        const SourceChain(tag: 'via-de', hops: [NodeLink(tag: 'home'), NodeLink(tag: 'de-exit')])));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    final boxes = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .toList();
    expect(boxes, hasLength(chainStripKeys().length));


    expect(boxes.every((b) => b.value == null), isTrue);
  });

  testWidgets('свой тег среди тегов конфига конфликтом не считается',
      (tester) async {


    await tester.pumpWidget(MaterialApp(
      home: ChainEditScreen(
        initial: const SourceChain(tag: 'via-de', hops: [NodeLink(tag: 'home'), NodeLink(tag: 'de-exit')]),
        config: ParsedConfig.parse(jsonEncode({
          'outbounds': [
            {'tag': 'home', 'type': 'vless'},
            {'tag': 'de-exit', 'type': 'vless'},
            {
              'tag': 'via-de',
              'type': 'chain',
              'outbounds': ['home', 'de-exit'],
            },
          ],
        })),
        directions: const [Direction(tag: 'vpn-1', label: 'vpn-1')],
        chains: const [SourceChain(tag: 'via-de', hops: [NodeLink(tag: 'home'), NodeLink(tag: 'de-exit')])],
      ),
    ));
    await tester.pumpAndSettle();
    final save = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.check));
    expect(save.onPressed, isNotNull);
  });
}
