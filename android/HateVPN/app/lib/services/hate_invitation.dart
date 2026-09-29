import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';



class HateInvitation {
  const HateInvitation({
    required this.id,
    required this.name,
    required this.config,
    required this.oneTime,
  });

  final String id;
  final String name;
  final String config;
  final bool oneTime;
}

class HateInvitationException implements Exception {
  const HateInvitationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class HateInvitationClient {
  static const _claimPrefix = 'hatevpn://claim/';
  static const _legacyPrefix = 'hatevpn://invite/';
  static final _idPattern = RegExp(r'^hv-[0-9a-f]{32}$');
  static final _hexPattern = RegExp(r'^[0-9a-f]{64}$');
  static final _hostPattern = RegExp(
    r'^[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?$',
  );
  static final _encodedPattern = RegExp(r'^[A-Za-z0-9_-]+$');

  static bool isLink(String value) {
    final lower = value.trim().toLowerCase();
    return lower.startsWith(_claimPrefix) || lower.startsWith(_legacyPrefix);
  }



  static Future<HateInvitation> resolve(String link) async {
    final trimmed = link.trim();
    final lower = trimmed.toLowerCase();
    if (lower.startsWith(_legacyPrefix)) {
      final p = _payload(trimmed, _legacyPrefix, 60000);
      final id = _field(p, 'Id');
      final name = _field(p, 'Name');
      final config = _field(p, 'Config');
      _validateCommon(p, id, name);
      if (!config.contains('[Interface]') || !config.contains('[Peer]')) {
        throw const HateInvitationException('В приглашении нет VPN-профиля.');
      }
      return HateInvitation(id: id, name: name, config: config, oneTime: false);
    }

    final p = _payload(trimmed, _claimPrefix, 4096);
    final id = _field(p, 'Id');
    final name = _field(p, 'Name');
    _validateCommon(p, id, name);
    final host = _field(p, 'Host');
    final port = p['Port'];
    final pin = _field(p, 'CertificateSha256');
    final token = _field(p, 'Token');
    if (!_hostPattern.hasMatch(host) ||
        host.contains('..') ||
        port is! int ||
        port < 1 ||
        port > 65535 ||
        !_hexPattern.hasMatch(pin) ||
        !_hexPattern.hasMatch(token)) {
      throw const HateInvitationException('Параметры приглашения повреждены.');
    }

    final body = await _claim(host, port, pin, token);
    if (body['id'] != id || body['config'] is! String) {
      throw const HateInvitationException('Сервер вернул неверный профиль.');
    }
    try {
      final config = utf8.decode(base64.decode(body['config'] as String));
      if (!config.contains('[Interface]') || !config.contains('[Peer]')) {
        throw const FormatException();
      }
      return HateInvitation(id: id, name: name, config: config, oneTime: true);
    } catch (_) {
      throw const HateInvitationException(
        'Сервер вернул повреждённый профиль.',
      );
    }
  }

  static Map<String, dynamic> _payload(
    String link,
    String prefix,
    int maxLength,
  ) {
    if (link.length > maxLength ||
        link.length <= prefix.length ||
        !link.toLowerCase().startsWith(prefix)) {
      throw const HateInvitationException(
        'Некорректная ссылка приглашения HateVPN.',
      );
    }
    final encoded = link.substring(prefix.length);
    if (!_encodedPattern.hasMatch(encoded)) {
      throw const HateInvitationException('Ссылка приглашения повреждена.');
    }
    try {
      final value = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(encoded))),
      );
      if (value is Map<String, dynamic>) return value;
    } catch (_) {

    }
    throw const HateInvitationException('Ссылка приглашения повреждена.');
  }

  static String _field(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    if (value is! String) {
      throw const HateInvitationException('Параметры приглашения повреждены.');
    }
    return value;
  }

  static void _validateCommon(
    Map<String, dynamic> payload,
    String id,
    String name,
  ) {
    if (payload['Version'] != 1 ||
        !_idPattern.hasMatch(id) ||
        name.trim().isEmpty ||
        name.length > 48 ||
        name.runes.any((c) => c < 32 || c == 127)) {
      throw const HateInvitationException('Параметры приглашения повреждены.');
    }
  }

  static Future<Map<String, dynamic>> _claim(
    String host,
    int port,
    String fingerprint,
    String token,
  ) async {


    final client = HttpClient(
      context: SecurityContext(withTrustedRoots: false),
    );
    client.connectionTimeout = const Duration(seconds: 8);
    client.badCertificateCallback = (cert, hostName, serverPort) =>
        sha256.convert(cert.der).toString() == fingerprint;
    client.findProxy = (_) => 'DIRECT';
    try {
      final uri = Uri(scheme: 'https', host: host, port: port, path: '/claim');
      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 10));
      request.headers.contentType = ContentType.json;


      final payload = utf8.encode(jsonEncode({'token': token}));
      request.contentLength = payload.length;
      request.add(payload);
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      if (response.statusCode == HttpStatus.gone) {
        throw const HateInvitationException(
          'Приглашение уже использовано или отозвано.',
        );
      }
      if (response.statusCode == HttpStatus.badRequest) {
        throw const HateInvitationException(
          'Сервис приглашений отклонил запрос.',
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HateInvitationException(
          'Не удалось активировать приглашение (HTTP ${response.statusCode}).',
        );
      }
      if (response.contentLength > 200000) {
        throw const HateInvitationException('Ответ сервера слишком большой.');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 12))) {
        bytes.addAll(chunk);
        if (bytes.length > 200000) {
          throw const HateInvitationException('Ответ сервера слишком большой.');
        }
      }
      final json = jsonDecode(utf8.decode(bytes));
      if (json is Map<String, dynamic>) return json;
      throw const HateInvitationException('Сервер вернул неверный ответ.');
    } on HateInvitationException {
      rethrow;
    } on HandshakeException {
      throw const HateInvitationException(
        'Не совпадает сертификат сервера приглашений.',
      );
    } catch (_) {
      throw const HateInvitationException('Нет связи с сервером приглашений.');
    } finally {
      client.close(force: true);
    }
  }
}
