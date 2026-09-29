import 'package:flutter/widgets.dart';

import '../../vpn/box_vpn_client.dart';
import 'home_dialogs.dart';












class StartupWizard {
  StartupWizard(this.context, this.vpn);

  final BuildContext context;
  final BoxVpnClient vpn;

  Future<void> run() async {


    if (!context.mounted) return;
    await maybeShowNotificationPermissionDialog(context);


    if (!context.mounted) return;
    await maybeShowBatteryOptimizationDialog(context, vpn);


  }
}
