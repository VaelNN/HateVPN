import 'package:flutter/material.dart';

import '../../../models/parser_config.dart';
import '../../../services/l10n/locale_controller.dart';




class PresetCatalogTile extends StatelessWidget {
  const PresetCatalogTile({
    super.key,
    required this.rule,
    required this.existing,
    required this.onCopy,
  });

  final SelectableRule rule;


  final bool existing;


  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(rule.label,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
              ),
              TextButton.icon(
                icon: Icon(existing ? Icons.check : Icons.add, size: 16),
                label: Text(existing
                    ? getLocalText.s("In Rules")
                    : getLocalText.s("Add to Rules")),
                onPressed: existing ? null : onCopy,
              ),
            ],
          ),
          if (rule.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(rule.description,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}
