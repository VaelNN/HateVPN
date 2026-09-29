import 'package:flutter/material.dart';

import '../../../models/node_warning.dart';
import '../../../services/l10n/locale_controller.dart';
import '../../../widgets/banner_palette.dart';
import '../../subscriptions_screen/entry_warnings.dart';
import 'node_warnings_sheet.dart';



















class NodeWarningRow extends StatelessWidget {
  const NodeWarningRow(this.warnings, {super.key});

  final List<NodeWarning> warnings;

  @override
  Widget build(BuildContext context) {
    final sorted = [...warnings]
      ..sort((a, b) => b.severity.index.compareTo(a.severity.index));


    final spoken = sorted
        .where((w) => w.severity != WarningSeverity.info)
        .toList();
    final hasInfo = sorted.any((w) => w.severity == WarningSeverity.info);

    if (spoken.isEmpty) return const SizedBox.shrink();

    final w = spoken.first;
    final (color, icon) = warningSeverityStyle(context, w.severity);
    final more = spoken.length - 1;

    return Semantics(
      button: true,




      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showNodeWarningsSheet(context, warnings),
        child: Row(
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                more > 0
                    ? getLocalText.s(
                        "%1\$s (+%2\$d more)", inlineWarningMessage(w), more)
                    : inlineWarningMessage(w),
                style: TextStyle(fontSize: 10, color: color),
              ),
            ),

            if (hasInfo) NodeInfoBadge(warnings),
          ],
        ),
      ),
    );
  }
}













class NodeInfoBadge extends StatelessWidget {
  const NodeInfoBadge(this.warnings,
      {super.key, this.showTopSeverity = false});






  final List<NodeWarning> warnings;


  final bool showTopSeverity;

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty) return const SizedBox.shrink();

    late final WarningSeverity severity;
    late final Color color;
    late final IconData icon;
    late final String semanticsLabel;

    if (showTopSeverity) {
      final sorted = [...warnings]
        ..sort((a, b) => b.severity.index.compareTo(a.severity.index));
      final top = sorted.first;
      severity = top.severity;
      semanticsLabel = top.message();
      if (severity == WarningSeverity.info) {
        color = Theme.of(context).colorScheme.onSurfaceVariant;
        icon = Icons.info_outline;
      } else {
        final styled = warningSeverityStyle(context, severity);
        color = styled.$1;
        icon = styled.$2;
      }
    } else {
      final infos =
          warnings.where((w) => w.severity == WarningSeverity.info).toList();
      if (infos.isEmpty) return const SizedBox.shrink();
      severity = WarningSeverity.info;
      semanticsLabel = infos.first.message();
      color = Theme.of(context).colorScheme.onSurfaceVariant;
      icon = Icons.info_outline;
    }

    return Semantics(
      button: true,


      label: semanticsLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showNodeWarningsSheet(context, warnings),
        child: SizedBox(
          width: 24,
          height: 24,
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }
}
