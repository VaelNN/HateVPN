import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/codec/rule_record.dart';
import '../../../models/custom_rule.dart';
import '../../../services/builder/post_steps.dart';
import '../../../services/builder/preset_expand.dart';
import '../../../services/builder/rule_set_registry.dart';
import '../edit_controller.dart';
import '../../../services/l10n/locale_controller.dart';






class ViewTab extends StatelessWidget {
  const ViewTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = CustomRuleEditScope.of(context);
    final theme = Theme.of(context);

    String json;
    List<String> warnings = const [];
    try {
      if (c.kind == CustomRuleKind.preset) {
        final preset = c.preset;
        if (preset == null) {
          json =
              '// broken preset: "${c.initial.presetId}" — no definition in template';
        } else {
          final snap = c.snapshot();

          final fragments = expandPreset(
            snap as CustomRulePreset,
            preset,
            srsPaths: c.presetSrsPaths,
            globalVars: c.globalVars,
            nodes: c.presetNodes,
          );
          warnings = fragments.warnings;




          final dnsOptions = <String, dynamic>{
            if (fragments.dnsServers.isNotEmpty) 'servers': fragments.dnsServers,


            if (fragments.dnsRules.isNotEmpty) 'rules': fragments.dnsRules,
          };
          final route = <String, dynamic>{
            if (fragments.ruleSets.isNotEmpty) 'rule_set': fragments.ruleSets,


            if (fragments.routingRules.isNotEmpty)
              'rules': fragments.routingRules,
          };
          json = const JsonEncoder.withIndent('  ').convert({
            if (dnsOptions.isNotEmpty) 'dns_options': dnsOptions,
            if (route.isNotEmpty) 'route': route,
          });
        }
      } else {
        final reg = RuleSetRegistry();




        final srsPaths = <String, String>{};
        if (c.kind == CustomRuleKind.srs) {
          srsPaths[c.initial.id] = c.srsState == SrsDownloadState.cached
              ? '<cached file path>'
              : '<download first>';
        }



        warnings = applyCustomRules(reg, [c.snapshot()],
            srsPaths: srsPaths, skipDisabled: false);
        json = const JsonEncoder.withIndent('  ').convert({
          'rule_set': reg.getRuleSets(),
          'rules': reg.getRules(),
        });
      }
    } catch (e) {
      json = '// error: $e';
    }






    final storageJson =
        const JsonEncoder.withIndent('  ').convert(ruleToRecord(c.initial));

    return Padding(
      padding: EdgeInsets.fromLTRB(
          12, 12, 12, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          Row(
            children: [
              Expanded(
                child: Text(getLocalText.s("storage shape (lxbox_settings.json)"),
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ),
              _CopyButton(text: storageJson),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            constraints: const BoxConstraints(maxHeight: 180),
            child: SingleChildScrollView(
              child: SelectableText(
                storageJson,
                style:
                    const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: Text(getLocalText.s("sing-box config preview"),
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ),
              _CopyButton(text: json),
            ],
          ),
          const SizedBox(height: 4),
          if (warnings.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(warnings.join('\n'),
                  style: TextStyle(
                      fontSize: 12, color: theme.colorScheme.error)),
            ),
            const SizedBox(height: 8),
          ],
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  json,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      icon: const Icon(Icons.content_copy, size: 14),
      label: Text(getLocalText.s("Copy"), style: const TextStyle(fontSize: 12)),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        final copied = getLocalText.s("Copied");
        await Clipboard.setData(ClipboardData(text: text));
        messenger.showSnackBar(
          SnackBar(content: Text(copied)),
        );
      },
    );
  }
}
