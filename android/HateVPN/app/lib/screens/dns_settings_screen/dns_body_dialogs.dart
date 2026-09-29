import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/l10n/locale_controller.dart';







void showRuleBodyDialog(
    BuildContext context, String title, String kind, Object? body) {
  final unwrapped = switch (body) {
    List(isEmpty: true) => null,
    [final only] => only,
    _ => body,
  };
  final pretty = unwrapped == null
      ? getLocalText.s("(content unavailable)")
      : const JsonEncoder.withIndent('  ').convert(unwrapped);
  final sourceLabel = switch (kind) {
    'template' => getLocalText.s("template"),
    'preset' => getLocalText.s("preset"),
    'srs' => getLocalText.s("srs"),
    'rule' => getLocalText.s("routing rule"),

    'node' => getLocalText.s("node"),
    _ => getLocalText.s("user rule"),
  };
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: const TextStyle(fontSize: 15)),
          Text(sourceLabel,
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
        ],
      ),
      content: SingleChildScrollView(
        child: SelectableText(
          pretty,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(getLocalText.s("Close")),
        ),
      ],
    ),
  );
}
