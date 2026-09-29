import 'dart:convert';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/services/warp/masque_keys.dart';






void main() {
  group('MasqueKeys DER encoding', () {


    final x = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
    final y = Uint8List.fromList(List<int>.generate(32, (i) => 100 + i));
    final d = Uint8List.fromList(List<int>.generate(32, (i) => 200 - i));

    test('SEC1 private key парсится обратно как валидный ASN.1 SEQUENCE', () {
      final der = MasqueKeys.encodeSec1PrivateKey(d: d, x: x, y: y);
      final parsed = ASN1Parser(der).nextObject();
      expect(parsed, isA<ASN1Sequence>());
      final seq = parsed as ASN1Sequence;

      expect(seq.elements.length, 4);

      expect((seq.elements[0] as ASN1Integer).intValue, 1);

      expect((seq.elements[1] as ASN1OctetString).octets, d);

      expect(seq.elements[2].tag, 0xA0);
      expect(seq.elements[3].tag, 0xA1);
    });

    test('PKIX public key: SPKI-структура с двумя OID + BIT STRING', () {
      final der = MasqueKeys.encodePkixPublicKey(x: x, y: y);
      final seq = ASN1Parser(der).nextObject() as ASN1Sequence;
      expect(seq.elements.length, 2);
      final algId = seq.elements[0] as ASN1Sequence;
      expect((algId.elements[0] as ASN1ObjectIdentifier).identifier,
          '1.2.840.10045.2.1');
      expect((algId.elements[1] as ASN1ObjectIdentifier).identifier,
          '1.2.840.10045.3.1.7');

      final bits = seq.elements[1] as ASN1BitString;
      expect(bits.stringValue.length, 65);
      expect(bits.stringValue[0], 0x04);
    });

    test('generate() даёт валидный base64 и непустые сырые координаты', () {
      final km = MasqueKeys.generate();
      expect(km.rawX.length, 32);
      expect(km.rawY.length, 32);
      expect(km.rawD.length, 32);

      expect(() => base64.decode(km.privateKeyDer), returnsNormally);
      expect(() => base64.decode(km.publicKeyDer), returnsNormally);

      final priv = ASN1Parser(base64.decode(km.privateKeyDer)).nextObject();
      expect(priv, isA<ASN1Sequence>());
    });

    test('normalizeServerPubKey: PEM → чистый base64(DER)', () {
      const pem = '-----BEGIN PUBLIC KEY-----\n'
          'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE\n'
          '-----END PUBLIC KEY-----';
      final out = MasqueKeys.normalizeServerPubKey(pem);
      expect(out, 'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE');

      expect(MasqueKeys.normalizeServerPubKey('  AAAA \n'), 'AAAA');
    });
  });
}
