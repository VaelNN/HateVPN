import 'package:flutter/material.dart';

import '../../../vpn/cc_channel.dart';
import '../resolved_server.dart';
import 'dns_badge.dart';
import '../../../services/l10n/locale_controller.dart';













class MergedServerTile extends StatelessWidget {
  const MergedServerTile({
    super.key,
    required this.entry,
    required this.onToggleEnabled,
    required this.onTap,
    this.liveGroup,
  });

  final ResolvedServer entry;
  final void Function(String tag, bool value) onToggleEnabled;


  final void Function(String tag) onTap;



  final CcDnsGroup? liveGroup;

  @override
  Widget build(BuildContext context) {
    final type = entry.body['type']?.toString() ?? '';
    final addr = entry.body['server']?.toString() ?? '';
    final theme = Theme.of(context);
    final locked = entry.locked;


    final (String badgeText, Color badgeColor) = switch (entry.kind) {
      ServerKind.template => (
        getLocalText.s("Template"),
        theme.colorScheme.tertiary,
      ),
      ServerKind.preset => (
        getLocalText.s("Preset"),
        theme.colorScheme.primary,
      ),
      ServerKind.inline =>
        entry.isOverridden
            ? (
                getLocalText.s("Overridden"),
                theme.colorScheme.error.withValues(alpha: 0.9),
              )
            : (getLocalText.s("User"), theme.colorScheme.secondary),
    };


    final groupInfo = type == 'group'
        ? ' · ${(entry.body['mode'] as String?) ?? 'stable'}'
              ' · ${(entry.body['servers'] as List?)?.length ?? 0}'
        : '';
    final subtitleLine =
        '${entry.tag} · $type$groupInfo${addr.isNotEmpty ? ' · $addr' : ''}'
        '${entry.presetLabel != null && entry.presetLabel!.isNotEmpty ? ' · ${entry.presetLabel}' : ''}';

    return Card(
      child: ListTile(
        onTap: () => onTap(entry.tag),
        leading: SizedBox(
          width: 40,
          child: Switch(

            value: entry.enabled || locked,
            onChanged: locked ? null : (v) => onToggleEnabled(entry.tag, v),
          ),
        ),
        title: Text(
          entry.description.isNotEmpty ? entry.description : entry.tag,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: entry.enabled || locked
                ? null
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subtitleLine,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (locked)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 12,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    getLocalText.s("used by %s", entry.lockedByLabel),
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),

            if (liveGroup != null) _LiveGroupLine(liveGroup!),
          ],
        ),
        trailing: DnsBadge(badgeText, badgeColor),
      ),
    );
  }
}




class _LiveGroupLine extends StatelessWidget {
  const _LiveGroupLine(this.g);
  final CcDnsGroup g;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 10,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (g.current.isNotEmpty)
            Text(

              '→ ${g.current}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.primary,
              ),
            ),
          for (final m in g.members)
            Text(
              _memberLabel(m),
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: m.clean ? cs.onSurfaceVariant : cs.error,
              ),
            ),
        ],
      ),
    );
  }


  String _memberLabel(CcDnsGroupMember m) {
    final b = StringBuffer(m.tag);
    if (m.clean) {
      b.write(' ✓');
      if (m.lastRttMs > 0) b.write(' ${m.lastRttMs}ms');
      if (g.mode == 'fastest' && m.liveWins > 0) b.write(' w${m.liveWins}');
    } else {
      b.write(' ✗${m.liveErrors}');
      if (m.lastErrorAgeMs >= 0) {
        b.write(' (${(m.lastErrorAgeMs / 1000).round()}s)');
      }
    }
    if (m.current) b.write(' ●');
    return b.toString();
  }
}
