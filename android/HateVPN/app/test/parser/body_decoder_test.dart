import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/services/parser/body_decoder.dart';
import 'package:lxbox/services/parser/parse_all.dart';

import 'engine_test_setup.dart';

void main() {


  setUpAll(loadEngineSections);

  group('decode', () {
    test('plain URI list', () {
      final r = decode('vless://x@h:1#a\nss://x@h:1#b\n\n# comment\n');
      expect(r, isA<UriLines>());
      expect((r as UriLines).lines, hasLength(2));
      expect(r.skippedComments, 1);
    });

    test('base64-wrapped URI list', () {
      final raw = 'vless://x@h:1#a\ntrojan://p@h:2#b\n';
      final b64 = base64.encode(utf8.encode(raw));
      final r = decode(b64);
      expect(r, isA<UriLines>());
      expect((r as UriLines).lines, hasLength(2));
    });

    test('INI config', () {
      const ini = '[Interface]\nPrivateKey = x\n\n[Peer]\nPublicKey = y\nEndpoint = h:51820\n';
      final r = decode(ini);
      expect(r, isA<IniConfig>());
    });

    test('JSON singbox outbound', () {
      final r = decode('{"type":"vless","server":"h","server_port":443,"uuid":"u"}');
      expect(r, isA<JsonConfig>());
      expect((r as JsonConfig).source.kind, SourceKind.singboxOutbound);
    });

    test('Xray JSON array', () {
      final r = decode('[{"outbounds":[{"protocol":"vless","tag":"proxy"}]}]');
      expect(r, isA<JsonConfig>());
      expect((r as JsonConfig).source.kind, SourceKind.xrayConfigArray);
    });

    test('empty body → failure', () {
      expect(decode(''), isA<DecodeFailure>());
      expect(decode('   \n\n'), isA<DecodeFailure>());
    });

    test('comment-only → failure', () {
      expect(decode('# nothing\n// zilch'), isA<DecodeFailure>());
    });



    test('CRLF line endings работают как LF', () {
      const body = 'vless://u1@h1:443#a\r\ntrojan://p@h2:443#b\r\n';
      final r = decode(body);
      expect(r, isA<UriLines>());
      expect((r as UriLines).lines, hasLength(2));
    });

    test('URL-safe base64 (- и _) распознаётся', () {


      const std = 'dmxlc3M6Ly91QGg6NDQzI3gKdHJvamFuOi8vcEBoOjQ0MyN5Cg';
      final urlSafe = std.replaceAll('+', '-').replaceAll('/', '_');
      final r = decode(urlSafe);
      expect(r, isA<UriLines>());
      expect((r as UriLines).lines, hasLength(2));
    });

    test('whitespace-only body → failure', () {
      expect(decode('   \n\t\n  '), isA<DecodeFailure>());
    });










    test('INI без [Peer] — законный .conf: ноль узлов, без исключения', () {
      const body = '[Interface]\nPrivateKey = xxx\nAddress = 10.0.0.2/24';
      final r = decode(body);
      expect(r, isA<IniConfig>());
      expect(() => parseAll(r), returnsNormally);
      expect(parseAll(r), isEmpty);
    });

    test('INI с [Interface] + [Peer] → IniConfig', () {
      const body = '[Interface]\nPrivateKey = xxx\n[Peer]\nPublicKey = yyy\n';
      expect(decode(body), isA<IniConfig>());
    });




    test('JSON object с proxies → вид clash_yaml, узлов нет', () {
      const body = '{"proxies": [{"type": "vmess", "server": "h"}]}';
      final r = decode(body);
      expect(r, isA<JsonConfig>());
      expect((r as JsonConfig).source.kind, SourceKind.clashYaml);
      expect(r.source.mapper, isNull);
      expect(parseAll(r), isEmpty);
    });

    test('слишком короткая base64 (<16) не декодируется — падает в plain path', () {


      const shortB64 = 'aGVsbG8x';
      final r = decode(shortB64);
      expect(r, isA<UriLines>(), reason: 'plain path вернёт raw as UriLines');
      expect((r as UriLines).lines, ['aGVsbG8x']);
    });
  });
}
