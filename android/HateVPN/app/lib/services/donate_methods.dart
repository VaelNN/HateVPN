import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'settings_storage.dart';












@immutable
class DonateMethod {
  const DonateMethod({
    required this.id,
    required this.kind,
    required this.title,
    required this.url,
    this.address,
    this.note,
  });

  final String id;


  final String kind;


  final String title;


  final String url;


  final String? address;


  final String? note;

  bool get isCrypto => kind == 'crypto';

  static DonateMethod? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'] as String? ?? '';
    final title = raw['title'] as String? ?? '';
    final url = raw['url'] as String? ?? '';
    if (id.isEmpty || title.isEmpty || url.isEmpty) return null;
    final kind = raw['kind'] as String? ?? 'link';
    final address = raw['address'] as String?;

    if (kind == 'crypto' && (address == null || address.isEmpty)) return null;
    return DonateMethod(
      id: id,
      kind: kind,
      title: title,
      url: url,
      address: address,
      note: raw['note'] as String?,
    );
  }
}

class DonateMethods {
  DonateMethods._();
  static final DonateMethods I = DonateMethods._();

  static const _asset = 'assets/donate.json';
  static const _url = String.fromEnvironment(
    'LXBOX_DONATE_URL',
    defaultValue:
        'https://raw.githubusercontent.com/Leadaxe/LxBox/main/app/assets/donate.json',
  );
  static const _httpTimeout = Duration(seconds: 10);
  static const _cacheKey = 'donate_cache_json';


  @visibleForTesting
  http.Client? httpClientForTesting;

  List<DonateMethod>? _cache;


  Future<List<DonateMethod>> load() async {
    final cached = _cache;
    if (cached != null) return cached;

    final owned = httpClientForTesting == null;
    final client = httpClientForTesting ?? http.Client();
    try {
      final resp = await client
          .get(Uri.parse(_url), headers: {'User-Agent': 'LxBox/1.x'})
          .timeout(_httpTimeout);
      if (resp.statusCode == 200) {
        final parsed = _parse(resp.body);
        if (parsed.isNotEmpty) {
          await SettingsStorage.setVar(_cacheKey, resp.body);
          return _cache = parsed;
        }
      }
    } catch (e) {
      AppLog.I.debug('DonateMethods: fetch failed ($e) — trying cache');
    } finally {
      if (owned) client.close();
    }
    final cachedRaw = await SettingsStorage.getVar(_cacheKey, '');
    if (cachedRaw.isNotEmpty) {
      final parsed = _parse(cachedRaw);
      if (parsed.isNotEmpty) return _cache = parsed;
    }


    try {
      return _cache = _parse(await rootBundle.loadString(_asset));
    } catch (e) {
      AppLog.I.debug('DonateMethods: bundled asset failed ($e)');
      return _cache = const [];
    }
  }

  static List<DonateMethod> _parse(String body) {
    try {
      final raw = jsonDecode(body);
      final list = (raw is Map ? raw['methods'] : null);
      if (list is! List) return const [];
      return [for (final m in list) ?DonateMethod.fromJson(m)];
    } catch (_) {
      return const [];
    }
  }

  @visibleForTesting
  void resetCacheForTesting() => _cache = null;
}
