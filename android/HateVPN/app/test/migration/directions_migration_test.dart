import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lxbox/models/direction.dart';
import 'package:lxbox/models/parser_config.dart';
import 'package:lxbox/services/settings_storage.dart';








void main() {
  late Directory tmp;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  String mainPath() => '${tmp.path}/lxbox_settings.json';




  GroupTemplates template() => GroupTemplates(
        direction: DirectionTemplate(
          include: const ['direct', 'auto'],
          options: const {'interrupt_exist_connections': true},
        ),
        auto: AutoTemplate(
          options: const {
            'url': 'https://cp.cloudflare.com/generate_204',
            'interval': '5m',
            'tolerance': 50,
          },
        ),
        defaultDirections: [
          DefaultDirection(tag: 'vpn-1', label: 'Главный', defaultEnabled: true),
          DefaultDirection(tag: 'vpn-2', label: 'Стриминг', defaultEnabled: false),
          DefaultDirection(tag: 'vpn-3', defaultEnabled: false),
        ],
      );

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = await Directory.systemTemp.createTemp('lxbox_directions_mig_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory' ||
          call.method == 'getApplicationDocumentsPath') {
        return tmp.path;
      }
      return null;
    });
    SettingsStorage.resetCacheForTesting();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    try {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    } catch (_) {}
  });



  Future<Map<String, dynamic>> readFile() async =>
      jsonDecode(await File(mainPath()).readAsString()) as Map<String, dynamic>;

  Future<void> seedFile(Map<String, dynamic> data) async {
    await File(mainPath()).writeAsString(jsonEncode(data));
    SettingsStorage.resetCacheForTesting();
  }

  test('fresh install: seed из template, enabled_groups пуст', () async {
    await seedFile({});
    await SettingsStorage.migrateDirectionsIfNeeded(template());

    final directions = await SettingsStorage.getDirections();

    expect(directions.map((c) => c.tag), ['vpn-1', 'vpn-2', 'vpn-3']);

    final vpn1 = directions.firstWhere((c) => c.tag == 'vpn-1');
    expect(vpn1.enabled, true);
    expect(vpn1.includeDirect, true);
    expect(vpn1.auto, isNotNull);
    expect(vpn1.auto!.url, 'https://cp.cloudflare.com/generate_204');
    expect(vpn1.auto!.idleTimeout, '30m');
    expect(vpn1.auto!.interruptExistConnections, false);
    expect(vpn1.interruptExistConnections, true);




    final vpn2 = directions.firstWhere((c) => c.tag == 'vpn-2');
    expect(vpn2.enabled, false);
    expect(vpn2.includeDirect, true);
    expect(vpn2.auto, isNotNull);

    final vpn3 = directions.firstWhere((c) => c.tag == 'vpn-3');
    expect(vpn3.includeDirect, true);
    expect(vpn3.defaultFilter, '');
    expect(vpn3.nodeFilter, '');
  });

  test('enabled_groups задаёт enabled (не defaultEnabled)', () async {

    await seedFile({
      'enabled_groups': ['vpn-3'],
    });
    await SettingsStorage.migrateDirectionsIfNeeded(template());

    final directions = await SettingsStorage.getDirections();
    expect(directions.firstWhere((c) => c.tag == 'vpn-1').enabled, true);
    expect(directions.firstWhere((c) => c.tag == 'vpn-2').enabled, false);
    expect(directions.firstWhere((c) => c.tag == 'vpn-3').enabled, true);
  });

  test('идемпотентность: повторный вызов — no-op', () async {
    await seedFile({});
    await SettingsStorage.migrateDirectionsIfNeeded(template());
    final first = await SettingsStorage.getDirections();


    await SettingsStorage.setDirections(
        first.where((c) => c.tag != 'vpn-2').toList());

    await SettingsStorage.migrateDirectionsIfNeeded(template());

    final after = await SettingsStorage.getDirections();
    expect(after.map((c) => c.tag), ['vpn-1', 'vpn-3']);
  });

  test('✨auto с нерезолвенными @var-плейсхолдерами → дефолты (не падает)',
      () async {




    final placeholderTemplate = GroupTemplates(
      direction: DirectionTemplate(include: const ['auto']),
      auto: AutoTemplate(
        options: const {
          'url': '@urltest_url',
          'interval': '@urltest_interval',
          'tolerance': '@urltest_tolerance',
        },
      ),
      defaultDirections: [DefaultDirection(tag: 'vpn-1')],
    );
    await seedFile({});
    await SettingsStorage.migrateDirectionsIfNeeded(placeholderTemplate);

    final directions = await SettingsStorage.getDirections();
    final vpn1 = directions.firstWhere((c) => c.tag == 'vpn-1');
    expect(vpn1.auto, isNotNull);



    const fallback = DirectionAuto();
    expect(vpn1.auto!.url, fallback.url);
    expect(vpn1.auto!.interval, fallback.interval);
    expect(vpn1.auto!.tolerance, fallback.tolerance);
  });

  test('✨auto с tolerance числом-в-строке → парсится', () async {
    final t = GroupTemplates(
      direction: DirectionTemplate(include: const ['auto']),
      auto: AutoTemplate(
        options: const {'tolerance': '30'},
      ),
      defaultDirections: [DefaultDirection(tag: 'vpn-1')],
    );
    await seedFile({});
    await SettingsStorage.migrateDirectionsIfNeeded(t);
    final vpn1 = (await SettingsStorage.getDirections())
        .firstWhere((c) => c.tag == 'vpn-1');
    expect(vpn1.auto!.tolerance, 30);
  });

  test('directions уже есть → миграция no-op', () async {
    await seedFile({
      'directions': [
        {'tag': 'vpn-1', 'label': 'Custom', 'enabled': true},
      ],
    });
    await SettingsStorage.migrateDirectionsIfNeeded(template());

    final directions = await SettingsStorage.getDirections();
    expect(directions.length, 1);
    expect(directions.first.label, 'Custom');
  });




  group('§393 A2 legacy-ключи', () {
    test('fresh-seed кладёт directions + directions_migrated, легаси нет',
        () async {
      await seedFile({});
      await SettingsStorage.migrateDirectionsIfNeeded(template());

      final raw = await readFile();
      expect(raw['directions'], isA<List>());
      expect(raw['directions_migrated'], true);
      expect(raw.containsKey('channels'), isFalse);
      expect(raw.containsKey('channels_migrated'), isFalse);
    });

    test('channels → directions: список идентичен, легаси-пара удалена',
        () async {

      final legacy = [
        {
          'tag': 'vpn-1',
          'label': 'Мой первый',
          'enabled': true,
          'include_direct': true,
          'node_filter': 'DE|NL',
        },
        {'tag': 'vpn-2', 'label': 'Стриминг', 'enabled': false},
      ];
      await seedFile({
        'channels': legacy,
        'channels_migrated': true,
        'route_final': 'vpn-2',
      });
      await SettingsStorage.migrateDirectionsIfNeeded(template());

      final raw = await readFile();

      expect(raw['directions'], legacy);
      expect(raw['directions_migrated'], true);
      expect(raw.containsKey('channels'), isFalse);
      expect(raw.containsKey('channels_migrated'), isFalse);

      expect(raw['route_final'], 'vpn-2');

      final directions = await SettingsStorage.getDirections();
      expect(directions.map((c) => c.tag), ['vpn-1', 'vpn-2']);
      expect(directions[0].label, 'Мой первый');
      expect(directions[0].nodeFilter, 'DE|NL');
      expect(directions[1].enabled, false);
    });

    test('channels без channels_migrated (прерванная установка) тоже переносится',
        () async {
      await seedFile({
        'channels': [
          {'tag': 'vpn-1', 'label': 'Only', 'enabled': true},
        ],
      });
      await SettingsStorage.migrateDirectionsIfNeeded(template());

      final raw = await readFile();
      expect((raw['directions'] as List), hasLength(1));
      expect(raw['directions_migrated'], true);
      expect(raw.containsKey('channels'), isFalse);
    });

    test('мигрировано-пусто: channels_migrated без channels → НЕ пересеивать',
        () async {

      await seedFile({'channels_migrated': true});
      await SettingsStorage.migrateDirectionsIfNeeded(template());

      expect(await SettingsStorage.getDirections(), isEmpty);
      final raw = await readFile();
      expect(raw['directions_migrated'], true);
      expect(raw.containsKey('channels_migrated'), isFalse);
      expect(raw.containsKey('directions'), isFalse);
    });

    test('directions_migrated без directions → тоже не пересеивать', () async {
      await seedFile({'directions_migrated': true});
      await SettingsStorage.migrateDirectionsIfNeeded(template());
      expect(await SettingsStorage.getDirections(), isEmpty);
    });

    test('хвост легаси рядом с новым ключом вычищается', () async {

      await seedFile({
        'directions': [
          {'tag': 'vpn-1', 'label': 'New', 'enabled': true},
        ],
        'channels': [
          {'tag': 'vpn-9', 'label': 'Stale', 'enabled': true},
        ],
        'channels_migrated': true,
      });
      await SettingsStorage.migrateDirectionsIfNeeded(template());

      final raw = await readFile();
      expect(raw.containsKey('channels'), isFalse);
      expect(raw.containsKey('channels_migrated'), isFalse);
      expect(raw['directions_migrated'], true);

      final directions = await SettingsStorage.getDirections();
      expect(directions.map((c) => c.tag), ['vpn-1']);
    });

    test('legacy-цепочка enabled_groups: старейшая установка сеется по ней',
        () async {

      await seedFile({
        'enabled_groups': ['vpn-3'],
      });
      await SettingsStorage.migrateDirectionsIfNeeded(template());

      final directions = await SettingsStorage.getDirections();
      expect(directions.firstWhere((c) => c.tag == 'vpn-1').enabled, true);
      expect(directions.firstWhere((c) => c.tag == 'vpn-2').enabled, false);
      expect(directions.firstWhere((c) => c.tag == 'vpn-3').enabled, true);
      final raw = await readFile();
      expect(raw['directions_migrated'], true);
      expect(raw.containsKey('channels'), isFalse);
    });

    test('второй вызов после переноса не ПЕРЕСЕИВАЕТ шаблон — только '
        'восстанавливает vpn-1 (§393 A3)', () async {
      await seedFile({
        'channels': [
          {'tag': 'vpn-1', 'label': 'Keep', 'enabled': true},
          {'tag': 'vpn-7', 'label': 'Seven', 'enabled': true},
        ],
      });
      await SettingsStorage.migrateDirectionsIfNeeded(template());

      await SettingsStorage.setDirections(const []);
      await SettingsStorage.migrateDirectionsIfNeeded(template());




      expect((await SettingsStorage.getDirections()).map((c) => c.tag),
          ['vpn-1']);
    });
  });

  group('CRUD после миграции', () {
    setUp(() async {
      await seedFile({});
      await SettingsStorage.migrateDirectionsIfNeeded(template());
    });

    test('addDirection — первый свободный vpn-N', () async {

      final ch = await SettingsStorage.addDirection(label: 'Новый');
      expect(ch.tag, 'vpn-4');
      expect(ch.label, 'Новый');
      expect((await SettingsStorage.getDirections()).length, 4);
    });

    test('§198 — addDirection без label → дефолт с кружком (VPN ④)', () async {

      final ch = await SettingsStorage.addDirection();
      expect(ch.tag, 'vpn-4');
      expect(ch.label, 'VPN ④');
    });

    test('§393 A3 — лимита на количество нет: 11-е и 12-е создаются', () async {
      for (var i = 4; i <= 12; i++) {
        await SettingsStorage.addDirection();
      }
      final all = await SettingsStorage.getDirections();
      expect(all.length, 12);
      expect(all.map((c) => c.tag).toList(),
          [for (var i = 1; i <= 12; i++) 'vpn-$i']);

      expect(all[9].label, 'VPN ⑩');
      expect(all[10].label, 'VPN 11');
      expect(all[11].label, 'VPN 12');
    });

    test('§393 A3 — addDirection с кастомным тегом', () async {
      final ch = await SettingsStorage.addDirection(tag: 'ru-exit');
      expect(ch.tag, 'ru-exit');

      expect(ch.label, 'ru-exit');

      expect((await SettingsStorage.addDirection()).tag, 'vpn-4');
    });

    test('§393 A3 — дубль / пустой / служебный тег → StateError', () async {
      expect(() => SettingsStorage.addDirection(tag: 'vpn-2'), throwsStateError);
      expect(() => SettingsStorage.addDirection(tag: '   '), throwsStateError);
      expect(() => SettingsStorage.addDirection(tag: 'direct-out'),
          throwsStateError);
      expect(() => SettingsStorage.addDirection(tag: 'block'), throwsStateError);
      expect(() => SettingsStorage.addDirection(tag: 'reject'), throwsStateError);
      expect(() => SettingsStorage.addDirection(tag: 'dns-out'), throwsStateError);
    });

    test('§393 A3 — коллизия с auto-двойником в обе стороны', () async {

      expect(() => SettingsStorage.addDirection(tag: 'vpn-1-auto'),
          throwsStateError);

      await SettingsStorage.addDirection(tag: 'exit-auto');
      expect(() => SettingsStorage.addDirection(tag: 'exit'), throwsStateError);
    });

    test('deleteDirection vpn-1 throws', () async {
      expect(() => SettingsStorage.deleteDirection('vpn-1'), throwsStateError);
    });

    test('deleteDirection переводит route_final → vpn-1', () async {
      await SettingsStorage.saveRouteFinal('vpn-2');
      await SettingsStorage.deleteDirection('vpn-2');
      expect(await SettingsStorage.getRouteFinal(), 'vpn-1');
      expect((await SettingsStorage.getDirections()).map((c) => c.tag),
          ['vpn-1', 'vpn-3']);
    });

    test('route_final на другое Направление не трогается', () async {
      await SettingsStorage.saveRouteFinal('vpn-3');
      await SettingsStorage.deleteDirection('vpn-2');
      expect(await SettingsStorage.getRouteFinal(), 'vpn-3');
    });

    test('updateDirection — несуществующий tag throws', () async {
      const ghost = Direction(tag: 'vpn-9', label: 'ghost');
      expect(() => SettingsStorage.updateDirection(ghost), throwsStateError);
    });
  });





  group('§327 seed auto-Направления по @var-плейсхолдерам', () {
    GroupTemplates placeholderTemplate() => GroupTemplates(
          direction: DirectionTemplate(
            include: const ['direct', 'auto'],
            options: const {'interrupt_exist_connections': true},
          ),
          auto: AutoTemplate(
            options: const {
              'url': '@urltest_url',
              'interval': '@urltest_interval',
              'tolerance': '@urltest_tolerance',
            },
          ),
          defaultDirections: [
            DefaultDirection(tag: 'vpn-1', label: 'Main', defaultEnabled: true),
          ],
        );

    const varDefaults = {
      'urltest_url': 'https://example.test/generate_204',
      'urltest_interval': '15m',
      'urltest_tolerance': '30',
    };

    test('плейсхолдеры резолвятся в default_value шаблона', () async {
      await SettingsStorage.migrateDirectionsIfNeeded(
        placeholderTemplate(),
        varDefaults: varDefaults,
      );
      final auto = (await SettingsStorage.getDirections()).first.auto!;

      expect(auto.tolerance, 30);
      expect(auto.interval, '15m');
      expect(auto.url, 'https://example.test/generate_204');
    });

    test('без varDefaults — дефолты DirectionAuto, а не литералы', () async {

      await SettingsStorage.migrateDirectionsIfNeeded(placeholderTemplate());
      final auto = (await SettingsStorage.getDirections()).first.auto!;
      const fallback = DirectionAuto();

      expect(auto.tolerance, fallback.tolerance);
      expect(auto.interval, fallback.interval);
      expect(auto.url, fallback.url);
    });

    test('явное значение в options побеждает default_value', () async {
      await SettingsStorage.migrateDirectionsIfNeeded(
        GroupTemplates(
          direction: DirectionTemplate(include: const ['direct', 'auto']),
          auto: AutoTemplate(
            options: const {'interval': '3m', 'tolerance': 77},
          ),
          defaultDirections: [DefaultDirection(tag: 'vpn-1', defaultEnabled: true)],
        ),
        varDefaults: varDefaults,
      );
      final auto = (await SettingsStorage.getDirections()).first.auto!;

      expect(auto.tolerance, 77);
      expect(auto.interval, '3m');
    });
  });












  group('§393 A3 — vpn-1 восстанавливается миграцией', () {
    test('импорт списка без vpn-1: vpn-1 вставлен ПЕРВЫМ, чужой тег цел',
        () async {
      await seedFile({
        'directions': [
          {'tag': 'ru-exit', 'label': 'Россия', 'enabled': true},
        ],
        'directions_migrated': true,
      });
      await SettingsStorage.migrateDirectionsIfNeeded(template());

      final directions = await SettingsStorage.getDirections();
      expect(directions.map((c) => c.tag), ['vpn-1', 'ru-exit'],
          reason: 'vpn-1 — умолчание всех heal\'ов, ему быть первым');
      expect(directions.first.enabled, true);
      expect(directions.first.label, defaultLabelForTag('vpn-1'));

      expect(directions[1].label, 'Россия');
      expect(directions[1].enabled, true);
    });

    test('vpn-1 на месте → ветка 1 остаётся no-op (файл не переписан)',
        () async {
      await seedFile({

        'storage_version': 1,
        'directions': [
          {'tag': 'vpn-1', 'label': 'Keep', 'enabled': true},
          {'tag': 'ru-exit', 'label': 'Россия', 'enabled': true},
        ],
        'directions_migrated': true,
      });
      final before = await File(mainPath()).readAsString();
      await SettingsStorage.migrateDirectionsIfNeeded(template());
      expect(await File(mainPath()).readAsString(), before,
          reason: 'самый частый путь не должен стоить записи на диск');
    });

    test('vpn-1 НЕ на первом месте — порядок пользователя не трогаем',
        () async {
      await seedFile({
        'directions': [
          {'tag': 'ru-exit', 'label': 'Россия', 'enabled': true},
          {'tag': 'vpn-1', 'label': 'Keep', 'enabled': true},
        ],
        'directions_migrated': true,
      });
      await SettingsStorage.migrateDirectionsIfNeeded(template());
      expect((await SettingsStorage.getDirections()).map((c) => c.tag),
          ['ru-exit', 'vpn-1'],
          reason: 'инвариант — «vpn-1 существует», а не «vpn-1 первый»');
    });

    test('легаси-перенос (ветка 2) списка без vpn-1 тоже чинится', () async {
      await seedFile({
        'channels': [
          {'tag': 'ru-exit', 'label': 'Россия', 'enabled': true},
        ],
      });
      await SettingsStorage.migrateDirectionsIfNeeded(template());
      expect((await SettingsStorage.getDirections()).map((c) => c.tag),
          ['vpn-1', 'ru-exit']);
      final raw = await readFile();
      expect(raw.containsKey('channels'), isFalse);
      expect(raw['directions_migrated'], true);
    });

    test('мусор в списке (не-Map записи) не роняет проверку', () async {
      await seedFile({
        'directions': ['garbage', 42, null],
        'directions_migrated': true,
      });
      await SettingsStorage.migrateDirectionsIfNeeded(template());
      expect((await SettingsStorage.getDirections()).map((c) => c.tag),
          ['vpn-1']);
    });
  });
}
