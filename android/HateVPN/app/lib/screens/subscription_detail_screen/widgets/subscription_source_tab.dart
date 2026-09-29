import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/ui_msg.dart';

import '../../../services/l10n/locale_controller.dart';
import '../../../widgets/big_text_view.dart';
import '../../../widgets/safe_bottom.dart';




class SubscriptionSourceTab extends StatelessWidget {
  const SubscriptionSourceTab({
    super.key,
    required this.hasUrl,
    required this.sourceLoading,
    required this.sourceError,
    required this.rawHeaders,
    required this.rawSource,
    required this.showAllHeaders,
    required this.importantHeaders,
    required this.moreHeaders,
    required this.onRefetch,
    required this.onToggleShowAll,
    this.canDecode = false,
    this.decoded = false,
    this.onToggleDecode,
  });

  final bool hasUrl;
  final bool sourceLoading;
  final UiMsg? sourceError;
  final Map<String, String> rawHeaders;
  final String rawSource;
  final bool showAllHeaders;



  final List<MapEntry<String, String>> importantHeaders;



  final List<MapEntry<String, String>> moreHeaders;

  final VoidCallback onRefetch;
  final VoidCallback onToggleShowAll;



  final bool canDecode;



  final bool decoded;

  final ValueChanged<bool>? onToggleDecode;

  bool get _hasMoreHeaders => moreHeaders.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;




    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                if (hasUrl) ...[
                  Row(
                    children: [
                      Text(
                        sourceLoading
                            ? getLocalText.s("Fetching…")
                            : getLocalText.s("Response headers"),
                        style: theme.textTheme.titleSmall?.copyWith(
                            color: cs.primary, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 18),
                        tooltip: getLocalText.s("Re-fetch live"),
                        visualDensity: VisualDensity.compact,
                        onPressed: sourceLoading ? null : onRefetch,
                      ),
                      if (rawHeaders.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.copy, size: 16),
                          tooltip: getLocalText.s("Copy headers"),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            final text = rawHeaders.entries
                                .map((e) => '${e.key}: ${e.value}')
                                .join('\n');
                            Clipboard.setData(ClipboardData(text: text));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      getLocalText.s("Headers copied"))),
                            );
                          },
                        ),
                    ],
                  ),
                  const Divider(),
                  if (sourceError != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                          getLocalText.s(
                              "Fetch failed: %s", sourceError!.render()),
                          style: TextStyle(fontSize: 12, color: cs.error)),
                    )
                  else if (sourceLoading && rawHeaders.isEmpty)
                    const LinearProgressIndicator()
                  else if (rawHeaders.isEmpty)
                    Text(getLocalText.s("No data — tap refresh above"),
                        style: const TextStyle(
                            fontSize: 12, fontStyle: FontStyle.italic))
                  else ...[
                    for (final h in importantHeaders)
                      _headerRow(h.key, h.value, theme),
                    if (_hasMoreHeaders) ...[
                      const SizedBox(height: 4),
                      TextButton.icon(
                        onPressed: onToggleShowAll,
                        icon: Icon(
                            showAllHeaders
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 16),
                        label: Text(showAllHeaders
                            ? getLocalText.s("Hide others")
                            : getLocalText.s("Show all (%d)",
                                rawHeaders.length - importantHeaders.length)),
                      ),
                      if (showAllHeaders)
                        for (final h in moreHeaders)
                          _headerRow(h.key, h.value, theme),
                    ],
                  ],
                  const SizedBox(height: 16),
                ],




                Row(
                  children: [
                    Text(getLocalText.s("Raw response"),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.bold,
                        )),
                    const Spacer(),
                    if (rawSource.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        tooltip: getLocalText.s("Copy source"),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: rawSource));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content:
                                    Text(getLocalText.s("Source copied"))),
                          );
                        },
                      ),
                  ],
                ),






                if (canDecode)
                  CheckboxListTile(
                    value: decoded,
                    onChanged: onToggleDecode == null
                        ? null
                        : (v) => onToggleDecode!(v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(getLocalText.s("Decode base64"),
                        style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                      getLocalText.s(
                          "Show the decoded body — what import rules see"),
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ),
                const Divider(),
                if (rawSource.isEmpty)
                  Text(getLocalText.s("No cached source data")),
              ],
            ),
          ),
        ),
        if (rawSource.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12).withSafeBottom(context),
            sliver: BigTextSliver(
              text: rawSource,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
      ],
    );
  }

  Widget _headerRow(String name, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(name, style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            )),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
