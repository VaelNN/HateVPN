import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/core_reject/core_reject_guard.dart';
import '../core_reject_ui.dart';

import '../../../models/home_state.dart';
import '../../../services/l10n/locale_controller.dart';












enum BannerPalette { info, warning, error }




class AppBanner {
  const AppBanner({
    required this.key,
    required this.message,
    required this.icon,
    required this.palette,
    this.title = '',
    this.actionLabel = '',
    this.onAction,
    this.autoDismiss,
    this.onTap,
    this.onDismiss,
  });



  final String title;


  final String actionLabel;
  final VoidCallback? onAction;

  final String key;
  final String message;
  final IconData icon;
  final BannerPalette palette;
  final Duration? autoDismiss;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;
}




class BannerActions {
  const BannerActions({
    required this.onRebuild,
    required this.onConfirmStop,
    required this.onClearError,
    required this.onShareCrash,
    required this.onDismissCrash,
    required this.onShowCoreRejected,
    required this.onDismissCoreRejected,
  });

  final VoidCallback onRebuild;
  final VoidCallback onConfirmStop;
  final VoidCallback onClearError;


  final VoidCallback onShareCrash;


  final VoidCallback onDismissCrash;


  final VoidCallback onShowCoreRejected;


  final VoidCallback onDismissCoreRejected;
}






List<AppBanner> activeBanners(
  HomeState s, {
  required bool configDirty,
  required bool busy,
  required BannerActions actions,
  bool crashPending = false,
  bool autoApplying = false,
  List<DisabledNode> coreRejected = const [],
}) {
  final a = actions;
  final out = <AppBanner>[];



  if (coreRejected.isNotEmpty) {
    out.add(AppBanner(
      key: 'core_rejected',
      title: coreRejectBannerTitle(coreRejected.length),
      message: coreRejectBannerText(coreRejected),
      icon: Icons.warning_amber_outlined,
      palette: BannerPalette.warning,
      actionLabel: coreRejectShowLabel(),
      onAction: a.onShowCoreRejected,
      onDismiss: a.onDismissCoreRejected,
    ));
  }




  if (crashPending) {
    out.add(AppBanner(
      key: 'core_crash',
      message: getLocalText.s("The core crashed last session — tap to share the report"),
      icon: Icons.bug_report_outlined,
      palette: BannerPalette.error,
      onTap: a.onShareCrash,
      onDismiss: a.onDismissCrash,
    ));
  }
  if (configDirty && !busy) {
    out.add(AppBanner(
      key: 'settings_changed',
      message: getLocalText.s("Settings changed — tap to rebuild config"),
      icon: Icons.build_circle_outlined,
      palette: BannerPalette.info,
      onTap: a.onRebuild,
    ));
  }









  if (s.tunnelUp && s.configChangedNeedRestart && !configDirty &&
      !autoApplying) {
    out.add(AppBanner(
      key: 'restart',
      message: getLocalText.s("Config changed — restart VPN to apply"),
      icon: Icons.info_outline,
      palette: BannerPalette.warning,
      onTap: a.onConfirmStop,
    ));
  }


  if (s.configLoadError) {
    out.add(AppBanner(
      key: 'config_load_error',
      message: getLocalText.s("Config loading error"),
      icon: Icons.restart_alt,
      palette: BannerPalette.error,
      onTap: a.onConfirmStop,
    ));
  }






  return out;
}





class BannerStack extends StatefulWidget {
  const BannerStack({super.key, required this.banners});

  final List<AppBanner> banners;

  @override
  State<BannerStack> createState() => _BannerStackState();
}

class _BannerStackState extends State<BannerStack> {
  final Map<String, ({Timer timer, String forMessage})> _timers = {};

  @override
  void initState() {
    super.initState();
    _reconcileTimers();
  }

  @override
  void didUpdateWidget(BannerStack old) {
    super.didUpdateWidget(old);
    _reconcileTimers();
  }

  void _reconcileTimers() {
    final present = {for (final b in widget.banners) b.key: b};

    _timers.removeWhere((k, e) {
      if (!present.containsKey(k)) {
        e.timer.cancel();
        return true;
      }
      return false;
    });

    for (final b in widget.banners) {
      final d = b.autoDismiss;
      if (d == null) continue;
      final existing = _timers[b.key];
      if (existing != null && existing.forMessage == b.message) continue;
      existing?.timer.cancel();
      _timers[b.key] = (
        timer: Timer(d, () {
          _timers.remove(b.key);
          if (mounted) b.onDismiss?.call();
        }),
        forMessage: b.message,
      );
    }
  }

  @override
  void dispose() {
    for (final e in _timers.values) {
      e.timer.cancel();
    }
    super.dispose();
  }

  ({Color bg, Color fg}) _colors(ColorScheme cs, BannerPalette p) =>
      switch (p) {
        BannerPalette.info => (bg: cs.primaryContainer, fg: cs.onPrimaryContainer),
        BannerPalette.warning =>
          (bg: cs.tertiaryContainer, fg: cs.onTertiaryContainer),
        BannerPalette.error => (bg: cs.errorContainer, fg: cs.onErrorContainer),
      };

  @override
  Widget build(BuildContext context) {
    if (widget.banners.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in widget.banners) ...[
          const SizedBox(height: 8),
          _row(context, cs, b),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, ColorScheme cs, AppBanner b) {
    final c = _colors(cs, b.palette);
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: b.title.isEmpty
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Icon(b.icon, size: 16, color: c.fg),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (b.title.isNotEmpty)
                  Text(b.title,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.fg)),
                Text(b.message,
                    style: TextStyle(fontSize: 13, color: c.fg)),
                if (b.actionLabel.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: b.onAction,
                      style: TextButton.styleFrom(
                        foregroundColor: c.fg,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(b.actionLabel),
                    ),
                  ),
              ],
            ),
          ),
          if (b.onDismiss != null)
            IconButton(
              tooltip: getLocalText.s("Dismiss"),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(Icons.close, size: 18, color: c.fg),
              onPressed: b.onDismiss,
            ),
        ],
      ),
    );
    if (b.onTap == null) return content;





    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: b.onTap,
      child: content,
    );
  }
}
