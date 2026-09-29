import 'package:flutter/material.dart';

import '../../../models/node_warning.dart';
import '../../../services/contract/contract_docs.dart';
import '../../../services/contract/registry.dart';
import '../../../services/contract/registry_warning.dart';
import '../../../services/contract/warning_codes.dart';
import '../../../services/l10n/locale_controller.dart';
import '../../../services/url_launcher.dart' as ul;
import '../../../widgets/banner_palette.dart';













class NodeNotificationsView extends StatelessWidget {
  const NodeNotificationsView(this.warnings, {super.key});

  final List<NodeWarning> warnings;

  @override
  Widget build(BuildContext context) {
    final byLevel = groupWarningsBySeverity(warnings);

    final present = byLevel.entries.where((e) => e.value.isNotEmpty).toList();
    if (present.isEmpty) return const SizedBox.shrink();



    final single = present.length == 1;

    final items = {
      for (final e in present) e.key: groupWarningsByCode(e.value),
    };


    final soleTile =
        items.values.fold<int>(0, (n, level) => n + level.length) == 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),


          child: _Counters(byLevel),
        ),
        for (final entry in present) ...[
          if (!single)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
              child: _LevelHeader(entry.key),
            ),
          for (final item in items[entry.key]!)
            item.length == 1
                ? _NotificationTile(item.single, initiallyExpanded: soleTile)
                : _NotificationGroupTile(item, initiallyExpanded: soleTile),
        ],
        const SizedBox(height: 4),
      ],
    );
  }
}







List<List<NodeWarning>> groupWarningsByCode(List<NodeWarning> level) {
  final out = <List<NodeWarning>>[];
  final byCode = <String, List<NodeWarning>>{};
  for (final w in level) {
    final code = warningCodeOf(w);
    if (code == null) {
      out.add([w]);
      continue;
    }
    final known = byCode[code];
    if (known != null) {
      known.add(w);
      continue;
    }
    final fresh = [w];
    byCode[code] = fresh;
    out.add(fresh);
  }
  return out;
}


const groupDiffersMark = '…';












RegistryWarning? mergeGroupSubstitutions(List<NodeWarning> group) {
  final subs = group.whereType<RegistryWarning>().toList();
  if (subs.isEmpty) return null;
  String? common(Iterable<String?> values) {
    final first = values.first;
    return values.every((v) => v == first) ? first : groupDiffersMark;
  }

  final keys = {for (final r in subs) ...r.params.keys};
  return RegistryWarning(
    code: subs.first.code,
    path: common(subs.map((r) => r.path)),
    value: common(subs.map((r) => r.value)),
    params: {
      for (final k in keys)

        k: common(subs.map((r) => r.params[k])) ?? groupDiffersMark,
    },
  );
}



Map<WarningSeverity, List<NodeWarning>> groupWarningsBySeverity(
    List<NodeWarning> warnings) {
  return {
    for (final level in const [
      WarningSeverity.error,
      WarningSeverity.warning,
      WarningSeverity.info,
    ])
      level: warnings.where((w) => w.severity == level).toList(),
  };
}



class _Counters extends StatelessWidget {
  const _Counters(this.byLevel);

  final Map<WarningSeverity, List<NodeWarning>> byLevel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = <Widget>[];
    for (final e in byLevel.entries) {
      if (e.value.isEmpty) continue;
      final (color, icon) = warningSeverityStyle(context, e.key);
      if (parts.isNotEmpty) {
        parts.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),

          child: Text('·', style: theme.textTheme.bodySmall),
        ));
      }
      parts.addAll([
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(
          '${e.value.length}',
          style: theme.textTheme.bodySmall?.copyWith(color: color),
        ),
      ]);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: parts);
  }
}


class _LevelHeader extends StatelessWidget {
  const _LevelHeader(this.severity);

  final WarningSeverity severity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, icon) = warningSeverityStyle(context, severity);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          severityTitle(severity),
          style: theme.textTheme.labelMedium
              ?.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}




String severityTitle(WarningSeverity severity) => switch (severity) {
      WarningSeverity.error => getLocalText.s("Errors"),
      WarningSeverity.warning => getLocalText.s("Warnings"),
      WarningSeverity.info => getLocalText.s(1, "Info"),
    };







class _NotificationTile extends StatelessWidget {
  const _NotificationTile(this.warning, {required this.initiallyExpanded});

  final NodeWarning warning;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, icon) = warningSeverityStyle(context, warning.severity);

    final code = warningCodeOf(warning);



    final w = switch (warning) {
      final RegistryWarning r => r.withSecretValueMasked(),
      final other => other,
    };
    final subst = w is RegistryWarning ? w : null;
    final path = subst?.path;

    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      dense: true,
      leading: Icon(icon, size: 18, color: color),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      title: Text(
        w.message(),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(color: color),
      ),

      subtitle: warning.ownerTag.isEmpty
          ? null
          : Text(
              getLocalText.s("Entry: %s", warning.ownerTag),
              key: ValueKey('notification-owner-${warning.ownerTag}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
      children: [
        if (path != null && path.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              path,
              style: _monospace,
            ),
          ),

        if (warning case final UnknownNodeTypeWarning u)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(u.detailWith(getLocalText),
                style: theme.textTheme.bodySmall),
          ),
        ..._breakdown(context, code, subst, notApplied: !warning.applied),
      ],
    );
  }
}







class _NotificationGroupTile extends StatelessWidget {
  const _NotificationGroupTile(this.group, {required this.initiallyExpanded});

  final List<NodeWarning> group;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = group.first;
    final (color, icon) = warningSeverityStyle(context, first.severity);
    final code = warningCodeOf(first)!;
    final known = ContractRegistry.I.textFor(code) != null;


    final entries = [
      for (final w in group)
        switch (w) {
          final RegistryWarning r => r.withSecretValueMasked(),
          final other => other,
        },
    ];
    final subst = mergeGroupSubstitutions(entries);


    final title =
        known && subst != null ? subst.message() : entries.first.message();
    final keyBase = '${first.severity.name}-$code';

    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      dense: true,
      leading: Icon(icon, size: 18, color: color),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      title: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${group.length}',
            key: ValueKey('notification-group-count-$keyBase'),
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ],
      ),
      children: [
        for (var i = 0; i < entries.length; i++)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _groupRowText(entries[i]),
              key: ValueKey('notification-group-row-$keyBase-$i'),
              style: _monospace,
            ),
          ),
        ..._breakdown(context, code, subst,
            notApplied: group.every((w) => !w.applied)),
      ],
    );
  }
}





String _groupRowText(NodeWarning w) {
  if (w is RegistryWarning) {
    final path = w.path;
    if (path != null && path.isNotEmpty) {
      final value = w.value;
      return value == null || value.isEmpty
          ? path
          : '$path = $value';
    }
  }
  if (w.ownerTag.isNotEmpty) return getLocalText.s("Entry: %s", w.ownerTag);
  return w.message();
}

const _monospace = TextStyle(fontSize: 12, fontFamily: 'monospace');












List<Widget> _breakdown(
    BuildContext context, String? code, RegistryWarning? subst,
    {bool notApplied = false}) {
  final theme = Theme.of(context);



  if (code == null || ContractRegistry.I.textFor(code) == null) {
    return const [];
  }
  final lang = registryLangForTag(LocaleController.I.effectiveTag);
  final path = subst?.path;
  final value = subst?.value;
  final params = subst?.params ?? const <String, String>{};
  final detail = notApplied
      ? getLocalText
          .s("The node is written by hand, so the app changed nothing in it.")
      : registryText(code, lang, path: path, value: value, params: params);
  final cause =
      registryCause(code, lang, path: path, value: value, params: params);
  final fix = registryFix(code, lang, path: path, value: value, params: params);
  return [
    if (detail.isNotEmpty)
      _Block(
        title: getLocalText.s("What happened"),
        child: Text(detail, style: theme.textTheme.bodySmall),
      ),
    if (cause != null)
      _Block(
        title: getLocalText.s("Why it happens"),
        child: Text(cause, style: theme.textTheme.bodySmall),
      ),
    if (fix.isNotEmpty)
      _Block(
        title: getLocalText.s("What you can do"),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final step in fix)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    Text('•  ', style: theme.textTheme.bodySmall),
                    Expanded(
                      child: Text(step, style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(Icons.open_in_new, size: 16),
        onPressed: () => ul.UrlLauncher.open(contractWarningDocUrl(code)),
        label: Text(getLocalText.s("Details")),
      ),
    ),
  ];
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Align(alignment: Alignment.centerLeft, child: child),
        ],
      ),
    );
  }
}
