import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/node_spec.dart';
import '../../../models/node_warning.dart';
import '../../../models/ui_msg.dart';
import '../../../services/probe/probe_runner.dart';
import '../../../widgets/banner_palette.dart';
import '../../../widgets/probe_badge.dart';
import 'node_warning_row.dart';
import '../node_inspect_screen.dart';
import '../../../services/l10n/locale_controller.dart';
import '../../../widgets/app_bottom_sheet.dart';




class SubscriptionNodeList extends StatelessWidget {
  const SubscriptionNodeList({
    super.key,
    required this.nodes,
    required this.loading,
    required this.error,
    this.togglableNodes = const {},
    this.disabledNodes = const {},
    this.chainHops = const {},
    this.onToggleNode,
    this.probe = const {},
    this.probeThresholds = ProbeThresholds.defaults,
    this.tagPrefix = '',
  });



  final String tagPrefix;

  final List<NodeSpec>? nodes;
  final bool loading;
  final UiMsg? error;




  final Set<NodeSpec> togglableNodes;




  final Set<NodeSpec> disabledNodes;






  final Set<NodeSpec> chainHops;

  final void Function(NodeSpec node)? onToggleNode;



  final Map<NodeSpec, ProbeResult> probe;
  final ProbeThresholds probeThresholds;



  String _rowTitle(NodeSpec node) {
    final base = node.label.isNotEmpty ? node.label : node.tag;
    return chainHops.contains(node) ? '⚙ $base' : base;
  }




  static bool _hasActionable(NodeSpec node) =>
      node.warnings.any((w) => w.severity != WarningSeverity.info);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(error!.render(),
              style: TextStyle(color: theme.colorScheme.error)),
        ),
      );
    }

    final nodes = this.nodes;
    if (nodes == null && !loading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(getLocalText.s("Update subscription to see nodes")),
        ),
      );
    }

    if (nodes == null || nodes.isEmpty) {
      if (loading) return const SizedBox.shrink();
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(getLocalText.s("No nodes found")),
        ),
      );
    }



    final actionableCount = nodes.where(_hasActionable).length;


    final warnColor = warningSeverityColor(context, WarningSeverity.warning);
    return Column(
      children: [
        if (actionableCount > 0)
          Container(
            width: double.infinity,
            color: warnColor.withValues(alpha: 0.15),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.warning_amber, size: 16, color: warnColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    getLocalText.plural("%d nodes with warnings (XHTTP fallback etc.)", actionableCount),
                    style: TextStyle(fontSize: 12, color: warnColor),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(


      padding: EdgeInsets.fromLTRB(
          12, 0, 12, MediaQuery.of(context).padding.bottom + 24),
      itemCount: nodes.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final node = nodes[i];

        final togglable =
            onToggleNode != null && togglableNodes.contains(node);
        final disabled = disabledNodes.contains(node);
        final probeResult = probe[node];
        return ListTile(
          contentPadding: EdgeInsets.zero,




          leading: togglable
              ? SizedBox(
                  width: 40,
                  child: Switch(
                    value: !disabled,
                    onChanged: (_) => onToggleNode!(node),
                  ),
                )
              : (togglableNodes.isEmpty ? null : const SizedBox(width: 40)),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  _rowTitle(node),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,

                    color:
                        disabled ? theme.colorScheme.onSurfaceVariant : null,
                  ),
                ),
              ),






              if (node.ruleTrail.isNotEmpty) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: getLocalText.s("Modified by import rules"),
                  child: Icon(Icons.edit_note,
                      size: 16, color: theme.colorScheme.primary),
                ),
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [






                  if (node.warnings.isNotEmpty && !_hasActionable(node))
                    NodeInfoBadge(node.warnings),
                  Flexible(
                    child: Text(
                      '${node.protocol}  ${node.server}:${node.port}',
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),


              if (_hasActionable(node)) NodeWarningRow(node.warnings),
            ],
          ),

          trailing: probeResult == null
              ? null
              : ProbeBadge(
                  result: probeResult,
                  thresholds: probeThresholds,
                  onTap: () {
                    if (probeResult.message.isEmpty) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(probeResult.message)),
                    );
                  },
                ),
          dense: true,




          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => NodeInspectScreen(node: node, tagPrefix: tagPrefix),
          )),
          onLongPress: () => _showNodeMenu(context, node),
        );
      },
          ),
        ),
      ],
    );
  }

  void _showNodeMenu(BuildContext context, NodeSpec node) {
    final info = node.rawSource.isNotEmpty
        ? node.rawSource
        : '${node.protocol}://${node.server}:${node.port}';
    showAppBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text(getLocalText.s("Copy node info")),
              subtitle: Text(info, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
              onTap: () {
                Clipboard.setData(ClipboardData(text: info));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(getLocalText.s("Node info copied"))),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: Text(getLocalText.s("Copy tag")),
              subtitle: Text(node.tag, style: const TextStyle(fontSize: 11)),
              onTap: () {
                Clipboard.setData(ClipboardData(text: node.tag));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(getLocalText.s("Tag copied"))),
                );
              },
            ),




            ListTile(
              leading: const Icon(Icons.data_object),
              title: Text(getLocalText.s("Inspect node")),

              subtitle: Text(getLocalText.s("JSON, source and replacements"),
                  style: const TextStyle(fontSize: 11)),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => NodeInspectScreen(node: node, tagPrefix: tagPrefix),
                ));
              },
            ),
          ],
        ),
      ),
    );
  }
}
