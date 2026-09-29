import 'package:flutter/material.dart';

import 'l10n/locale_controller.dart';







mixin SnackHelper<T extends StatefulWidget> on State<T> {


  void showSnack(String message, {Duration? duration}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: duration ?? const Duration(seconds: 4)),
    );
  }
}




Future<bool?> showDeleteConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(getLocalText.s("Cancel")),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error),
          child: Text(confirmLabel ?? getLocalText.s("Delete")),
        ),
      ],
    ),
  );
}





Future<String?> showUnsavedChangesDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(getLocalText.s("Unsaved changes")),
        content: Text(getLocalText.s("You have unsaved changes. Save before leaving?")),

        actionsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: Text(getLocalText.s("Discard")),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'keep'),
            child: Text(getLocalText.s("Keep")),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            style: TextButton.styleFrom(
              foregroundColor: cs.primary,
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
            child: Text(getLocalText.s("Save")),
          ),
        ],
      );
    },
  );
}
