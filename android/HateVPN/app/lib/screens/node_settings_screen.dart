import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/tag_resolver.dart';
import '../controllers/subscription_controller.dart';
import '../models/codec/source_record.dart';
import '../vpn/box_vpn_client.dart';
import '../services/error_format.dart';
import '../services/preset_nodes_view.dart';
import '../services/settings_storage.dart';
import '../services/template_loader.dart';
import '../models/direction.dart';
import '../models/node_link.dart';
import '../models/node_spec.dart';
import '../models/node_warning.dart';
import '../models/server_list.dart';
import '../models/template_vars.dart';
import '../widgets/detour_target_picker.dart';
import '../widgets/emoji_picker_button.dart';
import '../widgets/lx_code_editor.dart';
import '../widgets/node_diagnostics_tab.dart';
import '../widgets/tailscale_network_tab.dart';
import '../services/tailscale_network.dart';
import '../services/l10n/locale_controller.dart';
import 'node_settings/node_document.dart';
import 'subscriptions_screen/entry_warnings.dart';

















class NodeSettingsScreen extends StatefulWidget {
  const NodeSettingsScreen({
    super.key,
    required this.entry,
    required this.index,
    required this.subController,
    this.memberIndex,
    this.initialTab = 0,
  });

  final SubscriptionEntry entry;
  final int index;
  final SubscriptionController subController;


  final int? memberIndex;


  final int initialTab;




  static const diagnosticsTabIndex = 3;

  @override
  State<NodeSettingsScreen> createState() => _NodeSettingsScreenState();
}

class _NodeSettingsScreenState extends State<NodeSettingsScreen>
    with SingleTickerProviderStateMixin {
  late TextEditingController _tagCtrl;
  late TextEditingController _jsonCtrl;


  late TextEditingController _sourceCtrl;


  String _originKind = 'uri';
  late TabController _tabs;
  static const _kSourceTab = 1;
  String _originalTag = '';
  String _scheme = '';
  String _serverInfo = '';
  NodeLink _detour = NodeLink.none;



  bool _isAwg = false;



  List<Direction> _directions = const [];



  NodeSpec? _node;



  List<NodeWarning> _notifications = const [];



  bool _skipPresetsVisible = false;


  bool _isTailscale = false;

  @override
  void initState() {
    super.initState();
    _tagCtrl = TextEditingController();
    _jsonCtrl = TextEditingController();
    _sourceCtrl = TextEditingController();

    final first = _member?.node ??
        (widget.entry.list.nodes.isEmpty ? null : widget.entry.list.nodes.first);
    _isTailscale = first is TailscaleSpec;
    final count = _isTailscale ? 5 : 4;
    var initial = widget.initialTab.clamp(0, 3);
    if (_isTailscale && initial == NodeSettingsScreen.diagnosticsTabIndex) {
      initial = 4;
    }
    _tabs = TabController(length: count, vsync: this, initialIndex: initial);
    unawaited(_load());
  }

  @override
  void dispose() {
    _tagCtrl.dispose();
    _jsonCtrl.dispose();
    _sourceCtrl.dispose();
    _tabs.dispose();
    super.dispose();
  }


  String get _containerRaw {
    final member = _member;
    if (member != null) return member.raw;
    final list = widget.entry.list;
    return list is UserServer ? list.rawBody : '';
  }


  FolderMember? get _member {
    final mi = widget.memberIndex;
    if (mi == null) return null;
    final list = widget.entry.list;
    if (list is! FolderServers) return null;
    if (mi < 0 || mi >= list.members.length) return null;
    return list.members[mi];
  }

  Future<void> _load() async {


    final NodeSpec node;
    final member = _member;
    if (member != null) {
      final n = member.node;
      if (n == null) return;
      node = n;
    } else {
      final nodes = widget.entry.list.nodes;
      if (nodes.isEmpty) return;
      node = nodes.first;
    }

    _node = node;
    final emittedTag =
        TagResolver.displayTag(widget.entry.list.tagPrefix, node.tag);
    _notifications = warningsForConfigTag(
      emittedTag,
      widget.subController.entries,
      emittedTagMap: widget.subController.lastEmittedTagMap,
      buildWarningsByTag: widget.subController.lastBuildWarningsByTag,
    );


    _isAwg = node is WireguardSpec && node.awg != null;

    _originalTag = node.tag;


    _scheme = _isAwg ? 'AmneziaWG (wireguard)' : node.protocol;


    _serverInfo = node is TailscaleSpec
        ? getLocalText.s("No address (Tailscale)")
        : node.isAddressless
            ? getLocalText.s("No address")
            : '${node.server}:${node.port}';





    final raw = _containerRaw;
    _sourceCtrl.text = raw;
    _originKind = originKindOf(raw);
    _jsonCtrl.text = const JsonEncoder.withIndent('  ').convert(
        sourceIsSingbox(raw) && node.rawSource.trimLeft().startsWith('{')
            ? jsonDecode(node.rawSource)
            : node.emit(TemplateVars.empty).map);
    _tagCtrl.text = _originalTag;





    _detour = member != null ? member.detour : widget.entry.overrideDetour;



    _directions = await SettingsStorage.getDirections();


    try {
      final template = await TemplateLoader.load();
      _skipPresetsVisible = skipPresetsToggleVisible(
        list: widget.entry.list,
        isMember: member != null,
        nodeType: node.protocol,
        presets: template.selectableRules,
      );
    } catch (_) {
      _skipPresetsVisible = false;
    }




    if (mounted) setState(() {});
  }


  Future<void> _pickDetour() async {
    final list = widget.entry.list;
    final member = _member;

    _directions = await SettingsStorage.getDirections();
    if (!mounted) return;
    final target = await showDetourTargetPicker(
      context,
      controller: widget.subController,
      directions: _directions,
      currentFolder:
          (member != null && list is FolderServers) ? list : null,
      selfBareTag: member?.node?.tag ?? '',
      selfDisplayTag: member == null
          ? TagResolver.displayTag(list.tagPrefix, _originalTag)
          : '',
    );
    if (target == null || !mounted) return;
    setState(() => _detour = target.link);
    await _persistDetour(target.link);
  }




  String _detourDisplay(NodeLink stored) {
    final list = widget.entry.list;
    return detourLinkDisplay(
      stored,
      directions: _directions,
      controller: widget.subController,
      folder: (widget.memberIndex != null && list is FolderServers)
          ? list
          : null,
    );
  }



  String _detourPath() {
    final list = widget.entry.list;
    return detourPathHops(
      _detour,
      controller: widget.subController,
      directions: _directions,
      folder: (widget.memberIndex != null && list is FolderServers)
          ? list
          : null,
    ).join(' → ');
  }



  Future<void> _persistDetour(NodeLink value) async {
    final mi = widget.memberIndex;
    if (mi != null) {
      final err =
          await widget.subController.setMemberDetour(widget.index, mi, value);
      if (err != null && mounted) {

        setState(() => _detour = _member?.detour ?? NodeLink.none);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err.render())));
      }
      return;
    }
    widget.entry.overrideDetour = value;
    await widget.subController.persistSources();
  }


  void _insertEmoji(String emoji) {
    final text = _tagCtrl.text;
    final sel = _tagCtrl.selection;
    final start =
        (sel.start >= 0 && sel.start <= text.length) ? sel.start : text.length;
    final end = (sel.end >= 0 && sel.end <= text.length) ? sel.end : start;
    const space = ' ';
    final insert = '$emoji$space';
    final newText = text.replaceRange(start, end, insert);
    _tagCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
    setState(() {});
  }





  Future<void> _saveSource() async {
    final text = _sourceCtrl.text.trim();
    if (text.isEmpty) {
      _snack(getLocalText.s("Source is empty"));
      return;
    }
    final String toStore;
    var droppedExtras = false;
    var commentsRemoved = false;
    if (text.startsWith('{') || text.startsWith('[')) {


      final prep = prepareNodeDocumentForSave(text, _tagCtrl.text);
      if (prep is NodeDocumentRejected) {
        _snack(prep.message);
        return;
      }
      final ready = prep as NodeDocumentReady;
      toStore = ready.text;
      droppedExtras = ready.droppedExtras;
      commentsRemoved = ready.commentsRemoved;
      final payload = checkPayloadFor(toStore);
      if (payload != null) {
        final check = await BoxVpnClient.I.checkConfig(payload);
        if (!mounted) return;


        if (check != null && !check.ok) {
          _snack(getLocalText.s("The core rejected the node: %s", check.error));
          return;
        }
      }
    } else if (!text.contains('\n') && text.contains('://')) {
      toStore = SubscriptionController.rawWithName(text, _tagCtrl.text.trim());
    } else {

      await _store(text,
          nameHint: _tagCtrl.text.trim(),
          savedMessage: () => getLocalText.s("Saved"));
      return;
    }
    await _store(toStore,
        savedMessage: () => droppedExtras
            ? getLocalText.s(
                "Only the node is saved. The rest of the input is not kept.")
            : commentsRemoved
                ? getLocalText.s("Comments were removed.")
                : getLocalText.s("Saved"));
  }




  Future<void> _saveExitNode(String? value) async {
    final raw = _containerRaw.trim();
    final base = raw.startsWith('{') ? raw : _jsonCtrl.text;
    final String text;
    try {
      text = withExitNode(base, value);
    } on FormatException catch (e) {
      _snack(getLocalText.s("Invalid JSON: %s", e.message));
      return;
    }
    _sourceCtrl.text = text;
    await _saveSource();
  }



  Future<void> _store(String raw,
      {String? nameHint, required String Function() savedMessage}) async {
    try {
      final mi = widget.memberIndex;
      if (mi != null) {

        final err = await widget.subController
            .updateMemberAt(widget.index, mi, raw, nameHint: nameHint);
        if (!mounted) return;
        if (err != null) {
          _snack(err.render());
          return;
        }
      } else {
        await widget.subController
            .updateConnectionAt(widget.index, [raw], nameHint: nameHint);
        if (!mounted) return;
      }


      await _load();
      if (!mounted) return;
      _snack(savedMessage());
    } catch (e) {
      if (mounted) {
        _snack(getLocalText.s("Invalid JSON: %s", formatUserError(e).render()));
      }
    }
  }





  Future<void> _editJson() async {
    if (_originKind == 'json') {
      _tabs.animateTo(_kSourceTab);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(getLocalText.s("Edit JSON?")),
        content: Text(getLocalText.s(
            "The source will be replaced by this JSON and the node will go to the core as is. The app stops checking such a node: only the core validates it on save, and a mistake can leave it unable to connect. There is no way back to a link. Edit the source instead when you can.")),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(getLocalText.s("Cancel")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(getLocalText.s("Continue")),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _store(_jsonCtrl.text,
        savedMessage: () => getLocalText.s("Source replaced with JSON"));
    if (!mounted) return;
    _tabs.animateTo(_kSourceTab);
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
        appBar: AppBar(
          title: Text(_tagCtrl.text.isNotEmpty
              ? _tagCtrl.text
              : getLocalText.s("Node Settings")),
          actions: [
            IconButton(
              tooltip: getLocalText.s("Save"),
              icon: const Icon(Icons.save),
              onPressed: () => unawaited(_saveSource()),
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: getLocalText.s("Settings")),
              Tab(text: getLocalText.s("Source")),

              const Tab(text: 'JSON'),
              if (_isTailscale) Tab(text: getLocalText.s("Network")),
              NodeDiagnosticsTabLabel(warnings: _notifications),
            ],
          ),
        ),
        body: _originalTag.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabs,
                children: [
                  _buildSettingsTab(theme),
                  _buildSourceTab(theme),
                  _buildJsonTab(theme),
                  if (_isTailscale)
                    TailscaleNetworkTab(
                      liveTag: TagResolver.displayTag(
                          widget.entry.list.tagPrefix, _originalTag),
                      body: _node is TailscaleSpec
                          ? (_node as TailscaleSpec).body
                          : const {},
                      onSaveExitNode: _saveExitNode,
                    ),

                  NodeDiagnosticsTab(
                    node: _node,
                    liveTag: TagResolver.displayTag(
                        widget.entry.list.tagPrefix, _originalTag),
                    warnings: _notifications,
                    scrollToNotifications: widget.initialTab ==
                        NodeSettingsScreen.diagnosticsTabIndex,
                  ),
                ],
              ),
    );
  }

  Widget _buildSettingsTab(ThemeData theme) {
    return ListView(
      padding:
          EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 24),
      children: [
        _sectionHeader(
            getLocalText.s("Info"), getLocalText.s("Protocol and server details"), theme),




        ListTile(
          leading: const Icon(Icons.security, size: 20),
          title: Text(getLocalText.s("Protocol")),

          subtitle: Text(_scheme, style: theme.textTheme.bodyMedium),
        ),
        ListTile(
          leading: const Icon(Icons.dns, size: 20),
          title: Text(getLocalText.s("Server")),
          subtitle: Text(_serverInfo, style: theme.textTheme.bodyMedium),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: _tagCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: getLocalText.s("Tag"),
              hintText: getLocalText.s("Display name in node list"),
              isDense: true,
              prefixIcon: const Icon(Icons.label_outline, size: 18),

              suffixIcon: EmojiPickerButton(onPick: _insertEmoji),
            ),
          ),
        ),


        if (_member?.node?.isGroup != true) ...[
        const SizedBox(height: 16),
        _sectionHeader(
            getLocalText.s("Detour"), getLocalText.s("Route through another server first"), theme),
        ListTile(
          leading: const Icon(Icons.alt_route, size: 20),
          title: Text(getLocalText.s("Detour server")),

          subtitle: Text(_detour.isEmpty
              ? getLocalText.s("None (direct)")
              : _detourDisplay(_detour)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => unawaited(_pickDetour()),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(


            _detour.isEmpty
                ? getLocalText.s("Traffic goes directly to this server.")
                : getLocalText.s("Phone → %1\$s → %2\$s → Internet", _detourPath(), _originalTag),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        ],
        const SizedBox(height: 16),
        ..._buildSkipPresetsBlock(theme),
      ],
    );
  }



  bool get _skipPresets {
    final member = _member;
    if (member != null) return member.skipPresets;
    final list = widget.entry.list;
    return list is UserServer && list.skipPresets;
  }



  List<Widget> _buildSkipPresetsBlock(ThemeData theme) {
    if (!_skipPresetsVisible) return const [];
    return [
      SwitchListTile(
        key: const ValueKey('node-skip-presets'),
        secondary: const Icon(Icons.rule_folder_outlined, size: 20),
        title: Text(getLocalText.s("Skip presets")),
        subtitle: Text(getLocalText
            .s("Presets will not add routing or DNS rules for this node.")),
        value: _skipPresets,
        onChanged: (v) => unawaited(_setSkipPresets(v)),
      ),
      const SizedBox(height: 16),
    ];
  }

  Future<void> _setSkipPresets(bool value) async {
    final err = await widget.subController
        .setSkipPresets(widget.index, widget.memberIndex, value);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err.render())));
    }
    setState(() {});
  }


  Widget _buildSourceTab(ThemeData theme) {
    final kindNote = switch (_originKind) {
      'json' => getLocalText.s(
          "sing-box JSON: sent to the core as is. The core checks it on save."),
      'wg_ini' => getLocalText.s(
          "WireGuard config: saved as is. The tag is stored separately."),
      _ => getLocalText.s("Link: the tag goes into its fragment on save."),
    };
    return ListView(
      padding:
          EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 24),
      children: [
        _sectionHeader(getLocalText.s("Source"),
            getLocalText.s("The node's original text. Save writes it as is."), theme),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            kindNote,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _sourceCtrl,
            maxLines: null,
            minLines: 12,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.all(12),
            ),
          ),
        ),
      ],
    );
  }



  Widget _buildJsonTab(ThemeData theme) {
    return ListView(
      padding:
          EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 24),
      children: [
        _sectionHeader(getLocalText.s("Outbound JSON"),
            getLocalText.s("What the core receives. Read-only: edit the source instead."), theme),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Stack(
            children: [
              LxJsonView(text: _jsonCtrl.text, height: 420),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: getLocalText.s("Copy JSON"),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _jsonCtrl.text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(getLocalText.s("JSON copied"))),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(getLocalText.s("Edit JSON")),
              onPressed: () => unawaited(_editJson()),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title, String description, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Divider(),
        ],
      ),
    );
  }
}
