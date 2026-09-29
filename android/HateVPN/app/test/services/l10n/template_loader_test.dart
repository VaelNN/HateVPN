import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lxbox/models/parser_config.dart';
import 'package:lxbox/services/l10n/locale_controller.dart';
import 'package:lxbox/services/l10n/template_overlay.dart';
import 'package:lxbox/services/template_loader.dart';



void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TemplateLoader.invalidate();
    LocaleController.I.setting = 'en';
  });

  tearDown(() {
    TemplateLoader.invalidate();
    LocaleController.I.setting = 'system';
  });

  test('load() stores result under the tag read at start (mid-flight switch)',
      () async {
    LocaleController.I.setting = 'en';
    final inFlight = TemplateLoader.load();


    LocaleController.I.setting = 'ru';
    await inFlight;
    expect(TemplateLoader.cachedOrNull('en'), isNotNull);
    expect(TemplateLoader.cachedOrNull('ru'), isNull,
        reason: 'in-flight load старой локали не должен занять слот новой');

    await TemplateLoader.reload('ru');
    expect(TemplateLoader.cachedOrNull('ru'), isNotNull);

    expect(TemplateLoader.cachedOrNull('en'), isNotNull);
  });

  test('cachedOrNull defaults to effectiveTag', () async {
    LocaleController.I.setting = 'en';
    expect(TemplateLoader.cachedOrNull(), isNull);
    await TemplateLoader.load();
    expect(TemplateLoader.cachedOrNull(), isNotNull);
    LocaleController.I.setting = 'ru';
    expect(TemplateLoader.cachedOrNull(), isNull);
  });

  test('ru overlay localizes display fields, config subtree untouched',
      () async {
    LocaleController.I.setting = 'en';
    final en = await TemplateLoader.load();
    LocaleController.I.setting = 'ru';
    final ru = await TemplateLoader.load();
    expect(TemplateLoader.cachedOrNull('ru'), same(ru));


    SelectableRule byId(WizardTemplate t, String id) =>
        t.selectableRules.firstWhere((r) => r.presetId == id);
    expect(byId(en, 'block-ads').label, 'Block Ads');
    expect(byId(ru, 'block-ads').label, isNot(byId(en, 'block-ads').label));

    WizardVar varByName(WizardTemplate t, String name) =>
        t.vars.firstWhere((v) => v.name == name);
    expect(varByName(en, 'tls_fragment').title, 'TLS Fragment');
    expect(varByName(ru, 'tls_fragment').title,
        isNot(varByName(en, 'tls_fragment').title));


    expect(ru.groupTemplates.magicNodes['auto']?.title,
        isNot(en.groupTemplates.magicNodes['auto']?.title));


    expect(jsonEncode(ru.config), jsonEncode(en.config));
  });



  test('every declared template overlay asset loads and parses', () async {
    for (final tag in LocaleController.supportedTags) {
      if (tag == 'en') {



        final template = jsonDecode(
                await rootBundle.loadString('assets/wizard_template.json'))
            as Map<String, dynamic>;
        expect(TemplateOverlay.extract(template), isNotEmpty);
        continue;
      }
      final raw =
          await rootBundle.loadString('assets/l10n/$tag/template.json');
      expect(jsonDecode(raw), isA<Map<String, dynamic>>(),
          reason: 'overlay $tag/template.json обязан быть валидным JSON-объектом');
    }
  });
}
