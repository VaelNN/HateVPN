import 'dart:convert';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:pointycastle/export.dart';

















class MasqueKeys {

  static const _oidP256 = '1.2.840.10045.3.1.7';


  static const _oidEcPublicKey = '1.2.840.10045.2.1';


  static const _coordLen = 32;



  static final _wsRe = RegExp(r'\s');
  static final _pemHeaderRe = RegExp(r'-----(BEGIN|END)[^-]*-----');





  static MasqueKeyMaterial generate() {
    final gen = ECKeyGenerator()
      ..init(ParametersWithRandom(
        ECKeyGeneratorParameters(ECCurve_secp256r1()),
        _secureRandom(),
      ));
    final pair = gen.generateKeyPair();
    final priv = pair.privateKey;
    final pub = pair.publicKey;

    final d = _bigIntToFixed(priv.d!, _coordLen);
    final x = _bigIntToFixed(pub.Q!.x!.toBigInteger()!, _coordLen);
    final y = _bigIntToFixed(pub.Q!.y!.toBigInteger()!, _coordLen);

    return MasqueKeyMaterial(
      privateKeyDer: base64.encode(encodeSec1PrivateKey(d: d, x: x, y: y)),
      publicKeyDer: base64.encode(encodePkixPublicKey(x: x, y: y)),
      rawD: d,
      rawX: x,
      rawY: y,
    );
  }




  static SecureRandom _secureRandom() {
    final rnd = FortunaRandom();
    final seed = Uint8List.fromList(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    rnd.seed(KeyParameter(seed));
    return rnd;
  }


  static Uint8List _bigIntToFixed(BigInt v, int len) {
    final out = Uint8List(len);
    var tmp = v;
    for (var i = len - 1; i >= 0; i--) {
      out[i] = (tmp & BigInt.from(0xff)).toInt();
      tmp = tmp >> 8;
    }
    return out;
  }


  static Uint8List _uncompressedPoint(Uint8List x, Uint8List y) {
    final out = Uint8List(1 + x.length + y.length);
    out[0] = 0x04;
    out.setRange(1, 1 + x.length, x);
    out.setRange(1 + x.length, out.length, y);
    return out;
  }











  static Uint8List encodeSec1PrivateKey({
    required Uint8List d,
    required Uint8List x,
    required Uint8List y,
  }) {
    final seq = ASN1Sequence();

    seq.add(ASN1Integer(BigInt.one));

    seq.add(ASN1OctetString(d));

    final oid = ASN1ObjectIdentifier.fromComponentString(_oidP256);
    seq.add(_explicit(0xA0, oid.encodedBytes));

    final bits = ASN1BitString(_uncompressedPoint(x, y).toList());
    seq.add(_explicit(0xA1, bits.encodedBytes));
    return seq.encodedBytes;
  }












  static Uint8List encodePkixPublicKey({
    required Uint8List x,
    required Uint8List y,
  }) {
    final algId = ASN1Sequence()
      ..add(ASN1ObjectIdentifier.fromComponentString(_oidEcPublicKey))
      ..add(ASN1ObjectIdentifier.fromComponentString(_oidP256));
    final spki = ASN1Sequence()
      ..add(algId)
      ..add(ASN1BitString(_uncompressedPoint(x, y).toList()));
    return spki.encodedBytes;
  }




  static String normalizeServerPubKey(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.contains('-----BEGIN')) {

      return trimmed.replaceAll(_wsRe, '');
    }
    final body = trimmed.replaceAll(_pemHeaderRe, '').replaceAll(_wsRe, '');

    base64.decode(body);
    return body;
  }



  static ASN1Object _explicit(int tag, Uint8List innerDer) =>
      ASN1Object.preEncoded(tag, innerDer);
}


class MasqueKeyMaterial {
  const MasqueKeyMaterial({
    required this.privateKeyDer,
    required this.publicKeyDer,
    required this.rawD,
    required this.rawX,
    required this.rawY,
  });


  final String privateKeyDer;


  final String publicKeyDer;

  final Uint8List rawD;
  final Uint8List rawX;
  final Uint8List rawY;
}
