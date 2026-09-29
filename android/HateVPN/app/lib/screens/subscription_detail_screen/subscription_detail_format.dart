import 'package:flutter/material.dart';

import '../../controllers/subscription_controller.dart';
import '../../models/server_list.dart';
import '../../services/format_utils.dart' as fmt;
import '../../services/l10n/locale_controller.dart';






String statusLabel(SubscriptionServers list) {
  switch (list.lastUpdateStatus) {
    case UpdateStatus.ok:
      return getLocalText.s(1, "OK");
    case UpdateStatus.failed:
      final n = list.consecutiveFails;
      return n > 1 ? getLocalText.plural("Failed (%d in a row)", n) : getLocalText.s(1, "Failed");
    case UpdateStatus.inProgress:
      return getLocalText.s("Refreshing…");
    case UpdateStatus.never:
      return getLocalText.s("Never updated");
  }
}

Color statusColor(SubscriptionServers list, ColorScheme cs) {
  switch (list.lastUpdateStatus) {
    case UpdateStatus.ok:
      return cs.primary;
    case UpdateStatus.failed:
      return cs.error;
    case UpdateStatus.inProgress:
      return cs.secondary;
    case UpdateStatus.never:
      return cs.onSurfaceVariant;
  }
}

IconData statusIcon(SubscriptionServers list) {
  switch (list.lastUpdateStatus) {
    case UpdateStatus.ok:
      return Icons.check_circle_outline;
    case UpdateStatus.failed:
      return Icons.error_outline;
    case UpdateStatus.inProgress:
      return Icons.hourglass_empty;
    case UpdateStatus.never:
      return Icons.schedule;
  }
}

String subscriptionStatusSubtitle(SubscriptionServers list) {
  final parts = <String>[];
  if (list.lastUpdated != null) {
    parts.add(
        getLocalText.s("Last success: %s", SubscriptionEntry.formatAgo(list.lastUpdated!)));
  }
  if (list.lastUpdateAttempt != null &&
      list.lastUpdateAttempt != list.lastUpdated) {
    parts.add(getLocalText.s("Last attempt: %s", SubscriptionEntry.formatAgo(list.lastUpdateAttempt!)));
  }
  if (list.lastNodeCount > 0) {
    parts.add(getLocalText.plural("%d nodes", list.lastNodeCount));
  }
  return parts.isEmpty ? '—' : parts.join(' · ');
}

String intervalHuman(int hours) {

  if (hours < 24) return '${hours}h';
  final d = hours ~/ 24;
  final rem = hours % 24;
  if (rem == 0) return getLocalText.plural("%d days", d);
  return '${d}d ${rem}h';
}





String formatBytes(int bytes) => fmt.formatBytes(bytes, spaced: true);

String formatExpire(int timestamp) {
  if (timestamp <= 0) return getLocalText.s("Unlimited");
  final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
  final diff = dt.difference(DateTime.now());
  if (diff.isNegative) return getLocalText.s("Expired");
  if (diff.inDays > 0) return getLocalText.plural("%d days left", diff.inDays);
  return getLocalText.plural("%d hours left", diff.inHours);
}
