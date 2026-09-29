








import '../../parser/ini_parser.dart';
import '../masque_account.dart';
import '../masquerade_params.dart';
import '../warp_account.dart';
import '../warp_client.dart';
import 'scan_models.dart';



class ScanNodeBuilder {
  ScanNodeBuilder({this.warp, this.masque, this.wgKeepalive = 0});

  final WarpAccount? warp;
  final MasqueAccount? masque;




  final int wgKeepalive;

  String? uriFor(ScanCandidate c) {
    switch (c.protocol) {
      case ScanProtocol.awg:
        return _wgUri(c);
      case ScanProtocol.masqueH3:
      case ScanProtocol.masqueH2:
        return _masqueUri(c);
    }
  }




  String? _wgUri(ScanCandidate c) {
    final acc = warp;
    if (acc == null) return null;
    final p = c.awgParams;
    final awg = WarpClient.buildAmneziaAwg(QuicParams(
      sni: c.sni,
      ip: p?.ip ?? 'quic',
      jc: p?.jc ?? 4,
      jmin: p?.jmin ?? 40,
      jmax: p?.jmax ?? 70,
    ));
    final tuned = acc.copyWith(endpoint: c.endpoint, awg: awg);



    final spec = parseWireguardIni(
      tuned.toWireguardConf(
        includeReserved: false,
        persistentKeepalive: wgKeepalive,
      ),
      nameHint: c.nodeTitle,
    );
    return spec?.toUri();
  }










  String? _masqueUri(ScanCandidate c) {
    final acc = masque;
    if (acc == null) return null;
    final isH3 = c.protocol == ScanProtocol.masqueH3;
    final tuned = MasqueAccount(
      privKeyDer: acc.privKeyDer,
      serverPubDer: acc.serverPubDer,
      clientV4: acc.clientV4,
      clientV6: acc.clientV6,
      server: c.ip,
      port: c.port,
      deviceId: acc.deviceId,
      token: acc.token,
      createdAt: acc.createdAt,
      sni: c.sni,
      idleTimeout: acc.idleTimeout,
      keepAlive: acc.keepAlive,
    );

    final uri = tuned.toMasqueUri(vhttp: isH3 ? 'h3' : 'h2');
    final hash = uri.lastIndexOf('#');
    final base = hash < 0 ? uri : uri.substring(0, hash);
    return '$base#${Uri.encodeComponent(c.nodeTitle)}';
  }
}
