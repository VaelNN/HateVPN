import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HateVpsCredentials {
  const HateVpsCredentials({
    required this.host,
    required this.port,
    required this.user,
    required this.secret,
  });

  final String host;
  final int port;
  final String user;
  final String secret;

  bool get usesPrivateKey =>
      secret.trimLeft().startsWith('-----BEGIN ') &&
      secret.contains('PRIVATE KEY-----');

  void validate() {
    if (host.isEmpty ||
        host.length > 253 ||
        !RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$').hasMatch(host) ||
        host.contains('..') ||
        host.contains('--')) {
      throw const FormatException('Укажите IPv4-адрес или домен VPS.');
    }
    if (port < 1 || port > 65535) {
      throw const FormatException('Порт SSH должен быть от 1 до 65535.');
    }
    if (user != 'root') {
      throw const FormatException(
        'Для автоматической настройки нужен SSH-пользователь root.',
      );
    }
    if (secret.trim().isEmpty) {
      throw const FormatException('Введите пароль или закрытый SSH-ключ.');
    }
  }
}

typedef HateHostKeyApproval =
    Future<bool> Function(String type, String fingerprint);

class HateVpsProvisioner {
  const HateVpsProvisioner();

  Future<String> install(
    HateVpsCredentials credentials, {
    required HateHostKeyApproval approveHostKey,
    required void Function(String) onProgress,
  }) async {
    credentials.validate();
    final deviceId = await _deviceId();
    List<SSHIdentity>? identities;
    if (credentials.usesPrivateKey) {
      try {
        identities = SSHKeyPair.fromPem(credentials.secret);
        if (identities.isEmpty) throw const FormatException();
      } catch (_) {
        throw const FormatException(
          'Не удалось прочитать SSH-ключ. Вставьте полный закрытый ключ OpenSSH или PEM.',
        );
      }
    }

    SSHClient? client;
    SftpClient? sftp;
    String? remotePath;
    try {
      onProgress('Подключаемся к VPS по SSH…');
      final socket = await SSHSocket.connect(
        credentials.host,
        credentials.port,
      ).timeout(const Duration(seconds: 20));
      client = SSHClient(
        socket,
        username: credentials.user,
        identities: identities,
        onPasswordRequest: identities == null ? () => credentials.secret : null,
        onVerifyHostKey: (type, fingerprint) =>
            approveHostKey(type, utf8.decode(fingerprint)),
        handshakeTimeout: const Duration(seconds: 20),
        authTimeout: const Duration(seconds: 20),
      );
      await client.authenticated;

      final detected = await client
          .runWithResult(
            "docker inspect -f '{{.State.Running}}' amnezia-awg2 2>/dev/null",
            stderr: false,
          )
          .timeout(const Duration(seconds: 10));
      final state = utf8.decode(detected.stdout).trim();
      if (state == 'false') {
        throw const FormatException(
          'VPN уже установлен на VPS, но его служба остановлена. Запустите сервер в AmneziaVPN.',
        );
      }
      final existing = state == 'true';
      onProgress(
        existing
            ? 'Создаём отдельное подключение на сервере…'
            : 'Проверяем систему и настраиваем сервер…',
      );

      final script = await rootBundle.loadString(
        existing
            ? 'assets/setup/add-amnezia-container-client.sh'
            : 'assets/setup/install-amneziawg-server.sh',
      );
      remotePath = '/tmp/hatevpn-setup-${_randomHex(16)}.sh';
      sftp = await client.sftp();
      final remote = await sftp.open(
        remotePath,
        mode:
            SftpFileOpenMode.write |
            SftpFileOpenMode.create |
            SftpFileOpenMode.exclusive,
      );
      try {
        await remote.writeBytes(Uint8List.fromList(utf8.encode(script)));
      } finally {
        await remote.close();
      }

      final command = existing
          ? 'bash $remotePath ${credentials.host} 0 $deviceId'
          : 'bash $remotePath ${credentials.host}';
      final result = await client
          .runWithResult(command)
          .timeout(const Duration(minutes: 15));
      if (result.exitCode != 0) {
        final reason = utf8.decode(result.stderr, allowMalformed: true).trim();
        throw StateError(
          reason.isEmpty
              ? 'Не удалось настроить VPS.'
              : reason.length > 350
              ? reason.substring(reason.length - 350)
              : reason,
        );
      }
      onProgress('Проверяем подключение…');
      final output = utf8.decode(result.stdout, allowMalformed: true);
      final match = RegExp(
        r'^HATEVPN_AWG_CONFIG_BASE64=(\S+)$',
        multiLine: true,
      ).firstMatch(output);
      if (match == null) {
        throw StateError('Сервер не вернул профиль подключения.');
      }
      final config = utf8.decode(base64.decode(match.group(1)!));
      final endpoint = RegExp(
        r'^\s*Endpoint\s*=\s*([^:\s]+):\d+\s*$',
        multiLine: true,
      ).firstMatch(config);
      if (!config.contains('[Interface]') ||
          !config.contains('[Peer]') ||
          !config.contains('PrivateKey') ||
          endpoint == null ||
          endpoint.group(1)!.toLowerCase() != credentials.host.toLowerCase()) {
        throw const FormatException(
          'Сервер вернул некорректный профиль подключения.',
        );
      }
      return config;
    } on SSHHostkeyError {
      throw const FormatException('SSH-ключ сервера не подтверждён. Настройка отменена.');
    } on SSHAuthError {
      throw const FormatException('SSH не принял логин, пароль или ключ. Проверьте данные доступа.');
    } on SocketException {
      throw const FormatException(
        'Сервер не отвечает по SSH. Проверьте адрес и порт.',
      );
    } on TimeoutException {
      throw const FormatException(
        'Сервер долго не отвечает. Попробуйте ещё раз.',
      );
    } finally {
      if (client != null && remotePath != null) {
        try {
          await client
              .runWithResult('rm -f $remotePath')
              .timeout(const Duration(seconds: 5));
        } catch (_) {

        }
      }
      try {
        await sftp?.close();
      } catch (_) {

      }
      try {
        await client?.close();
      } catch (_) {

      }
    }
  }

  static Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('hatevpn_vps_device_id');
    if (saved != null && RegExp(r'^hv-[0-9a-f]{32}$').hasMatch(saved)) {
      return saved;
    }
    final id = 'hv-${_randomHex(16)}';
    await prefs.setString('hatevpn_vps_device_id', id);
    return id;
  }

  static String _randomHex(int byteCount) {
    final random = Random.secure();
    return List<int>.generate(
      byteCount,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }
}
