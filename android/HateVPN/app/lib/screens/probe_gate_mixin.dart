import 'package:flutter/material.dart';

import '../models/tunnel_status.dart';
import '../services/l10n/locale_controller.dart';
import '../vpn/box_vpn_client.dart';









mixin ProbeGateMixin<T extends StatefulWidget> on State<T> {



  Future<bool> ensureVpnStoppedForProbe() async {
    if ((await BoxVpnClient().getVpnStatus()) ==
        TunnelStatus.disconnected) {
      return true;
    }
    if (!mounted) return false;
    return _showGateAndStop();
  }




  Future<bool> onProbeVpnRaceGate() => _showGateAndStop();

  Future<bool> _showGateAndStop() async {
    final stop = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(getLocalText.s("VPN is running")),
        content: Text(getLocalText.s(
            "Servers can't be tested while the VPN is on — the test needs its own core session, which can't run alongside the active tunnel. Stop the VPN to test the servers.")),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(getLocalText.s("Cancel")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(getLocalText.s("Stop VPN")),
          ),
        ],
      ),
    );
    if (stop != true) return false;
    final ok = await BoxVpnClient().stopVPN();
    if (!mounted) return false;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(getLocalText.s("Couldn't stop the VPN — try again."))));
      return false;
    }
    return true;
  }
}
