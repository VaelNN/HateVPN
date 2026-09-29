import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/subscription_controller.dart';
import '../models/direction.dart';
import '../models/import_rule.dart';
import '../models/node_link.dart';
import '../models/node_spec.dart';
import '../models/server_list.dart';
import '../models/ui_msg.dart';
import '../services/error_humanize.dart';
import '../services/node_hash.dart';
import '../services/parser/body_decoder.dart';
import '../services/probe/probe_controller.dart';
import '../services/probe/probe_runner.dart';
import '../services/settings_storage.dart';
import '../services/subscription/sources.dart';
import '../services/subscription/subscription_identity.dart';
import '../widgets/detour_target_picker.dart';
import '../services/url_launcher.dart';
import 'probe_gate_mixin.dart';
import 'subscriptions_screen/entry_context_menu.dart' show showEditSourceDialog;
import 'subscription_detail_screen/detour_mode.dart';
import 'subscription_detail_screen/subscription_detail_format.dart';
import 'subscription_detail_screen/tag_prefix_cascade.dart';
import 'subscription_detail_screen/widgets/subscription_meta.dart';
import 'subscription_detail_screen/widgets/subscription_filters_tab.dart';
import 'subscription_detail_screen/widgets/subscription_node_list.dart';
import 'subscription_detail_screen/widgets/subscription_settings_tab.dart';
import 'subscription_detail_screen/widgets/subscription_source_tab.dart';
import '../services/l10n/locale_controller.dart';

class SubscriptionDetailScreen extends StatefulWidget {
  const SubscriptionDetailScreen({
    super.key,
    required this.entry,
    required this.controller,
  });

  final SubscriptionEntry entry;
  final SubscriptionController controller;

  @override
  State<SubscriptionDetailScreen> createState() =>
      _SubscriptionDetailScreenState();
}

class _SubscriptionDetailScreenState extends State<SubscriptionDetailScreen>
    with SingleTickerProviderStateMixin, ProbeGateMixin {
  late final TabController _tabCtrl;
  List<NodeSpec>? _nodes;
  bool _loading = true;
  UiMsg? _error;
  bool _editing = false;
  late TextEditingController _nameCtrl;
  String _rawSource = '';
  Map<String, String> _rawHeaders = const {};
  bool _sourceLoaded = false;
  bool _sourceLoading = false;
  UiMsg? _sourceError;
  bool _showAllHeaders = false;











  bool? _decodeSource;



  List<Direction> _directions = const [];




  late String _committedTagPrefix;





  bool _autoReloadOnChange = false;




  Map<NodeSpec, String> _identityCache = Map.identity();
  Set<NodeSpec> _togglableNodes = Set.identity();
  Set<NodeSpec> _disabledNodes = Set.identity();




  Set<NodeSpec> _chainHops = Set.identity();




  final Map<String, ProbeResult> _probe = {};
  Timer? _probeFlushTimer;
  bool _testing = false;
  ProbeRunner? _probeRunner;
  ProbeThresholds _probeThresholds = ProbeThresholds.defaults;


  List<NodeSpec?>? _probeKeysFor;
  List<String> _probeKeysCache = const [];
  List<String> _nodeProbeKeys(List<NodeSpec?> nodes) {
    if (!identical(_probeKeysFor, nodes)) {
      _probeKeysFor = nodes;
      _probeKeysCache = ProbeController.probeKeysForNodes(nodes);
    }
    return _probeKeysCache;
  }





  List<NodeSpec>? _hashedNodesList;






  void _rebuildRowsFromEntry() {
    final nodes = widget.entry.list.nodes;
    if (!identical(nodes, _hashedNodesList)) {
      _identityCache = sourceNodeIdentities(nodes);
      _hashedNodesList = nodes;
    }



    final expanded = <NodeSpec>[];
    final hops = Set<NodeSpec>.identity();
    for (final node in nodes) {
      expanded.add(node);
      for (var hop = node.chained; hop != null; hop = hop.chained) {
        expanded.add(hop);
        hops.add(hop);
      }
    }
    _nodes = expanded;
    _chainHops = hops;
    _togglableNodes = widget.entry.list is SubscriptionServers
        ? (Set<NodeSpec>.identity()..addAll(nodes))
        : Set<NodeSpec>.identity();
    _recomputeDisabled();
  }




  void _recomputeDisabled() {
    final list = widget.entry.list;
    final next = Set<NodeSpec>.identity();
    if (list is SubscriptionServers && list.disabledHashes.isNotEmpty) {
      for (final n in list.nodes) {
        final identity = _identityCache[n];
        if (identity != null && list.disabledHashes.containsKey(identity)) {
          next.add(n);



          for (var hop = n.chained; hop != null; hop = hop.chained) {
            next.add(hop);
          }
        }
      }
    }
    _disabledNodes = next;
  }

  void _onEntryChanged() {
    if (!mounted) return;
    setState(_rebuildRowsFromEntry);
  }

  Future<void> _toggleNode(NodeSpec node) async {

    final idx = widget.controller.entries.indexOf(widget.entry);
    if (idx < 0) return;
    await widget.controller.toggleSubscriptionNode(idx, node);

  }


  Future<void> _toggleAllNodes(bool enable) async {
    final idx = widget.controller.entries.indexOf(widget.entry);
    if (idx < 0) return;
    await widget.controller.setAllSubscriptionNodes(idx, enabled: enable);
  }




  static const _importantHeaders = {
    'profile-title',
    'profile-update-interval',
    'profile-web-page-url',
    'support-url',
    'subscription-userinfo',
    'content-type',
  };

  @override
  void initState() {
    super.initState();


    _tabCtrl = TabController(length: 4, vsync: this);
    _nameCtrl = TextEditingController(text: widget.entry.name);
    _committedTagPrefix = widget.entry.tagPrefix;


    widget.entry.addListener(_onEntryChanged);
    unawaited(_loadNodes());
    unawaited(_loadDirections());
    unawaited(_loadProbeThresholds());
    unawaited(_loadAutoReloadOnChange());

    _tabCtrl.addListener(() {
      if (_tabCtrl.index == 2 && !_sourceLoaded && !_sourceLoading) {
        unawaited(_fetchSourceLive());
      }
    });
  }

  @override
  void dispose() {
    widget.entry.removeListener(_onEntryChanged);
    _probeFlushTimer?.cancel();
    _probeFlushTimer = null;
    _tabCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }



  Future<void> _loadProbeThresholds() async {
    final t = await ProbeController.loadThresholds();
    if (mounted) setState(() => _probeThresholds = t);
  }



  void _scheduleProbeFlush() {
    if (_probeFlushTimer != null) return;
    _probeFlushTimer = Timer(const Duration(milliseconds: 120), () {
      _probeFlushTimer = null;
      if (mounted) setState(() {});
    });
  }

  Future<void> _toggleProbeTest() async {
    if (_testing) {
      _probeRunner?.cancel();
      _probeFlushTimer?.cancel();
      _probeFlushTimer = null;
      setState(() => _testing = false);
      return;
    }
    if (widget.entry.list.nodes.isEmpty) return;

    if (await ensureVpnStoppedForProbe()) {
      await _runProbe();
    }
  }

  Future<void> _runProbe() async {




    final nodes = ProbeController.probeNodesOf(widget.entry.list);
    if (nodes.isEmpty) return;
    final (:url, :timeoutMs) = await ProbeController.resolvePingOptions();
    if (!mounted) return;
    final probeKeys = _nodeProbeKeys(nodes);
    setState(() {
      _testing = true;
      _probe
        ..clear()
        ..addEntries([
          for (final k in probeKeys)
            MapEntry(k, const ProbeResult(ProbeStatus.pending)),
        ]);
    });
    final runner = ProbeRunner();
    _probeRunner = runner;
    final err = await runner.run(
      nodes,
      url: url,
      timeoutMs: timeoutMs,
      onResult: (i, r) {
        if (!mounted) return;
        if (i < probeKeys.length) _probe[probeKeys[i]] = r;
        _scheduleProbeFlush();
      },
    );
    _probeFlushTimer?.cancel();
    _probeFlushTimer = null;
    if (!mounted) return;
    setState(() => _testing = false);

    if (err == kProbeVpnRunning) {
      if (mounted && await onProbeVpnRaceGate()) await _runProbe();
      return;
    }
    if (err.isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    }
  }


  ({int ok, int dead, int broken}) _probeSummary() {
    var ok = 0, dead = 0, broken = 0;
    for (final r in _probe.values) {
      switch (r.status) {
        case ProbeStatus.ok:
          ok++;
        case ProbeStatus.failed:
          dead++;
        case ProbeStatus.broken:
        case ProbeStatus.invalid:
          broken++;
        case ProbeStatus.pending:
        case ProbeStatus.group:
          break;
      }
    }
    return (ok: ok, dead: dead, broken: broken);
  }





  Map<int, ProbeResult> _probeByIndex() {
    final nodes = ProbeController.probeNodesOf(widget.entry.list);
    final keys = _nodeProbeKeys(nodes);
    return {
      for (var i = 0; i < keys.length; i++) i: ?_probe[keys[i]],
    };
  }

  List<NodeSpec> _nodesAtIndexes(Set<int> indexes) {
    final nodes = ProbeController.probeNodesOf(widget.entry.list);
    return [
      for (final i in indexes)
        if (i < nodes.length && nodes[i] != null) nodes[i]!,
    ];
  }





  bool get _hasProbeVerdict =>
      _probe.values.any((r) => r.status != ProbeStatus.pending &&
          r.status != ProbeStatus.group);




  bool get _hasEnableRules {
    final list = widget.entry.list;
    return list is SubscriptionServers &&
        list.activeImportRules
            .any((r) => r.action == ImportRuleAction.enable);
  }

  Future<void> _showProbeError(String err) async {
    if (err.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }




  Future<void> _disableUnreachable() async {
    final dead = ProbeController.unreachableIndexes(_probeByIndex());
    if (dead.isEmpty) {
      await _showProbeError(
          getLocalText.s("No unreachable or broken servers in last test"));
      return;
    }
    if (_hasEnableRules) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(getLocalText.s("Disable unreachable")),
          content: Text([
            getLocalText.plural(
                "Disable %d servers that failed the test?", dead.length),
            getLocalText.s(
                "Enable rules in Filters will turn these nodes back on at the next update."),
          ].join('\n\n')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(getLocalText.s("Cancel"))),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(getLocalText.s("Disable")),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final idx = widget.controller.entries.indexOf(widget.entry);
    if (idx < 0) return;
    await widget.controller
        .setSubscriptionNodesEnabled(idx, _nodesAtIndexes(dead), enabled: false);

  }


  Future<void> _disableSlowerThan() async {
    final ctl = TextEditingController(text: '${_probeThresholds.orangeMs}');
    final ms = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(getLocalText.s("Disable slow servers")),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: ctl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: getLocalText.s("Slower than, ms"),
                border: const OutlineInputBorder(),
              ),
            ),
            if (_hasEnableRules) ...[
              const SizedBox(height: 12),
              Text(
                getLocalText.s(
                    "Enable rules in Filters will turn these nodes back on at the next update."),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(getLocalText.s("Cancel"))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctl.text.trim())),
            child: Text(getLocalText.s("Disable")),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (ms == null || !mounted) return;
    final slow = ProbeController.slowerThan(_probeByIndex(), ms);
    if (slow.isEmpty) {
      await _showProbeError(
          getLocalText.s("No tested servers slower than %d ms", ms));
      return;
    }
    final idx = widget.controller.entries.indexOf(widget.entry);
    if (idx < 0) return;
    await widget.controller
        .setSubscriptionNodesEnabled(idx, _nodesAtIndexes(slow), enabled: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(getLocalText.plural(
              "Disabled %1\$d servers > %2\$d ms", slow.length, ms))),
    );
  }



  Map<NodeSpec, ProbeResult> _probeByNode() {
    if (_probe.isEmpty) return const {};
    final nodes = ProbeController.probeNodesOf(widget.entry.list);
    final keys = _nodeProbeKeys(nodes);
    return {
      for (var i = 0; i < keys.length; i++)
        if (nodes[i] != null && _probe[keys[i]] != null)
          nodes[i]!: _probe[keys[i]]!,
    };
  }



  Widget _buildProbeBar(ThemeData theme) {
    final muted = theme.colorScheme.onSurfaceVariant;
    final s = _probeSummary();
    final String? info;
    if (_testing) {
      info = getLocalText.s("Testing… %d done", s.ok + s.dead);
    } else if (_probe.isNotEmpty) {
      info = [
        getLocalText.s("%d ok", s.ok),
        getLocalText.plural("%d err", s.dead),
        if (s.broken > 0) getLocalText.plural("%d broken", s.broken),
      ].join(' · ');
    } else {
      info = null;
    }
    final hasNodes = widget.entry.list.nodes.isNotEmpty;


    final canToggleAll =
        widget.entry.list is SubscriptionServers && hasNodes;




    final allOff = hasNodes && _disabledNodes.length >= _togglableNodes.length;
    return Padding(


      padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
      child: Row(
        children: [



          if (canToggleAll)
            SizedBox(
              width: 40,
              child: Switch(
                value: !allOff,
                onChanged: (v) => unawaited(_toggleAllNodes(v)),
              ),
            )
          else
            const SizedBox(width: 12),
          Expanded(
            child: info != null
                ? Text(info, style: TextStyle(fontSize: 12, color: muted))
                : const SizedBox.shrink(),
          ),
          GestureDetector(
            onTap: hasNodes ? () => unawaited(_toggleProbeTest()) : null,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                _testing ? Icons.stop_circle_outlined : Icons.speed,
                size: 22,
                color: hasNodes ? null : theme.disabledColor,
              ),
            ),
          ),




          PopupMenuButton<String>(
            tooltip: getLocalText.s("Test actions"),
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (v) {
              if (v == 'disable_slow') unawaited(_disableSlowerThan());
              if (v == 'disable_dead') unawaited(_disableUnreachable());
            },
            itemBuilder: (menuCtx) {
              final ready = _hasProbeVerdict;
              return [
                PopupMenuItem(
                    value: 'disable_slow',
                    enabled: ready,
                    child: Text(getLocalText.s("Disable slower than…"))),
                PopupMenuItem(
                    value: 'disable_dead',
                    enabled: ready,
                    child: Text(getLocalText.s("Disable unreachable"))),
              ];
            },
          ),
        ],
      ),
    );
  }

  List<MapEntry<String, String>> _filteredHeaders({required bool important}) {
    final entries = _rawHeaders.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries
        .where((e) => _importantHeaders.contains(e.key.toLowerCase()) == important)
        .toList();
  }

  Future<void> _fetchSourceLive() async {
    if (widget.entry.url.isEmpty) return;
    setState(() {
      _sourceLoading = true;
      _sourceError = null;
    });
    try {

      final r = await fetchRaw(
          UrlSource(widget.entry.url, identity: widget.entry.identity));
      if (!mounted) return;
      setState(() {
        _rawSource = r.body;
        _rawHeaders = r.headers;
        _sourceLoaded = true;
        _sourceLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sourceError = humanizeError(e);
        _sourceLoading = false;
      });
    }
  }

  Future<void> _loadNodes({bool cacheOnly = true}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!cacheOnly) {

        final idx = widget.controller.entries.indexOf(widget.entry);
        if (idx >= 0) await widget.controller.updateAt(idx);
      }


      _rebuildRowsFromEntry();


      if (widget.entry.connections.isNotEmpty) {
        _rawSource = widget.entry.connections.join('\n');
        _sourceLoaded = true;
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _error = humanizeError(e); _loading = false; });
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(getLocalText.s("Delete subscription?")),
        content: Text(getLocalText.s("Remove \"%s\"?", widget.entry.displayName)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(getLocalText.s("Cancel"))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
            child: Text(getLocalText.s("Delete")),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;


    final idx = widget.controller.entries.indexOf(widget.entry);
    if (idx < 0) {
      if (mounted) Navigator.pop(context);
      return;
    }
    await widget.controller.removeAt(idx);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _openUrl(String url) async {
    final opened = await UrlLauncher.open(url);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(getLocalText.s("Copied: %s", url))),
      );
    }
  }

  void _toggleEdit() {
    if (_editing) {

      final name = _nameCtrl.text.trim();

      final idx = widget.controller.entries.indexOf(widget.entry);
      if (idx >= 0) unawaited(widget.controller.renameAt(idx, name));
    }
    setState(() => _editing = !_editing);
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: _editing
            ? TextField(
                controller: _nameCtrl,
                autofocus: true,
                style: theme.textTheme.titleLarge,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: getLocalText.s("Display name"),
                ),
                onSubmitted: (_) => _toggleEdit(),
              )
            : Text(
                entry.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        actions: [
          IconButton(
            tooltip: _editing ? getLocalText.s("Save") : getLocalText.s("Rename"),
            icon: Icon(_editing ? Icons.check : Icons.edit_outlined),
            onPressed: _toggleEdit,
          ),
          IconButton(
            tooltip: getLocalText.s("Refresh"),
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : () => _loadNodes(cacheOnly: false),
          ),
          IconButton(
            tooltip: getLocalText.s("Delete"),
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabs: [
            Tab(text: getLocalText.s("Nodes")),
            Tab(text: getLocalText.s("Settings")),
            Tab(text: getLocalText.s("Source")),
            Tab(text: getLocalText.s("Filters")),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [

          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loading) const LinearProgressIndicator(),
              SubscriptionMeta(
                entry: entry,
                onOpenUrl: _openUrl,
                offCount: _disabledNodes.length,
              ),
              _buildProbeBar(theme),
              const Divider(height: 1),
              Expanded(
                child: SubscriptionNodeList(
                  nodes: _nodes,
                  loading: _loading,
                  error: _error,




                  togglableNodes: _togglableNodes,
                  disabledNodes: _disabledNodes,
                  chainHops: _chainHops,
                  onToggleNode:
                      entry.list is SubscriptionServers ? _toggleNode : null,
                  probe: _probeByNode(),
                  probeThresholds: _probeThresholds,


                  tagPrefix: entry.tagPrefix,
                ),
              ),
            ],
          ),

          _buildSettingsTab(theme),

          _buildSourceTab(theme),

          SubscriptionFiltersTab(
            entry: widget.entry,
            controller: widget.controller,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab(ThemeData theme) {
    final hasDetour = (_nodes ?? const []).any((n) => n.chained != null);
    return SubscriptionSettingsTab(
      entry: widget.entry,
      directions: _directions,

      detourPathHopsOf: (stored) => detourPathHops(stored,
          controller: widget.controller, directions: _directions),
      hasDetour: hasDetour,
      detourMode: _detourMode,
      onTagPrefixChanged: (val) {
        widget.entry.tagPrefix = val.trim();
        unawaited(widget.controller.persistSources());
      },


      otherSources: [for (final e in widget.controller.entries) e.list],
      onReplaceChanged: (r) async {
        setState(() => widget.entry.replace = r);
        await widget.controller.persistSources();
      },


      onTagPrefixCommitted: (_) => unawaited(_commitTagPrefix()),
      onSetDetourMode: _setDetourMode,
      onRegisterDetourServersChanged: (val) {
        setState(() => widget.entry.registerDetourServers = val);
        unawaited(widget.controller.persistSources());
      },
      onRegisterDetourInAutoChanged: (val) {
        setState(() => widget.entry.registerDetourInAuto = val);
        unawaited(widget.controller.persistSources());
      },
      onShowOverrideDetourPicker: () => _showOverrideDetourPicker(),
      onReplaceDetourChainChanged: (val) {
        setState(() => widget.entry.replaceDetourChain = val);
        unawaited(widget.controller.persistSources());
      },
      onCopyUrl: () async {
        final list = widget.entry.list as SubscriptionServers;
        await Clipboard.setData(ClipboardData(text: list.url));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(getLocalText.s("URL copied")),
              duration: const Duration(seconds: 1)),
        );
      },
      onShowIntervalPicker: _showIntervalPicker,
      onShowOnUpdateActionPicker: _showOnUpdateActionPicker,
      autoReloadOnChange: _autoReloadOnChange,
      onRefreshNow: _refreshNow,
      onEditSource: _editSource,

      onToggleCustomIdentity: (on) {
        setState(() {
          if (on) {
            widget.entry.enableCustomIdentity();
          } else {
            widget.entry.disableCustomIdentity();
          }
        });
        unawaited(widget.controller.persistSources());
      },
      onEditIdentityUserAgent: () => unawaited(_editIdentityUserAgent()),
      onIdentitySendHwidChanged: (v) {
        final id = widget.entry.identity;
        if (id == null) return;



        final next = v && id.hwid.isEmpty
            ? id.copyWith(sendHwid: v, hwid: generateUuidV4())
            : id.copyWith(sendHwid: v);
        setState(() => widget.entry.updateIdentity(next));
        unawaited(widget.controller.persistSources());
      },
      onEditIdentityHwid: () => unawaited(_editIdentityField(
            title: 'HWID',
            initial: widget.entry.identity?.hwid ?? '',
            monospace: true,
            apply: (id, v) => id.copyWith(hwid: v.trim()),
          )),
      onRegenerateIdentityHwid: () {
        final id = widget.entry.identity;
        if (id == null) return;
        setState(() =>
            widget.entry.updateIdentity(id.copyWith(hwid: generateUuidV4())));
        unawaited(widget.controller.persistSources());
      },
      onEditIdentityDeviceOs: () => unawaited(_editIdentityField(
            title: 'x-device-os',
            initial: widget.entry.identity?.deviceOs ?? '',
            apply: (id, v) => id.copyWith(deviceOs: v.trim()),
          )),
      onEditIdentityVerOs: () => unawaited(_editIdentityField(
            title: 'x-ver-os',
            initial: widget.entry.identity?.verOs ?? '',
            apply: (id, v) => id.copyWith(verOs: v.trim()),
          )),
      onEditIdentityDeviceModel: () => unawaited(_editIdentityField(
            title: 'x-device-model',
            initial: widget.entry.identity?.deviceModel ?? '',
            apply: (id, v) => id.copyWith(deviceModel: v.trim()),
          )),
    );
  }



  Future<void> _editIdentityUserAgent() => _editIdentityField(


        title: getLocalText.s('Custom User-Agent'),
        initial: widget.entry.identity?.userAgent ?? '',
        apply: (id, v) => id.copyWith(userAgent: v.trim()),
      );




  Future<void> _editIdentityField({
    required String title,
    required String initial,
    required SubscriptionIdentityOverride Function(
            SubscriptionIdentityOverride id, String value)
        apply,
    bool monospace = false,
  }) async {
    final ctl = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLines: null,
          style: monospace
              ? const TextStyle(fontFamily: 'monospace', fontSize: 13)
              : null,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(getLocalText.s("Cancel")),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctl.text),
            child: Text(getLocalText.s("Save")),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (result == null || !mounted) return;
    final id = widget.entry.identity;
    if (id == null) return;
    setState(() => widget.entry.updateIdentity(apply(id, result)));
    await widget.controller.persistSources();
  }



  Future<void> _editSource() async {
    final idx = widget.controller.entries.indexOf(widget.entry);
    if (idx < 0) return;
    await showEditSourceDialog(context, idx, widget.entry, widget.controller);
    if (mounted) setState(() {});
  }

  Future<void> _showIntervalPicker() async {
    final list = widget.entry.list as SubscriptionServers;


    final presets = <int>[-1, 0, 1, 3, 6, 12, 24, 48, 72, 168];
    final chosen = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(getLocalText.s("Update interval")),
        children: [
          for (final h in presets)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, h),
              child: Row(
                children: [
                  if (h == list.updateIntervalHours)
                    const Icon(Icons.check, size: 18)
                  else
                    const SizedBox(width: 18),
                  const SizedBox(width: 8),
                  Text(switch (h) {
                    < 0 => getLocalText.s("Don't auto-update"),
                    0 => getLocalText.s("Never (respect server)"),
                    _ => getLocalText.s("%1\$dh (%2\$s)", h, intervalHuman(h)),
                  }),
                ],
              ),
            ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      widget.entry.updateIntervalHours = chosen;
    });
    await widget.controller.persistSources();
  }




  Future<void> _showOnUpdateActionPicker() async {
    final list = widget.entry.list as SubscriptionServers;
    final chosen = await showDialog<SubscriptionOnUpdateAction>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(getLocalText.s("On update")),
        children: [
          for (final a in SubscriptionOnUpdateAction.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, a),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (a == list.onUpdateAction)
                    const Icon(Icons.check, size: 18)
                  else
                    const SizedBox(width: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(switch (a) {
                          SubscriptionOnUpdateAction.rebuild =>
                            getLocalText.s("Rebuild config"),
                          SubscriptionOnUpdateAction.reload =>
                            getLocalText.s("Rebuild and reload core"),
                          SubscriptionOnUpdateAction.none =>
                            getLocalText.s("Do nothing"),
                        }),
                        Text(
                          switch (a) {
                            SubscriptionOnUpdateAction.rebuild => getLocalText.s(
                                "New nodes go into the config; apply the change yourself"),
                            SubscriptionOnUpdateAction.reload => getLocalText.s(
                                "New nodes apply at once; the connection drops for a few seconds"),
                            SubscriptionOnUpdateAction.none => getLocalText.s(
                                "Nodes update in the list only; the config waits for the next rebuild"),
                          },
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      widget.entry.onUpdateAction = chosen;
    });
    await widget.controller.persistSources();
  }

  Future<void> _refreshNow() async {
    final idx = widget.controller.entries.indexOf(widget.entry);
    if (idx < 0) return;
    await widget.controller.updateAt(idx);
    if (!mounted) return;
    setState(() {});
  }



  Future<void> _commitTagPrefix() async {
    final oldPrefix = _committedTagPrefix;
    final newPrefix = widget.entry.tagPrefix;
    if (oldPrefix == newPrefix) return;
    _committedTagPrefix = newPrefix;


    await widget.controller.relinkServerTagPrefix(widget.entry, oldPrefix);
    if (!mounted) return;

    await _loadDirections();
    if (!mounted) return;
    final outcome = await applyTagPrefixCascade(
      directions: _directions,
      oldPrefix: oldPrefix,
      newPrefix: newPrefix,
      sub: widget.controller,
    );
    if (!mounted || outcome.isEmpty) return;
    await _loadDirections();
    if (!mounted) return;
    showTagPrefixCascadeSnackBar(context, outcome);
  }


  Future<void> _loadDirections() async {
    final directions = await SettingsStorage.getDirections();
    if (!mounted) return;
    setState(() => _directions = directions);
  }



  Future<void> _loadAutoReloadOnChange() async {
    final v = await SettingsStorage.getAutoReloadOnChange();
    if (!mounted || v == _autoReloadOnChange) return;
    setState(() => _autoReloadOnChange = v);
  }

  Future<void> _showOverrideDetourPicker() async {



    await _loadDirections();
    if (!mounted) return;
    final chosen = await showDetourTargetPicker(
      context,
      controller: widget.controller,
      directions: _directions,
    );
    if (chosen == null || !mounted) return;
    setState(() {
      widget.entry.overrideDetour = chosen.link;


      if (chosen.link.isNotEmpty) widget.entry.useDetourServers = true;
    });
    unawaited(widget.controller.persistSources());
  }






  String get _decodedSource {
    if (_rawSource.isEmpty) return '';
    final d = decode(_rawSource);
    return switch (d) {
      UriLines(lines: final l) => l.join('\n'),
      IniConfig(text: final t) => t,
      AmneziaConfig(iniTexts: final ts) => ts.join('\n\n'),
      JsonConfig() => _rawSource,
      DecodeFailure() => _rawSource,
    };
  }



  bool get _sourceIsBase64 =>
      _rawSource.isNotEmpty && _decodedSource.trim() != _rawSource.trim();

  Widget _buildSourceTab(ThemeData theme) {
    final entry = widget.entry;
    final decodable = _sourceIsBase64;


    final showDecoded = decodable && (_decodeSource ?? true);
    return SubscriptionSourceTab(
      hasUrl: entry.url.isNotEmpty,
      sourceLoading: _sourceLoading,
      sourceError: _sourceError,
      rawHeaders: _rawHeaders,
      rawSource: showDecoded ? _decodedSource : _rawSource,
      showAllHeaders: _showAllHeaders,
      importantHeaders: _filteredHeaders(important: true),
      moreHeaders: _filteredHeaders(important: false),
      onRefetch: () => unawaited(_fetchSourceLive()),
      onToggleShowAll: () =>
          setState(() => _showAllHeaders = !_showAllHeaders),
      canDecode: decodable,
      decoded: showDecoded,
      onToggleDecode: (v) => setState(() => _decodeSource = v),
    );
  }




  DetourMode get _detourMode {
    if (!widget.entry.useDetourServers) return DetourMode.none;
    if (widget.entry.overrideDetour.isNotEmpty) return DetourMode.override;
    return DetourMode.use;
  }

  void _setDetourMode(DetourMode mode) {
    setState(() {
      switch (mode) {
        case DetourMode.use:
          widget.entry.useDetourServers = true;
          widget.entry.overrideDetour = NodeLink.none;
        case DetourMode.override:
          widget.entry.useDetourServers = true;


          if (widget.entry.overrideDetour.isEmpty) {
            unawaited(_showOverrideDetourPicker());
          }
        case DetourMode.none:
          widget.entry.useDetourServers = false;
          widget.entry.overrideDetour = NodeLink.none;
      }
    });
    unawaited(widget.controller.persistSources());
  }
}
