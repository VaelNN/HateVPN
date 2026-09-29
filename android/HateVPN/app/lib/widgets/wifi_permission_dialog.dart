import 'package:flutter/material.dart';

import '../services/url_launcher.dart' as ul;
import '../services/l10n/locale_controller.dart';





















class WifiPermissionDialog {
  WifiPermissionDialog._();





  static Future<void> show(
    BuildContext context, {
    required List<String> missing,
  }) async {
    final shortNames = missing
        .map((p) => p.replaceFirst('android.permission.', ''))
        .toList(growable: false);
    final needsNearby = missing.any((p) => p.endsWith('NEARBY_WIFI_DEVICES'));
    final needsBackgroundLocation =
        missing.any((p) => p.endsWith('ACCESS_BACKGROUND_LOCATION'));


    final needsFineLocation =
        missing.any((p) => p.endsWith('ACCESS_FINE_LOCATION'));

    final body = StringBuffer()
      ..writeln(
          'Your sing-box config uses Wi-Fi-based rules (wifi_ssid / wifi_bssid). '
          'Reading the current Wi-Fi SSID requires:')
      ..writeln();
    for (final p in shortNames) {
      body.writeln(' • $p');
    }
    body.writeln();
    if (needsFineLocation) {
      body.writeln(getLocalText.s(
          "Precise location is required. Open Settings → Permissions → Location and enable \"Use precise location\"."));
    }
    if (needsNearby && !needsBackgroundLocation && !needsFineLocation) {
      body.writeln(
          'Tap "Allow Wi-Fi info" to grant via system prompt, then restart the VPN.');
    } else if (needsBackgroundLocation || !needsFineLocation) {
      body.writeln(
          'Background Location can only be granted in Settings → Permissions → '
          'Location → "Allow all the time". After granting, restart the VPN.');
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog.adaptive(
        title: Text(getLocalText.s("Wi-Fi rules need permissions")),
        content: SingleChildScrollView(child: Text(body.toString())),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(getLocalText.s("Cancel")),
          ),
          if (needsNearby)
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await ul.UrlLauncher.requestNearbyWifiPermission();
              },
              child: Text(getLocalText.s("Allow Wi-Fi info")),
            ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ul.UrlLauncher.openAppSettings();
            },
            child: Text(getLocalText.s("Open Settings")),
          ),
        ],
      ),
    );
  }
}
