import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../models/node_spec.dart';
import '../../models/node_warning.dart';
import '../../models/server_list.dart';
import '../../models/subscription_meta.dart';
import '../parser/body_decoder.dart';
import '../parser/engine/decoders.dart' show decodeUtf8Lenient;
import '../parser/parse_all.dart';
import 'subscription_identity.dart';
import 'user_agent.dart';



sealed class SubscriptionSource {
  const SubscriptionSource();
}

final class UrlSource extends SubscriptionSource {
  final String url;








  final String? userAgent;




  final SubscriptionIdentityOverride? identity;

  final Duration timeout;
  const UrlSource(
    this.url, {
    this.userAgent,
    this.identity,


    this.timeout = const Duration(seconds: 9),
  });
}

final class FileSource extends SubscriptionSource {
  final File file;
  const FileSource(this.file);
}

final class ClipboardSource extends SubscriptionSource {
  final String contents;
  const ClipboardSource(this.contents);
}

final class InlineSource extends SubscriptionSource {
  final String body;
  const InlineSource(this.body);
}

final class QrSource extends SubscriptionSource {
  final String content;
  const QrSource(this.content);
}

class FetchResult {
  final String body;
  final SubscriptionMeta? meta;
  final Map<String, String> headers;
  const FetchResult(this.body, [this.meta, this.headers = const {}]);
}

class ParseResult {
  final List<NodeSpec> nodes;
  final SubscriptionMeta? meta;
  final DecodedBody decoded;
  final String rawBody;
  final Map<String, String> headers;






  final List<NodeWarning> dropped;

  const ParseResult(this.nodes, this.decoded,
      [this.meta,
      this.rawBody = '',
      this.headers = const {},
      this.dropped = const []]);
}






Future<ParseResult> parseFromSource(SubscriptionSource source,
    {http.Client? client}) async {


  final owned = client == null;
  final c = client ?? http.Client();
  try {
    final fetch = await _fetch(source, c);
    final inline = _inlineHeaders(fetch.body);

    final merged = <String, String>{...inline, ...fetch.headers};
    final meta = _metaFromHeaders(merged);
    final decoded = decode(fetch.body);





    final dropped = <NodeWarning>[];
    final nodes = parseAll(decoded, dropped: dropped);
    return ParseResult(
        nodes, decoded, meta, fetch.body, fetch.headers, dropped);
  } finally {
    if (owned) c.close();
  }
}



final _newlineRe = RegExp(r'\r?\n');
final _commentPrefixRe = RegExp(r'^(#+|//|;)\s*');




Map<String, String> _inlineHeaders(String body) {
  final out = <String, String>{};
  for (final raw in body.split(_newlineRe)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final isComment = line.startsWith('#') ||
        line.startsWith('//') ||
        line.startsWith(';');
    if (!isComment) break;

    final stripped = line.replaceFirst(_commentPrefixRe, '');
    final colon = stripped.indexOf(':');
    if (colon <= 0) continue;
    final key = stripped.substring(0, colon).trim().toLowerCase();
    final value = stripped.substring(colon + 1).trim();
    if (key.isEmpty || value.isEmpty) continue;



    if (const {
      'profile-title',
      'profile-update-interval',
      'profile-web-page-url',
      'support-url',
      'subscription-userinfo',
      'content-disposition',
    }.contains(key)) {
      out[key] = value;
    }
  }
  return out;
}




const _prodFetchBackoffs = [Duration(seconds: 1), Duration(seconds: 3)];
List<Duration>? _fetchBackoffsOverride;



set fetchBackoffsForTesting(List<Duration>? value) =>
    _fetchBackoffsOverride = value;



Future<FetchResult> fetchRaw(SubscriptionSource source,
    {http.Client? client}) async {

  final owned = client == null;
  final c = client ?? http.Client();
  try {
    return await _fetch(source, c);
  } finally {
    if (owned) c.close();
  }
}

Future<FetchResult> _fetch(SubscriptionSource source, http.Client client) async {
  switch (source) {
    case UrlSource(
        url: final u,
        userAgent: final ua,
        identity: final id,
        timeout: final t
      ):




      final String effectiveUa;
      final Map<String, String> idHeaders;
      if (id != null) {
        effectiveUa = id.userAgent.isNotEmpty
            ? id.userAgent
            : resolveSubscriptionUserAgent();
        idHeaders = SubscriptionIdentity.headersFrom(
          sendHwid: id.sendHwid,
          hwid: id.hwid,
          deviceOs: id.deviceOs,
          verOs: id.verOs,
          deviceModel: id.deviceModel,
        );
      } else {
        final override = SubscriptionIdentity.userAgentOverride;
        effectiveUa = ua ??
            (override.isNotEmpty ? override : resolveSubscriptionUserAgent());
        idHeaders = SubscriptionIdentity.fetchHeaders();
      }
      final reqHeaders = <String, String>{
        'User-Agent': effectiveUa,
        ...idHeaders,
      };




      Object? lastErr;
      final backoffs = _fetchBackoffsOverride ?? _prodFetchBackoffs;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final resp = await client
              .get(Uri.parse(u), headers: reqHeaders)
              .timeout(t);
          if (resp.statusCode >= 400 && resp.statusCode < 500) {
            throw HttpException('HTTP ${resp.statusCode} for $u');
          }
          if (resp.statusCode >= 500) {
            throw HttpException('HTTP ${resp.statusCode} for $u');
          }
          return FetchResult(resp.body, _metaFromHeaders(resp.headers),
              Map<String, String>.from(resp.headers));
        } on HttpException catch (e) {
          lastErr = e;

          if (e.message.contains(RegExp(r'HTTP 4\d\d'))) rethrow;
          if (attempt < backoffs.length) {
            await Future<void>.delayed(backoffs[attempt]);
          }
        } catch (e) {
          lastErr = e;
          if (attempt < backoffs.length) {
            await Future<void>.delayed(backoffs[attempt]);
          }
        }
      }
      throw lastErr ?? Exception('fetch failed');
    case FileSource(file: final f):
      return FetchResult(await f.readAsString());
    case ClipboardSource(contents: final c):
      return FetchResult(c);
    case InlineSource(body: final b):
      return FetchResult(b);
    case QrSource(content: final c):
      return FetchResult(c);
  }
}



String? _decodeBase64Title(String? raw) {
  if (raw == null) return null;
  const prefix = 'base64:';
  if (!raw.startsWith(prefix)) return raw;
  try {
    final bytes = base64.decode(raw.substring(prefix.length));
    return decodeUtf8Lenient(bytes);
  } catch (_) {
    return raw;
  }
}







String? _parseContentDispositionFilename(String? header) {
  if (header == null || header.isEmpty) return null;
  String? name;

  final ext = RegExp(
    r"filename\*\s*=\s*(?:UTF-8|utf-8)''([^;]+)",
    caseSensitive: false,
  ).firstMatch(header);
  if (ext != null) {
    try {
      final decoded = Uri.decodeComponent(ext.group(1)!.trim());
      if (decoded.isNotEmpty) name = decoded;
    } catch (_) { }
  }
  if (name == null) {
    final m = RegExp(
      r'filename\s*=\s*("([^"]*)"|([^;]+))',
      caseSensitive: false,
    ).firstMatch(header);
    if (m != null) {
      final raw = (m.group(2) ?? m.group(3) ?? '').trim();
      if (raw.isNotEmpty) name = raw;
    }
  }
  if (name == null) return null;
  var out = name;


  final outLower = out.toLowerCase();
  for (final e in const ['.txt', '.yaml', '.yml', '.json', '.conf']) {
    if (outLower.endsWith(e)) {
      out = out.substring(0, out.length - e.length);
      break;
    }
  }
  out = out.trim();
  return out.isEmpty ? null : out;
}

SubscriptionMeta? _metaFromHeaders(Map<String, String> h) {



  final hLower = <String, String>{};
  for (final e in h.entries) {
    hLower.putIfAbsent(e.key.toLowerCase(), () => e.value);
  }
  String? get(String key) => hLower[key.toLowerCase()];

  final userInfo = get('subscription-userinfo');





  final title = _decodeBase64Title(get('profile-title')) ??
      _parseContentDispositionFilename(get('content-disposition'));
  final webPage = get('profile-web-page-url');
  final support = get('support-url');
  final updateIntervalRaw = get('profile-update-interval');

  if (userInfo == null &&
      title == null &&
      webPage == null &&
      support == null &&
      updateIntervalRaw == null) {
    return null;
  }

  int upload = 0, download = 0, total = 0;
  int? expire;
  if (userInfo != null) {
    for (final p in userInfo.split(';')) {
      final kv = p.trim().split('=');
      if (kv.length != 2) continue;
      final parsed = int.tryParse(kv[1].trim());



      final n = parsed ?? 0;
      switch (kv[0].trim()) {
        case 'upload':
          upload = n;
        case 'download':
          download = n;
        case 'total':
          total = n;
        case 'expire':
          expire = parsed;
      }
    }
  }
  final updateHours = int.tryParse((updateIntervalRaw ?? '').trim());

  return SubscriptionMeta(
    uploadBytes: upload,
    downloadBytes: download,
    totalBytes: total,
    expireTimestamp: expire,
    supportUrl: support,
    webPageUrl: webPage,
    profileTitle: title,
    updateIntervalHours: updateHours,
  );
}
