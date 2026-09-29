import 'package:flutter/material.dart';

import '../../../models/dns_ref.dart';
import '../../../widgets/reorder_grab_strip.dart';
import '../dns_body_dialogs.dart';
import '../dns_format.dart';
import 'dns_badge.dart';






class DnsRuleTile extends StatelessWidget {
  const DnsRuleTile({
    required super.key,
    required this.index,
    required this.entry,
    required this.templateRulesByName,
    required this.presetRulesByPresetId,
    required this.presetLabelByPresetId,
    required this.onToggleEnabled,
    required this.onEdit,
    required this.onDelete,
    this.dragIndex,
  });


  final int index;




  final int? dragIndex;

  final DnsRuleRef entry;
  final Map<String, Map<String, dynamic>> templateRulesByName;
  final Map<String, List<Map<String, dynamic>>> presetRulesByPresetId;
  final Map<String, String> presetLabelByPresetId;
  final void Function(int index, bool value) onToggleEnabled;
  final void Function(int index) onEdit;
  final void Function(int index) onDelete;

  @override
  Widget build(BuildContext context) {
    final kind = entry.kind;
    final enabled = entry.enabled;
    final theme = Theme.of(context);



    final String displayTitle;
    Map<String, dynamic>? body;

    List<Map<String, dynamic>>? bodies;
    switch (entry) {
      case DnsRuleInline(:final name, :final rule):
        displayTitle = name;
        body = rule;
      case DnsRuleTemplate(:final name):
        displayTitle = name;
        body = templateRulesByName[displayTitle];
      case DnsRulePreset(:final presetId):
        displayTitle = presetLabelByPresetId[presetId] ?? presetId;
        bodies = presetRulesByPresetId[presetId];
      case DnsRuleSrs(:final name, :final srsUrl, :final server):
        displayTitle = name;


        body = {
          'srsUrl': srsUrl,
          'server': server,
        };
    }

    final preview = bodies != null
        ? formatRulesPreview(bodies, kind: kind)
        : formatRulePreview(body, kind: kind);

    final badgeText = switch (kind) {
      'template' => 'template',
      'preset' => 'preset',
      'srs' => 'srs',
      _ => 'inline',
    };
    final badgeColor = switch (kind) {
      'template' => theme.colorScheme.tertiary,
      'preset' => theme.colorScheme.primary,
      'srs' => theme.colorScheme.outline,
      _ => theme.colorScheme.secondary,
    };






    final tile = Card(
      child: ListTile(
        onTap: () => showRuleBodyDialog(
            context, displayTitle, kind, bodies ?? body),
        leading: Switch(
          value: enabled,
          onChanged: (v) => onToggleEnabled(index, v),
        ),
        title: Text(
          displayTitle,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: enabled ? null : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        subtitle: Text(
          preview,
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant,
            fontFamily: 'monospace',
          ),

          maxLines: (bodies != null && bodies.length > 1)
              ? 2 * bodies.length
              : 2,
          overflow: TextOverflow.ellipsis,
        ),


        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            DnsBadge(badgeText, badgeColor),
            if (kind == 'inline') ...[
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => onEdit(index),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        size: 18, color: theme.colorScheme.error),
                    onPressed: () => onDelete(index),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );

    if (dragIndex == null) return tile;

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 30),
          child: tile,
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: ReorderGrabStrip(index: dragIndex!),
        ),
      ],
    );
  }
}
