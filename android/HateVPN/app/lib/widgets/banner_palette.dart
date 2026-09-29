import 'package:flutter/material.dart';

import '../models/node_warning.dart';











enum BannerSeverity { info, warning, error, success }



class BannerColors {
  const BannerColors({
    required this.background,
    required this.border,
    required this.foreground,
    required this.action,
  });

  final Color background;
  final Color border;
  final Color foreground;
  final Color action;
}









BannerColors bannerColors(BuildContext context, BannerSeverity severity) {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (severity) {
    case BannerSeverity.info:
      return BannerColors(
        background: cs.primaryContainer,
        border: cs.onPrimaryContainer.withValues(alpha: 0.35),
        foreground: cs.onPrimaryContainer,
        action: cs.onPrimaryContainer,
      );
    case BannerSeverity.error:
      return BannerColors(
        background: cs.errorContainer,
        border: cs.onErrorContainer.withValues(alpha: 0.35),
        foreground: cs.onErrorContainer,
        action: cs.onErrorContainer,
      );
    case BannerSeverity.warning:




      return BannerColors(
        background: isDark
            ? Colors.amber.shade900.withValues(alpha: 0.18)
            : Colors.amber.shade100,
        border: isDark ? Colors.amber.shade700 : Colors.amber.shade400,
        foreground: isDark ? Colors.amber.shade100 : Colors.brown.shade800,
        action: isDark ? Colors.amber.shade200 : Colors.brown.shade800,
      );
    case BannerSeverity.success:
      return BannerColors(
        background: isDark
            ? Colors.green.shade900.withValues(alpha: 0.18)
            : Colors.green.shade100,
        border: isDark ? Colors.green.shade700 : Colors.green.shade400,
        foreground: isDark ? Colors.green.shade100 : Colors.green.shade900,
        action: isDark ? Colors.green.shade200 : Colors.green.shade900,
      );
  }
}





Color bannerIconColor(BuildContext context, BannerSeverity severity) {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return switch (severity) {
    BannerSeverity.info => cs.primary,
    BannerSeverity.error => cs.error,
    BannerSeverity.warning =>
      isDark ? Colors.amber.shade300 : Colors.amber.shade800,
    BannerSeverity.success =>
      isDark ? Colors.green.shade300 : Colors.green.shade700,
  };
}













(Color, IconData) warningSeverityStyle(BuildContext context,
    WarningSeverity severity) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  return switch (severity) {
    WarningSeverity.error => (theme.colorScheme.error, Icons.error_outline),


    WarningSeverity.warning => (
        isDark ? Colors.amber.shade300 : Colors.amber.shade800,
        Icons.warning_amber,
      ),


    WarningSeverity.info => (
        isDark ? Colors.blue.shade300 : Colors.blue.shade700,
        Icons.info_outline,
      ),
  };
}


Color warningSeverityColor(BuildContext context, WarningSeverity severity) =>
    warningSeverityStyle(context, severity).$1;
