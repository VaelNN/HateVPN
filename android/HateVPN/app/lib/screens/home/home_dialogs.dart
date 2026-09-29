import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/home_controller.dart';
import '../../models/home_state.dart';
import '../../services/install_source.dart';
import '../../services/settings_storage.dart';
import '../../services/update_checker.dart';
import '../../services/url_launcher.dart' as ul;
import '../../services/version_info.dart';
import '../../vpn/box_vpn_client.dart';
import '../../widgets/wifi_permission_dialog.dart';
import '../../services/l10n/locale_controller.dart';




void confirmStop(
  BuildContext context,
  HomeController controller,
  HomeState state,
) {
  if (state.traffic.activeConnections > 3) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(getLocalText.s("Stop VPN?")),
        content: Text(
          getLocalText.plural(
            "%d active connections will be closed.",
            state.traffic.activeConnections,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(getLocalText.s("Cancel")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(getLocalText.s("Stop")),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) controller.stop();
    });
  } else {
    controller.stop();
  }
}












bool askBeforeOverridingForeignVpn({required bool hasTun}) => hasTun;










Future<bool> confirmForeignVpnOverride({
  required BuildContext context,
  required Future<VpnModeConfig> Function() loadVpnMode,
  required Future<bool> Function() isForeignVpnActive,
  Future<bool?> Function(BuildContext)? showDialogFn,
}) async {
  final cfg = await loadVpnMode();
  if (!askBeforeOverridingForeignVpn(hasTun: cfg.hasTun)) return true;
  if (!await isForeignVpnActive()) return true;
  if (!context.mounted) return false;
  final ok = await (showDialogFn ?? showForeignVpnDialog)(context);
  return ok == true;
}









Future<bool?> showForeignVpnDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      title: Text(getLocalText.s("Another VPN is active")),
      content: const Text('Переключиться на HateVPN?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(getLocalText.s("Cancel")),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(ctx).pop(false);
            unawaited(BoxVpnClient.I.openVpnSettings());
          },
          child: Text(getLocalText.s("VPN settings")),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(getLocalText.s("Switch")),
        ),
      ],
    ),
  );
}










Future<void> showLocationPermissionDialog(
  BuildContext context,
  String permName,
) async {
  if (!context.mounted) return;
  final missing = permName.split(',').map((p) => p.trim()).toList();
  await WifiPermissionDialog.show(context, missing: missing);
}

























Future<void> maybeShowUpdateSnackbar(
  BuildContext context,
  UpdateInfo info, {
  required VoidCallback onShown,
}) async {
  final dismissed = await SettingsStorage.getDismissedUpdateVersion();
  if (dismissed == info.tag) return;
  if (!context.mounted) return;
  onShown();
  final source = InstallSourceResolver.current;
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 6),
      behavior: SnackBarBehavior.floating,
      content: _UpdateSnackContent(
        info: info,



        onTapBody: () {
          messenger.hideCurrentSnackBar();
          unawaited(
            ul.UrlLauncher.open(
              source.updateUrl(info.tag),
              fallbackUrl: source.updateUrlFallback,
            ),
          );
        },
        onLater: () => messenger.hideCurrentSnackBar(),



        onIgnore: () {
          messenger.hideCurrentSnackBar();
          unawaited(UpdateChecker.I.dismissCurrent());
        },
      ),
    ),
  );
}






class _UpdateSnackContent extends StatelessWidget {
  const _UpdateSnackContent({
    required this.info,
    required this.onTapBody,
    required this.onLater,
    required this.onIgnore,
  });

  final UpdateInfo info;
  final VoidCallback onTapBody;
  final VoidCallback onLater;
  final VoidCallback onIgnore;

  @override
  Widget build(BuildContext context) {

    final buttons = [
      TextButton(onPressed: onLater, child: Text(getLocalText.s("Later"))),
      TextButton(onPressed: onIgnore, child: Text(getLocalText.s("Ignore"))),
    ];




    final text = InkWell(
      onTap: onTapBody,
      child: SizedBox(


        width: double.infinity,
        child: Text(
          getLocalText.s(
            "L×Box %1\$s available (you have v%2\$s)",
            info.tag,
            VersionInfo.I.version,
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 320) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              text,
              Row(mainAxisAlignment: MainAxisAlignment.end, children: buttons),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: text),
            ...buttons,
          ],
        );
      },
    );
  }
}





const _notifPromptKey = SettingsStorage.notificationPromptVar;

Future<void> maybeShowNotificationPermissionDialog(BuildContext context) async {
  final granted = await ul.UrlLauncher.checkNotificationPermission();
  if (granted) return;
  final asked = await SettingsStorage.getVar(_notifPromptKey, '0');
  if (asked == '1') return;
  await SettingsStorage.setVar(_notifPromptKey, '1');
  if (!context.mounted) return;
  await ul.UrlLauncher.requestNotificationPermission();
}









const _batteryPromptKey = SettingsStorage.batteryPromptVar;

Future<void> maybeShowBatteryOptimizationDialog(
  BuildContext context,
  BoxVpnClient vpn, {
  bool skipPersist = false,
}) async {
  final ok = await vpn.isIgnoringBatteryOptimizations();
  if (ok) return;
  if (!skipPersist) {
    final asked = await SettingsStorage.getVar(_batteryPromptKey, '0');
    if (asked == '1') return;
    await SettingsStorage.setVar(_batteryPromptKey, '1');
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      title: const Text('Работа в фоне'),
      content: const Text(
        'Разрешите работу в фоне, чтобы VPN оставался включённым при заблокированном экране.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(getLocalText.s("Later")),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.of(ctx).pop();
            await vpn.openBatteryOptimizationSettings();
          },
          child: Text(getLocalText.s("Allow")),
        ),
      ],
    ),
  );
}







Future<void> showOemBatteryFollowupDialog(
  BuildContext context,
  BoxVpnClient vpn,
) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      title: Text(getLocalText.s("Disable battery restrictions")),
      content: const Text(
        'В настройках батареи выберите для HateVPN «Без ограничений».',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(getLocalText.s("Close")),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.of(ctx).pop();
            await vpn.openAppDetailsSettings();
          },
          child: Text(getLocalText.s("Open Settings")),
        ),
      ],
    ),
  );
}






const _addTilePromptKey = SettingsStorage.addTilePromptVar;

Future<void> maybeShowAddTilePrompt(
  BuildContext context,
  BoxVpnClient vpn,
) async {
  final asked = await SettingsStorage.getVar(_addTilePromptKey, '0');
  if (asked == '1') return;
  await SettingsStorage.setVar(_addTilePromptKey, '1');


  await vpn.requestAddTile();
}













const _updatePromptKey = SettingsStorage.updateCheckPromptVar;

Future<void> maybeShowUpdateCheckPrompt(BuildContext context) async {
  final asked = await SettingsStorage.getVar(_updatePromptKey, '0');
  if (asked == '1') return;

  if (VersionInfo.I.version.contains('-dev.')) return;
  await SettingsStorage.setVar(_updatePromptKey, '1');
  if (!context.mounted) return;

  final fromStore = InstallSourceResolver.current != InstallSource.github;
  final enable = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog.adaptive(
      title: Text(getLocalText.s("Check for updates?")),
      content: Text(
        getLocalText.s(
          "L×Box can ping github.com once a day to see whether a new version is out. Nothing installs by itself — you get a link to the release page.\n\nIf you installed from an app store, its client already handles updates and you can skip this.",
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(getLocalText.s("Skip")),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(getLocalText.s("Enable")),
        ),
      ],
    ),
  );


  await SettingsStorage.setAutoCheckUpdates(enable ?? !fromStore);
}
