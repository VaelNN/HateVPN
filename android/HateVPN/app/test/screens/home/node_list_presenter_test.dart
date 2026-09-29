import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/controllers/home_controller.dart';
import 'package:lxbox/controllers/subscription_controller.dart';
import 'package:lxbox/models/home_state.dart';
import 'package:lxbox/screens/home/node_filter_view_model.dart';
import 'package:lxbox/screens/home/node_list_presenter.dart';








void main() {
  TestWidgetsFlutterBinding.ensureInitialized();




  final configRaw = jsonEncode({
    'outbounds': [
      {'tag': 'A', 'type': 'vless', 'detour': 'B'},
      {'tag': 'B', 'type': 'vless'},
      {'tag': 'C', 'type': 'trojan'},
      {'tag': 'vpn-1-auto', 'type': 'urltest'},
      {'tag': 'direct', 'type': 'direct'},
    ],
  });
  const tags = ['A', 'B', 'C', 'vpn-1-auto', 'direct', 'Z'];

  late NodeFilterViewModel filter;
  late NodeListPresenter presenter;
  late HomeState state;

  setUp(() {
    filter = NodeFilterViewModel();
    presenter = NodeListPresenter(
      controller: HomeController(),
      subController: SubscriptionController(),
      filter: filter,
    );
    state = HomeState(
      configRaw: configRaw,
      nodes: tags,

      groupLabels: const {'vpn-1': 'VPN ①'},
      directionAutoTags: const {'vpn-1-auto'},
    );
  });

  tearDown(() => filter.dispose());

  test('sanity: B — detour-таргет, A/C — нет, Z отсутствует', () {
    expect(state.configModel['B']!.isDetour, true);
    expect(state.configModel['A']!.isDetour, false);
    expect(state.configModel['C']!.isDetour, false);
    expect(state.configModel['Z'], isNull);
  });

  test('старт (фильтр выкл): показаны ВСЕ, включая detour B', () {
    expect(filter.detourEnabled, false);
    final (matching, nonMatching) = presenter.splitNodes(tags, state);

    expect(matching, containsAll(['A', 'B', 'C', 'vpn-1-auto', 'direct', 'Z']));
    expect(nonMatching, isEmpty);
  });

  test('checkbox on (! on): скрыть detour — B убран, остальное видно', () {
    filter.setDetourEnabled(true);
    final (matching, _) = presenter.splitNodes(tags, state);
    expect(matching, containsAll(['A', 'C', 'vpn-1-auto', 'direct', 'Z']));
    expect(matching, isNot(contains('B')), reason: 'detour B скрыт');
  });

  test('checkbox on + ! off: только detour — B + control, A/C/Z скрыты', () {
    filter.setDetourEnabled(true);
    filter.toggleDetourHide();
    final (matching, _) = presenter.splitNodes(tags, state);
    expect(matching, contains('B'), reason: 'detour-нода видна');
    expect(matching, containsAll(['vpn-1-auto', 'direct']),
        reason: 'control-узлы не отсеиваются pool-ом');
    expect(matching, isNot(contains('A')));
    expect(matching, isNot(contains('C')));
    expect(matching, isNot(contains('Z')),
        reason: 'нет в configModel → non-detour (?? false) → скрыт в only-detour');
  });

  test('control-узлы видны во ВСЕХ detour-режимах (никогда не drop)', () {

    expect(presenter.splitNodes(tags, state).$1, containsAll(['vpn-1-auto', 'direct']));
    filter.setDetourEnabled(true);
    expect(presenter.splitNodes(tags, state).$1, containsAll(['vpn-1-auto', 'direct']));
    filter.toggleDetourHide();
    expect(presenter.splitNodes(tags, state).$1, containsAll(['vpn-1-auto', 'direct']));
  });

  test('computeListData (старт): displayList включает detour B', () {
    final data = presenter.computeListData(state);
    expect(data.displayList, contains('B'), reason: 'старт = показать всё');
    expect(data.matchingSet, containsAll(['vpn-1-auto', 'direct']));
  });


  group('§359 авто-узел подписки — обычная нода', () {


    final subRaw = jsonEncode({
      'outbounds': [
        {'tag': 'sub-🇫🇮 Helsinki', 'type': 'vless'},
        {'tag': 'sub-🇪🇺 Europe | Auto', 'type': 'urltest'},
        {
          'tag': 'sub-🇪🇺 Europe | Game | Auto',
          'type': 'urltest',
          'balancer': {'pool': 2},
        },
        {'tag': 'vpn-1', 'type': 'selector'},
        {'tag': 'vpn-1-auto', 'type': 'urltest'},
        {'tag': 'direct-out', 'type': 'direct'},
        {'tag': 'block', 'type': 'block'},
      ],
    });
    const subTags = [
      'sub-🇫🇮 Helsinki',
      'sub-🇪🇺 Europe | Auto',
      'sub-🇪🇺 Europe | Game | Auto',
      'vpn-1',
      'vpn-1-auto',
      'direct-out',
      'block',
    ];

    late HomeState s;
    setUp(() {
      s = HomeState(
        configRaw: subRaw,
        nodes: subTags,
        groupLabels: const {'vpn-1': 'VPN ①'},
        directionAutoTags: const {'vpn-1-auto'},
      );
    });

    test('isSystemControlTag: шасси — да, авто-узлы подписки — нет', () {
      expect(s.isSystemControlTag('vpn-1'), isTrue, reason: 'селектор Направления');
      expect(s.isSystemControlTag('vpn-1-auto'), isTrue, reason: 'его двойник');
      expect(s.isSystemControlTag('direct-out'), isTrue, reason: 'по типу');
      expect(s.isSystemControlTag('block'), isTrue, reason: 'по типу');
      expect(s.isSystemControlTag('sub-🇪🇺 Europe | Auto'), isFalse);
      expect(s.isSystemControlTag('sub-🇪🇺 Europe | Game | Auto'), isFalse);

      expect(s.isControlTag('sub-🇪🇺 Europe | Auto'), isTrue);
    });

    test('regex не по имени — авто-узел подписки УХОДИТ (сам баг §359)',
        () async {
      filter.onRegexChanged('🇫🇮');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final (matching, _) = presenter.splitNodes(subTags, s);
      expect(matching, contains('sub-🇫🇮 Helsinki'));
      expect(matching, isNot(contains('sub-🇪🇺 Europe | Auto')));
      expect(matching, isNot(contains('sub-🇪🇺 Europe | Game | Auto')));
      expect(matching, containsAll(['block', 'direct-out', 'vpn-1']),
          reason: 'шасси не отсеивается regex-ом — оно в matching всегда');
    });

    test('regex по имени — авто-узел подписки остаётся', () async {
      filter.onRegexChanged('Europe');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final (matching, _) = presenter.splitNodes(subTags, s);
      expect(matching, containsAll(
          ['sub-🇪🇺 Europe | Auto', 'sub-🇪🇺 Europe | Game | Auto']));
      expect(matching, isNot(contains('sub-🇫🇮 Helsinki')));
    });

    test('шасси видно при любом regex', () async {
      filter.onRegexChanged('нет-такого-узла');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final (matching, _) = presenter.splitNodes(subTags, s);
      expect(matching,
          containsAll(['vpn-1', 'vpn-1-auto', 'direct-out', 'block']));
      expect(matching.length, 4, reason: 'только шасси');
    });

    test('протокол авто-группы = urltest (не протокол выбранного члена)', () {
      expect(presenter.protocolOfTag('sub-🇪🇺 Europe | Auto', s), 'urltest');
      expect(presenter.protocolOfTag('sub-🇫🇮 Helsinki', s), 'vless');
    });

    test('транспорт авто-группы = режим (least_test / round_robin)', () {
      expect(presenter.variantsOfTag('sub-🇪🇺 Europe | Auto', s),
          {'least_test'});
      expect(presenter.variantsOfTag('sub-🇪🇺 Europe | Game | Auto', s),
          {'round_robin'}, reason: 'balancer{} ⇒ round_robin (§208)');
    });

    test('чип протокола urltest оставляет авто-узлы, vless — убирает', () {
      filter.toggleProtocol('urltest');
      var (matching, _) = presenter.splitNodes(subTags, s);
      expect(matching, containsAll(
          ['sub-🇪🇺 Europe | Auto', 'sub-🇪🇺 Europe | Game | Auto']));
      expect(matching, isNot(contains('sub-🇫🇮 Helsinki')));

      filter.toggleProtocol('urltest');
      filter.toggleProtocol('vless');
      (matching, _) = presenter.splitNodes(subTags, s);
      expect(matching, contains('sub-🇫🇮 Helsinki'));
      expect(matching, isNot(contains('sub-🇪🇺 Europe | Auto')));
    });

    test('чип транспорта round_robin отбирает пул-группу', () {
      filter.toggleVariant('round_robin');
      final (matching, _) = presenter.splitNodes(subTags, s);
      expect(matching, contains('sub-🇪🇺 Europe | Game | Auto'));
      expect(matching, isNot(contains('sub-🇪🇺 Europe | Auto')),
          reason: 'least_test-группа не проходит чип пула');
    });

    test('чипы фильтра предлагают urltest + режимы', () {
      final data = presenter.computeListData(s);
      expect(data.availableProtocols, contains('urltest'));
      expect(data.availableVariants, containsAll(['least_test', 'round_robin']));
    });

    test('лейблы без перевода: Auto / Fastest / Pool', () {
      expect(protoLabel('urltest'), 'Auto');
      expect(protoLabel('tailscale'), 'Tailscale');
      expect(autoModeLabel('least_test'), 'Fastest');
      expect(autoModeLabel('round_robin'), 'Pool');
    });
  });
}
