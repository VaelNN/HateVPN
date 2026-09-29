import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../app_log.dart';
import '../project_links.dart';
import '../settings_storage.dart';
import '../update_checker.dart' show isNewer;
import '../version_info.dart';
import 'active_time_tracker.dart';
import 'support_state.dart';























@immutable
class SupportLinkSpec {
  const SupportLinkSpec(this.label, this.url, {this.markRead = true});

  final String label;
  final String url;
  final bool markRead;
}

@immutable
class SupportContent {
  const SupportContent({
    required this.title,
    required this.message,
    required this.links,
  });

  final String title;
  final String message;



  final List<SupportLinkSpec> links;




  SupportContent expandLinks() => SupportContent(
        title: ProjectLinks.expand(title),
        message: ProjectLinks.expand(message),
        links: [
          for (final l in links)
            SupportLinkSpec(
              ProjectLinks.expand(l.label),
              ProjectLinks.expand(l.url),
              markRead: l.markRead,
            ),
        ],
      );

  static SupportContent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final title = raw['title'] as String? ?? '';
    final message = raw['message'] as String? ?? '';
    if (title.isEmpty || message.isEmpty) return null;
    final links = <SupportLinkSpec>[];
    for (final l in raw['links'] as List? ?? const []) {
      if (l is! Map) continue;
      final label = l['label'] as String? ?? '';
      final url = l['url'] as String? ?? '';
      if (label.isEmpty || url.isEmpty) continue;
      links.add(SupportLinkSpec(label, url, markRead: l['mark_read'] != false));
    }
    return SupportContent(title: title, message: message, links: links);
  }
}

@immutable
class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.sinceVersion,
    required this.skip,
    required this.minActiveHours,
    required this.minSessionMinutes,
    required this.i18n,
    this.readDelaySeconds = 10,
  });


  final String id;





  final String sinceVersion;


  final bool skip;



  final int minActiveHours;



  final int minSessionMinutes;



  final int readDelaySeconds;



  final Map<String, SupportContent> i18n;


  SupportContent contentFor(String tag) => i18n[tag] ?? i18n['en']!;

  static SupportMessage? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'] as String? ?? '';
    if (id.isEmpty) return null;
    final i18n = <String, SupportContent>{};
    final i18nRaw = raw['i18n'];
    if (i18nRaw is Map) {
      for (final e in i18nRaw.entries) {
        final c = SupportContent.fromJson(e.value);
        if (c != null) i18n[e.key.toString()] = c;
      }
    }
    if (!i18n.containsKey('en')) return null;
    return SupportMessage(
      id: id,
      sinceVersion: raw['since_version'] as String? ?? '0.0.0',
      skip: raw['skip'] == true,
      minActiveHours: (raw['min_active_hours'] as num?)?.toInt() ?? 3,
      minSessionMinutes: (raw['min_session_minutes'] as num?)?.toInt() ?? 5,
      readDelaySeconds: (raw['read_delay_seconds'] as num?)?.toInt() ?? 10,
      i18n: i18n,
    );
  }
}

@immutable
class SupportFeed {
  const SupportFeed({required this.snoozeActiveHours, required this.messages});


  final int snoozeActiveHours;


  final List<SupportMessage> messages;

  static SupportFeed? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final list = raw['messages'];
    if (list is! List) return null;
    final messages = <SupportMessage>[];
    for (final m in list) {
      final parsed = SupportMessage.fromJson(m);
      if (parsed != null) messages.add(parsed);
    }
    return SupportFeed(
      snoozeActiveHours: (raw['snooze_active_hours'] as num?)?.toInt() ?? 10,
      messages: messages,
    );
  }
}




@immutable
class SupportPreviewRequest {
  const SupportPreviewRequest({
    required this.feed,
    required this.message,
    required this.dryRun,
  });

  final SupportFeed feed;
  final SupportMessage message;
  final bool dryRun;
}

class SupportMessageService {
  SupportMessageService._();
  static final SupportMessageService I = SupportMessageService._();







  static const _url = String.fromEnvironment(
    'LXBOX_SUPPORT_URL',
    defaultValue:
        'https://raw.githubusercontent.com/Leadaxe/LxBox/main/app/assets/support.json',
  );
  static const _httpTimeout = Duration(seconds: 10);


  @visibleForTesting
  http.Client? httpClientForTesting;


  @visibleForTesting
  String? appVersionForTesting;

  String get _appVersion => appVersionForTesting ?? VersionInfo.I.version;

  static const _asset = 'assets/support.json';



  Future<SupportFeed?> fetchOrCached() async {
    if (await SettingsStorage.getAutoCheckUpdates()) {
      final fresh = await _fetch();
      if (fresh != null) return fresh;
    }
    final cached = await SupportState.I.getString('cache_json');
    if (cached.isNotEmpty) {
      final f = _parse(cached);
      if (f != null) return f;
    }


    try {
      return _parse(await rootBundle.loadString(_asset));
    } catch (e) {
      AppLog.I.debug('SupportMessage: bundled asset failed ($e)');
      return null;
    }
  }

  Future<SupportFeed?> _fetch() async {


    final owned = httpClientForTesting == null;
    final client = httpClientForTesting ?? http.Client();
    try {
      final resp = await client
          .get(Uri.parse(_url), headers: {'User-Agent': 'LxBox/1.x'})
          .timeout(_httpTimeout);
      if (resp.statusCode == 200) {
        final f = _parse(resp.body);
        if (f != null) {
          await SupportState.I.set('cache_json', resp.body);
          return f;
        }
      }
    } catch (e) {
      AppLog.I.debug('SupportMessage: fetch failed ($e) — trying cache');
    } finally {
      if (owned) client.close();
    }
    return null;
  }

  static SupportFeed? _parse(String body) {
    try {
      return SupportFeed.fromJson(jsonDecode(body));
    } catch (_) {
      return null;
    }
  }





  Future<void> _syncBaseline() async {
    final ver = _appVersion;
    if (await SupportState.I.getString('baseline_version') == ver) return;
    await SupportState.I.setAll({
      'baseline_seconds': await ActiveTimeTracker.I.totalSeconds(),
      'baseline_version': ver,
    });
  }








  static SupportMessage? pick({
    required SupportFeed feed,
    required String appVersion,
    required Map<String, String> read,
    required int totalActiveSeconds,
    required int baselineSeconds,
    required int currentSessionSeconds,
    required int snoozeAfterSeconds,
  }) {
    if (totalActiveSeconds < snoozeAfterSeconds) return null;
    for (final m in feed.messages) {
      if (m.skip) continue;
      if (isNewer(m.sinceVersion, appVersion)) continue;
      final readAt = read[m.id];
      if (readAt != null && !isNewer(m.sinceVersion, readAt)) continue;
      if (currentSessionSeconds < m.minSessionMinutes * 60) return null;
      if (totalActiveSeconds - baselineSeconds < m.minActiveHours * 3600) {
        return null;
      }
      return m;
    }
    return null;
  }



  Future<SupportMessage?> nextToShow(
    SupportFeed feed, {
    required int currentSessionSeconds,
  }) async {
    await _syncBaseline();
    return pick(
      feed: feed,
      appVersion: _appVersion,
      read: await SupportState.I.getStringMap('read'),
      totalActiveSeconds: await ActiveTimeTracker.I.totalSeconds(),
      baselineSeconds: await SupportState.I.getInt('baseline_seconds'),
      currentSessionSeconds: currentSessionSeconds,
      snoozeAfterSeconds: await SupportState.I.getInt('snooze_after_seconds'),
    );
  }




  Future<void> markRead(SupportMessage m) async {
    final read = await SupportState.I.getStringMap('read');
    read[m.id] = _appVersion;
    await SupportState.I.setAll({
      'read': read,
      'baseline_seconds': await ActiveTimeTracker.I.totalSeconds(),
    });
  }




  Future<void> snooze(SupportFeed feed) async {
    final total = await ActiveTimeTracker.I.totalSeconds();
    await SupportState.I
        .set('snooze_after_seconds', total + feed.snoozeActiveHours * 3600);
  }
}
