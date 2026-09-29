import 'package:flutter/material.dart';

import '../../../models/node_warning.dart';
import '../../../services/l10n/locale_controller.dart';
import '../../../widgets/app_bottom_sheet.dart';
import 'node_notifications_view.dart';











Future<void> showNodeWarningsSheet(
  BuildContext context,
  List<NodeWarning> warnings, {
  String? sourceLabel,
}) {
  return showAppBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => NodeWarningsSheet(warnings, sourceLabel: sourceLabel),
  );
}



class NodeWarningsSheet extends StatelessWidget {
  const NodeWarningsSheet(this.warnings, {this.sourceLabel, super.key});

  final List<NodeWarning> warnings;


  final String? sourceLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  getLocalText.s("Notifications"),
                  style: theme.textTheme.titleMedium,
                ),
                if (sourceLabel != null && sourceLabel!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      sourceLabel!,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 8),
              child: NodeNotificationsView(warnings),
            ),
          ),
        ],
      ),
    );
  }
}
