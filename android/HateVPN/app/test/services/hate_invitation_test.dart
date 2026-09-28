import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/services/hate_invitation.dart';

String link(String kind, Map<String, Object> payload) {
  final encoded = base64UrlEncode(
    utf8.encode(jsonEncode(payload)),
  ).replaceAll('=', '');
  return 'hatevpn://$kind/$encoded';
}

void main() {
  const id = 'hv-0123456789abcdef0123456789abcdef';
  const config =
      '[Interface]\nAddress = 10.0.0.2/32\n\n[Peer]\nEndpoint = example.org:1234\n';

  test('legacy Windows invitation retains its profile and name', () async {
    final invitation = await HateInvitationClient.resolve(
      link('invite', {
        'Version': 1,
        'Id': id,
        'Name': 'Друг',
        'Config': config,
      }),
    );
    expect(invitation.id, id);
    expect(invitation.name, 'Друг');
    expect(invitation.config, config);
    expect(invitation.oneTime, isFalse);
  });

  test('rejects corrupt one-time links before contacting a server', () async {
    final invalid = link('claim', {
      'Version': 1,
      'Id': id,
      'Name': 'Друг',
      'Host': '127.0.0.1',
      'Port': 8443,
      'CertificateSha256': 'not-a-fingerprint',
      'Token': 'a' * 64,
    });
    await expectLater(
      HateInvitationClient.resolve(invalid),
      throwsA(isA<HateInvitationException>()),
    );
  });

  test('rejects invalid format and unsupported version', () async {
    expect(HateInvitationClient.isLink('https://example.org/sub'), isFalse);
    expect(HateInvitationClient.isLink('HATEVPN://CLAIM/abc'), isTrue);
    await expectLater(
      HateInvitationClient.resolve('hatevpn://claim/!'),
      throwsA(isA<HateInvitationException>()),
    );
    await expectLater(
      HateInvitationClient.resolve(
        link('invite', {
          'Version': 2,
          'Id': id,
          'Name': 'Друг',
          'Config': config,
        }),
      ),
      throwsA(isA<HateInvitationException>()),
    );
  });

  test(
    'one-time claim sends Content-Length and reads pinned HTTPS response',
    () async {
      const certPath = 'test/fixtures/invitations/test-cert.pem';
      const keyPath = 'test/fixtures/invitations/test-key.pem';
      final pem = File(certPath).readAsStringSync();
      final encoded = pem.replaceAll(
        RegExp(r'-----BEGIN CERTIFICATE-----|-----END CERTIFICATE-----|\s'),
        '',
      );
      final fingerprint = sha256.convert(base64.decode(encoded)).toString();
      final context = SecurityContext()
        ..useCertificateChain(certPath)
        ..usePrivateKey(keyPath);
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      try {
        final token = 'a' * 64;
        final claimLink = link('claim', {
          'Version': 1,
          'Id': id,
          'Name': 'Друг',
          'Host': '127.0.0.1',
          'Port': server.port,
          'CertificateSha256': fingerprint,
          'Token': token,
        });
        final incoming = server.first;
        final resolved = HateInvitationClient.resolve(claimLink);
        final request = await incoming;
        final body = await utf8.decoder.bind(request).join();
        expect(request.headers.contentLength, utf8.encode(body).length);
        expect(jsonDecode(body), {'token': token});
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'id': id, 'config': base64.encode(utf8.encode(config))}),
        );
        await request.response.close();
        final invitation = await resolved;
        expect(invitation.config, config);
        expect(invitation.oneTime, isTrue);
      } finally {
        await server.close(force: true);
      }
    },
  );
}
