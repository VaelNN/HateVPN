import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/node_spec.dart';
import '../../models/template_vars.dart';
import '../../services/l10n/locale_controller.dart';
import '../../services/tag_resolver.dart';
import '../../widgets/lx_code_editor.dart';
import '../../widgets/node_diagnostics_tab.dart';
import '../../widgets/tailscale_network_tab.dart';












enum NodeInspectTab { json, source, replacements, diagnostics }

class NodeInspectScreen extends StatefulWidget {
  const NodeInspectScreen({
    super.key,
    required this.node,
    this.tagPrefix = '',
    this.initialTab = NodeInspectTab.json,
  });

  final NodeSpec node;




  final String tagPrefix;


  final NodeInspectTab initialTab;



  static int tabIndex(NodeInspectTab tab,
      {required bool hasReplacements, bool hasNetwork = false}) {
    switch (tab) {
      case NodeInspectTab.json:
        return 0;
      case NodeInspectTab.source:
        return 1;
      case NodeInspectTab.replacements:
        return hasReplacements ? 2 : 0;
      case NodeInspectTab.diagnostics:
        return (hasReplacements ? 3 : 2) + (hasNetwork ? 1 : 0);
    }
  }

  @override
  State<NodeInspectScreen> createState() => _NodeInspectScreenState();
}

class _NodeInspectScreenState extends State<NodeInspectScreen> {


  bool _extended = false;

  NodeSpec get _node => widget.node;

  String get _json => const JsonEncoder.withIndent('  ')
      .convert(_node.emit(TemplateVars.empty).map);


  String get _source {
    final compact = _node.rawSource;
    if (!_extended) return compact;
    return _node.sourceExtended ?? compact;
  }

  bool get _hasExtended => (_node.sourceExtended ?? '').isNotEmpty;




  bool get _hasReplacements => _node.ruleTrail.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final title = _node.label.isNotEmpty ? _node.label : _node.tag;
    final hasReplacements = _hasReplacements;
    final warnings = _node.warnings;


    final node = _node;
    final tailscale = node is TailscaleSpec;
    final liveTag = TagResolver.displayTag(widget.tagPrefix, _node.tag);
    return DefaultTabController(
      length: (hasReplacements ? 4 : 3) + (tailscale ? 1 : 0),
      initialIndex: NodeInspectScreen.tabIndex(widget.initialTab,
          hasReplacements: hasReplacements, hasNetwork: tailscale),
      child: Scaffold(
        appBar: AppBar(
          title: Text(title.isEmpty ? _node.server : title,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: getLocalText.s("JSON")),
              Tab(text: getLocalText.s("Source")),
              if (hasReplacements)
                Tab(text: getLocalText.s("Replacements")),
              if (tailscale) Tab(text: getLocalText.s("Network")),


              NodeDiagnosticsTabLabel(warnings: warnings),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _monoBody(context, _json),
            _sourceTab(context),
            if (hasReplacements) _replacementsTab(context),
            if (node is TailscaleSpec)
              TailscaleNetworkTab(liveTag: liveTag, body: node.body),
            NodeDiagnosticsTab(
              node: _node,
              liveTag: liveTag,
              warnings: warnings,
              scrollToNotifications:
                  widget.initialTab == NodeInspectTab.diagnostics,
            ),
          ],
        ),
      ),
    );
  }





  Widget _replacementsTab(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: theme.colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.edit_note, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  getLocalText.s(
                      "Import rules changed this node. The JSON tab shows the result."),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _monoBody(context, _node.ruleTrail.join('\n'))),
      ],
    );
  }

  Widget _sourceTab(BuildContext context) {
    final text = _source;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [


        if (_hasExtended)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(getLocalText.s("Compact")),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(getLocalText.s("Extended")),
                ),
              ],
              selected: {_extended},
              onSelectionChanged: (s) => setState(() => _extended = s.first),
            ),
          ),
        if (_hasExtended)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(
              _extended
                  ? getLocalText.s("The whole element as the provider sent it")
                  : getLocalText.s("Just the outbound this node was built from"),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        Expanded(child: _monoBody(context, text)),
      ],
    );
  }

  Widget _monoBody(BuildContext context, String text) {
    if (text.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            getLocalText.s("Nothing to show"),
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: LxJsonView(text: text),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: getLocalText.s("Copy"),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(getLocalText.s("Copied"))),
              );
            },
          ),
        ),
      ],
    );
  }
}
