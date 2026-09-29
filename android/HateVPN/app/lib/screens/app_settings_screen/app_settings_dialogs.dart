import 'package:flutter/material.dart';

import '../../services/l10n/locale_controller.dart';






class AppSettingsDialogs {
  const AppSettingsDialogs._();



  static Future<bool?> confirmQuitApp(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(getLocalText.s("Quit & reopen app?")),
        content: Text(getLocalText.s("This will fully close the app process so the new \"Forward sing-box logs\" value is picked up at next launch (Libbox.setup is one-shot per process). VPN service will stop. Tap the app icon to reopen.")),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(getLocalText.s("Cancel")),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(getLocalText.s("Quit")),
          ),
        ],
      ),
    );
  }




  static Future<bool?> openAppInfoHint(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(getLocalText.s("Find these toggles")),
        content: SingleChildScrollView(
          child: Text(
            getLocalText.s("In the next screen (system App info) look for:\n\n• Autostart / Startup manager — allow\n• Background activity / Allow in background — allow\n• Battery / Power usage → \"Don't optimize\" or \"No restrictions\"\n• Battery saver exceptions — add L×Box\n\nLocation of these toggles varies by OEM (Xiaomi/MIUI, Samsung/One UI, Oppo/ColorOS, Huawei, Google Pixel). Some are under Battery, others under App permissions."),
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(getLocalText.s("Cancel")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(getLocalText.s("Open settings")),
          ),
        ],
      ),
    );
  }
}
