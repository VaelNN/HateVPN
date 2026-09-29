




import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' show Intl;

import '../rule_name_resolver.dart';
import '../settings_storage.dart';
import '../template_loader.dart';
import 'get_local_text.dart';
import 'plural_resolver.dart';





GetLocalText get getLocalText => LocaleController.I.text;

class LocaleController extends ChangeNotifier with WidgetsBindingObserver {
  static final LocaleController I = LocaleController();

  static const supportedTags = ['en', 'ru', 'zh'];
  static const supportedLocales = [
    Locale('en'),
    Locale('ru'),
    Locale('zh'),
  ];


  String setting = 'system';

  Locale? _lastApplied;





  GetLocalText _text = GetLocalText(null, const EnPluralResolver());
  GetLocalText get text => _text;

  Locale get effective => setting == 'system'
      ? _resolve(PlatformDispatcher.instance.locale)
      : Locale(setting);

  String get effectiveTag => effective.languageCode;

  static Locale _resolve(Locale device) =>
      supportedTags.contains(device.languageCode)
          ? Locale(device.languageCode)
          : const Locale('en');














  Future<void> bootstrap(String stored) async {
    setting = stored;
    final loc = effective;
    _lastApplied = loc;

    Intl.defaultLocale = loc.toLanguageTag();
    try {
      _text = await _buildGetLocalText(loc.languageCode);
    } catch (_) {

    }
  }





  @override
  void didChangeLocales(List<Locale>? locales) {
    if (setting != 'system') return;
    final now = effective;

    if (now != _lastApplied) unawaited(_applyLocale(now));
  }

  Future<void> set(String v) async {
    setting = SettingsStorage.appLanguageValues.contains(v) ? v : 'system';

    await SettingsStorage.setAppLanguage(setting);
    await _applyLocale(effective);
  }



  Future<void> reloadFromStorage() async {
    final stored = await SettingsStorage.getAppLanguage();
    if (stored == setting && _lastApplied == effective) return;
    setting = stored;
    await _applyLocale(effective);
  }

  Future<void> _applyLocale(Locale loc) async {
    _lastApplied = loc;

    Intl.defaultLocale = loc.toLanguageTag();




    try {


      _text = await _buildGetLocalText(loc.languageCode);


      await TemplateLoader.reload(loc.languageCode);

      RuleNameResolver.I
          .relocalize(TemplateLoader.cachedOrNull(loc.languageCode));


      await SettingsStorage.flushToDisk();
    } catch (_) {

    }
    notifyListeners();
  }







  static Future<GetLocalText> _buildGetLocalText(String tag) async {
    final resolver = switch (tag) {
      'ru' => const RuPluralResolver(),
      'zh' => const ZhPluralResolver(),
      _ => const EnPluralResolver(),
    };
    if (tag == 'en') return GetLocalText(null, resolver);
    try {
      final raw = await rootBundle.loadString('assets/l10n/$tag/ui.json');
      final dict = jsonDecode(raw) as Map<String, dynamic>;
      return GetLocalText(dict, resolver);
    } on FlutterError {

      return GetLocalText(null, resolver);
    }
  }
}
