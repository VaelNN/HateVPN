import 'package:flutter/material.dart';

import '../../../widgets/reorder_grab_strip.dart';
import '../dns_body_dialogs.dart';
import '../dns_format.dart';
import 'dns_badge.dart';
import '../../../services/l10n/locale_controller.dart';







class DnsMirrorGroupCard extends StatelessWidget {
  const DnsMirrorGroupCard({
    super.key,
    required this.children,
    this.dragIndex,
  });



  final List<Widget> children;



  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);




    final card = Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Icon(Icons.alt_route,
                    size: 14, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    getLocalText.s("From routing rules · ordered as in Routing"),
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...children,
          const SizedBox(height: 4),
        ],
      ),
    );

    if (dragIndex == null) return card;

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 30),
          child: card,
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









class DnsMirrorTile extends StatelessWidget {
  const DnsMirrorTile({
    super.key,
    required this.title,
    required this.previewBodies,
    required this.sourceKind,
    required this.enabled,
    required this.onToggle,
    this.note,
  });

  final String title;





  final List<Map<String, dynamic>> previewBodies;



  final String sourceKind;

  final bool enabled;



  final ValueChanged<bool>? onToggle;


  final String? note;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (String badgeText, Color badgeColor) = switch (sourceKind) {
      'preset' => ('preset', cs.primary),

      'node' => ('node', cs.tertiary),
      _ => ('rule', cs.secondary),
    };
    final preview = formatRulesPreview(previewBodies, kind: sourceKind);
    final subtitle = (note != null && note!.isNotEmpty)
        ? (preview.isEmpty ? note! : '$preview · $note')
        : preview;
    return Card(
      child: ListTile(
        onTap: () =>
            showRuleBodyDialog(context, title, sourceKind, previewBodies),


        leading: onToggle == null
            ? Icon(Icons.dns_outlined, size: 22, color: cs.onSurfaceVariant)
            : Switch(value: enabled, onChanged: onToggle),
        title: Text(
          title.isNotEmpty ? title : getLocalText.s("(unnamed rule)"),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: enabled ? null : cs.onSurfaceVariant,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 11,
            color: cs.onSurfaceVariant,
            fontFamily: 'monospace',
          ),


          maxLines: previewBodies.length > 1 ? 2 * previewBodies.length : 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: DnsBadge(badgeText, badgeColor),
      ),
    );
  }
}


class DnsAspectRow {
  const DnsAspectRow({
    required this.body,
    required this.enabled,
    this.onToggle,
    this.onRemove,
    this.note,
  });


  final Map<String, dynamic> body;
  final bool enabled;



  final ValueChanged<bool>? onToggle;



  final VoidCallback? onRemove;
  final String? note;
}







class DnsRuleAspectsTile extends StatelessWidget {
  const DnsRuleAspectsTile({
    super.key,
    required this.title,
    this.serverRow,
    this.forceIpv4Row,
  });

  final String title;
  final DnsAspectRow? serverRow;
  final DnsAspectRow? forceIpv4Row;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title.isNotEmpty ? title : getLocalText.s("(unnamed rule)"),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
                DnsBadge('rule', cs.secondary),
              ],
            ),
          ),
          if (serverRow != null)
            _aspectRow(context, getLocalText.s("Server"), serverRow!),
          if (forceIpv4Row != null)
            _aspectRow(context, getLocalText.s("Force IPv4 (drop AAAA)"), forceIpv4Row!),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _aspectRow(BuildContext context, String label, DnsAspectRow row) {
    final cs = Theme.of(context).colorScheme;
    final preview = formatRulePreview(row.body, kind: 'rule');
    final subtitle = (row.note != null && row.note!.isNotEmpty)
        ? '$preview · ${row.note}'
        : preview;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      onTap: () =>
          showRuleBodyDialog(context, '$title · $label', 'rule', row.body),


      leading: row.onToggle != null
          ? Switch(value: row.enabled, onChanged: row.onToggle)
          : Icon(Icons.dns_outlined, size: 20, color: cs.onSurfaceVariant),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          color: row.enabled ? null : cs.onSurfaceVariant,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 11,
          color: cs.onSurfaceVariant,
          fontFamily: 'monospace',
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: row.onRemove == null
          ? null
          : IconButton(
              icon: Icon(Icons.close, size: 18, color: cs.error),
              tooltip: getLocalText.s("Remove"),
              visualDensity: VisualDensity.compact,
              onPressed: row.onRemove,
            ),
    );
  }
}
