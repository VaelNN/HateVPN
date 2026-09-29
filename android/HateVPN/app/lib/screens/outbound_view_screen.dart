import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/home_controller.dart';
import '../services/contract/group_genus.dart';
import '../controllers/subscription_controller.dart';
import '../models/direction.dart';
import '../models/config_node.dart';
import '../models/dependency_graph.dart';
import '../services/probe/chain_layer_probe.dart';
import '../services/runtime_chain.dart';
import '../services/settings_storage.dart';
import '../vpn/cc_channel.dart';
import '../widgets/chain_positions_block.dart';
import '../widgets/lx_code_editor.dart';
import '../widgets/node_diagnostics_tab.dart';
import '../widgets/pool_view_dialog.dart';
import '../widgets/tailscale_network_tab.dart';
import 'home/node_actions.dart' show toggleEndpoint;
import 'node_settings/exit_node_store.dart';
import 'owner_navigation.dart';
import 'subscriptions_screen/entry_warnings.dart';
import '../services/l10n/locale_controller.dart';








class OutboundViewScreen extends StatefulWidget {
  const OutboundViewScreen({
    super.key,
    required this.tag,
    required this.kind,
    required this.json,
    required this.detourCount,
    required this.onCopy,
    required this.config,
    required this.subController,
    required this.homeController,
    this.openDependents = false,
    this.openNetwork = false,
  });




  final bool openNetwork;



  final bool openDependents;

  final String tag;
  final String kind;
  final String json;



  final int detourCount;



  final void Function(String mode) onCopy;


  final ParsedConfig config;


  final SubscriptionController subController;
  final HomeController homeController;

  @override
  State<OutboundViewScreen> createState() => _OutboundViewScreenState();
}

class _OutboundViewScreenState extends State<OutboundViewScreen> {
  late final TextEditingController _jsonCtrl;



  List<Direction> _directions = const [];
  List<RuntimeHop> _hops = const [];




  List<CcPoolSlot>? _pool;



  bool get _isBalancer =>
      _isGroupNode && widget.homeController.isRoundRobinAuto(widget.tag);

  bool get _isGroupNode {
    final t = widget.config[widget.tag]?.type;
    return t != null && GroupGenus.isKnown(t);
  }


  bool get _isManualGroup =>
      widget.config[widget.tag]?.type == GroupGenus.manual;



  String? get _manualSelected {
    if (!_isManualGroup) return null;
    final picked = _pickedMember;
    if (picked != null) return picked;
    final live = widget.homeController.state.groupOf(widget.tag)?.selected;
    if (live != null && live.isNotEmpty) return live;
    final def = widget.config[widget.tag]?.raw['default'];
    return def is String && def.isNotEmpty ? def : null;
  }




  List<String>? get _chainHops =>
      chainHopsFromConfig(widget.config[widget.tag]?.raw);


  bool get _isTailscale => widget.config[widget.tag]?.type == 'tailscale';



  Map<String, dynamic>? _tailscaleBody;

  Map<String, dynamic> get _networkBody =>
      _tailscaleBody ?? widget.config[widget.tag]?.raw ?? const {};




  Future<void> Function(String?)? get _saveExitNode {
    if (exitNodeTargetForTag(widget.tag, widget.subController.entries) ==
        null) {
      return null;
    }
    return _storeExitNode;
  }

  Future<void> _storeExitNode(String? value) async {
    final target =
        exitNodeTargetForTag(widget.tag, widget.subController.entries);
    if (target == null) return;
    final err =
        await storeExitNodeChoice(widget.subController, target, value);
    if (!mounted) return;
    if (err == null) {
      final body = Map<String, dynamic>.of(_networkBody);
      if (value == null || value.isEmpty) {
        body.remove('exit_node');
      } else {
        body['exit_node'] = value;
      }
      setState(() => _tailscaleBody = body);
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err ?? getLocalText.s("Saved"))));
  }



  String? _pickedMember;





  Future<void> _selectMember(String member) async {
    if (member == _manualSelected) return;
    final prev = _pickedMember;
    setState(() => _pickedMember = member);
    final bool ok;
    if (widget.homeController.state.tunnelUp) {
      ok = await widget.homeController.selectInGroup(widget.tag, member);
    } else {
      ok = await widget.subController
          .rememberGroupMember(widget.tag, member, live: false);
    }
    if (!mounted) return;
    if (!ok) {
      setState(() => _pickedMember = prev);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(getLocalText.s("Could not select this server"))));
    }
  }

  @override
  void initState() {
    super.initState();
    _jsonCtrl = TextEditingController(text: widget.json);
    _hops = runtimeChainOf(widget.tag, widget.config, directions: _directions);
    unawaited(_load());
  }

  @override
  void dispose() {
    _jsonCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final directions = await SettingsStorage.getDirections();
    if (!mounted) return;
    setState(() {
      _directions = directions;
      _hops = runtimeChainOf(widget.tag, widget.config, directions: directions);
    });


    if (!_isBalancer) return;
    final pool = await widget.homeController.getPool(widget.tag);
    if (!mounted) return;
    setState(() => _pool = pool);
  }

  void _onHopTap(RuntimeHop hop) => _onTagTap(hop.tag);

  void _onTagTap(String tag) {
    unawaited(openTagOwner(
      context,
      tag,
      subController: widget.subController,
      homeController: widget.homeController,
      directions: _directions,
      onOwnerNotFound: () {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(getLocalText.s("Source not found in your lists"))),
        );
      },
    ));
  }

  @override
  Widget build(BuildContext context) {

    final bothLabel = widget.detourCount > 1
        ? 'Copy server + detours(${widget.detourCount})'
        : 'Copy server + detour';



    final sickDependents =
        widget.homeController.state.sickRoots[widget.tag];
    final dependents = sickDependents ??
        widget.homeController.directDependentsOf(widget.tag);
    final hasDependents = dependents.isNotEmpty;

    final warnings = warningsForConfigTag(
      widget.tag,
      widget.subController.entries,
      emittedTagMap: widget.subController.lastEmittedTagMap,
      buildWarningsByTag: widget.subController.lastBuildWarningsByTag,
    );

    final tailscale = _isTailscale;
    final networkIndex = hasDependents ? 3 : 2;
    return DefaultTabController(


      length: 3 + (hasDependents ? 1 : 0) + (tailscale ? 1 : 0),
      initialIndex: (widget.openNetwork && tailscale)
          ? networkIndex
          : (widget.openDependents && hasDependents)
              ? 2
              : 0,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.kind} · ${widget.tag}',
              overflow: TextOverflow.ellipsis),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: getLocalText.s("Overview")),

              const Tab(text: 'JSON'),
              if (hasDependents) Tab(text: getLocalText.s("Dependents")),
              if (tailscale) Tab(text: getLocalText.s("Network")),
              NodeDiagnosticsTabLabel(warnings: warnings),
            ],
          ),
          actions: [


            if (widget.detourCount > 0)
              PopupMenuButton<String>(
                tooltip: getLocalText.s("Copy"),
                icon: const Icon(Icons.content_copy),
                onSelected: widget.onCopy,
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'server',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.content_copy, size: 20),
                      title: Text(getLocalText.s("Copy server JSON")),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'detour',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.alt_route, size: 20),
                      title: Text(getLocalText.s("Copy detour")),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'both',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.copy_all, size: 20),
                      title: Text(bothLabel),
                    ),
                  ),
                ],
              )
            else
              IconButton(
                tooltip: getLocalText.s("Copy JSON"),
                icon: const Icon(Icons.content_copy),
                onPressed: () => widget.onCopy('server'),
              ),
          ],
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              _buildOverviewTab(context),
              _buildJsonTab(context),
              if (hasDependents)
                _buildDependentsTab(
                    context, dependents, sick: sickDependents != null),
              if (tailscale)
                TailscaleNetworkTab(
                  liveTag: widget.tag,
                  body: _networkBody,
                  onSaveExitNode: _saveExitNode,
                ),




              NodeDiagnosticsTab(
                liveTag: widget.tag,
                warnings: warnings,
                header: _chainHops == null
                    ? null
                    : ChainPositionsBlock(
                        chainTag: widget.tag, hops: _chainHops!),
              ),
            ],
          ),
        ),
      ),
    );
  }







  Widget _buildDependentsTab(
    BuildContext context,
    List<DependentRef> dependents, {
    required bool sick,
  }) {
    final cs = Theme.of(context).colorScheme;

    final sorted = [...dependents]
      ..sort((a, b) {
        if (a.isDns != b.isDns) return a.isDns ? -1 : 1;
        return a.tag.compareTo(b.tag);
      });
    String subtitleOf(DependentRef d) {
      final via = d.via;
      if (via == null) {
        return d.isDns
            ? getLocalText.s("DNS server — direct detour")
            : getLocalText.s("Node — direct detour");
      }
      final label = _directions
          .where((c) => c.tag == via)
          .map((c) => c.label)
          .firstOrNull ??
          via;
      return d.isDns
          ? getLocalText.s('DNS server — via "%1\$s"', label)
          : getLocalText.s('Node — via "%1\$s"', label);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Icon(
                sick ? Icons.warning_amber_rounded : Icons.account_tree_outlined,
                size: 20,
                color: sick ? cs.error : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sick
                      ? getLocalText.s(
                          'These depend on dead node "%1\$s" and are not working:',
                          widget.tag)
                      : getLocalText.s("These route through this node:"),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        for (final d in sorted)
          ListTile(
            dense: true,
            leading: Icon(
              d.isDns ? Icons.dns_outlined : Icons.lan_outlined,
              size: 20,
              color: sick ? cs.error : cs.onSurfaceVariant,
            ),
            title:
                Text(d.tag, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(subtitleOf(d),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: d.isDns ? null : () => _onTagTap(d.tag),
          ),
      ],
    );
  }



  Widget _buildOverviewTab(BuildContext context) {
    final node = widget.config[widget.tag];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _sectionHeader(context, 'Parameters'),
        ..._paramRows(context, node),
        const SizedBox(height: 16),
        _sectionHeader(context, 'Route'),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            getLocalText.s("Live path in packet order. Tap a hop to open its source."),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ..._routeRows(context),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }


  List<Widget> _paramRows(BuildContext context, ConfigNode? node) {
    if (node == null) {
      return [_kvRow(context, 'Type', 'not in current config')];
    }
    final raw = node.raw;
    final server = raw['server'];
    final port = raw['server_port'];
    final members = raw['outbounds'];
    final typeLabel =
        node.kind == 'endpoint' ? '${node.type} · endpoint' : node.type;



    final balancer = raw['balancer'];
    final pool = balancer is Map ? balancer['pool'] : null;
    final poolTolerance =
        balancer is Map ? balancer['pool_tolerance'] : null;
    return [
      _kvRow(context, 'Type', typeLabel),
      if (server is String && server.isNotEmpty)
        _kvRow(context, 'Server', port == null ? server : '$server:$port'),
      if (node.transportLabel != null)
        _kvRow(context, 'Transport', node.transportLabel!),
      if (node.securityLabel != null)
        _kvRow(context, 'Security', node.securityLabel!),
      if (_isGroupNode)
        _kvRow(
            context,
            'Mode',
            _isManualGroup
                ? getLocalText.s("Manual")
                : _isBalancer
                    ? getLocalText.s("Load balance")
                    : getLocalText.s("Fastest")),
      if (_isBalancer && pool != null) _kvRow(context, 'Pool', '$pool'),
      if (_isBalancer && poolTolerance is int && poolTolerance > 0)
        _kvRow(context, 'Pool tolerance', '$poolTolerance ms'),
      if (members is List) _membersTile(context, members),


      if (node.type == 'wireguard' || node.type == 'awg')
        ListenableBuilder(
          listenable: widget.homeController,
          builder: (context, _) => _endpointBlock(context, node),
        ),
    ];
  }

  bool _endpointToggleBusy = false;




  Widget _endpointBlock(BuildContext context, ConfigNode node) {
    final hs = widget.homeController.state;
    final st = hs.endpointStates[widget.tag] ?? '';
    final value = _endpointStateValue(node);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (value != null) _kvRow(context, 'Endpoint state', value),
        if (hs.tunnelUp && st.isNotEmpty)
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(getLocalText.s("Node enabled")),
            subtitle: Text(getLocalText
                .s("Stays off until you turn it on or stop the VPN.")),
            value: st != CcEndpointState.disabled,
            onChanged: _endpointToggleBusy
                ? null
                : (_) => unawaited(_toggleEndpoint()),
          ),
      ],
    );
  }

  Future<void> _toggleEndpoint() async {
    setState(() => _endpointToggleBusy = true);
    await toggleEndpoint(context, widget.homeController, widget.tag);
    if (mounted) setState(() => _endpointToggleBusy = false);
  }





  String? _endpointStateValue(ConfigNode node) {
    if (node.type != 'wireguard' && node.type != 'awg') return null;
    final hs = widget.homeController.state;
    final st = hs.endpointStates[widget.tag];
    if (st == null || st.isEmpty) return null;

    if (st == CcEndpointState.disabled) return getLocalText.s("off");
    final idle = hs.endpointIdleSince[widget.tag];
    if (st == CcEndpointState.asleep && idle != null && idle > 0) {
      return '$st · idle for $idle s';
    }
    return st;
  }







  Widget _membersTile(BuildContext context, List<dynamic> members) {
    final cs = Theme.of(context).colorScheme;
    final slots = _pool ?? const <CcPoolSlot>[];
    final byTag = {for (final s in slots) s.tag: s};
    return Theme(

      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(

        initiallyExpanded: _isManualGroup,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 90,
              child: Text(getLocalText.s("Members"),
                  style:
                      TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            ),
            Expanded(
              child: Text(

                _isBalancer && slots.isNotEmpty
                    ? '${members.length} · '
                        '${getLocalText.plural("%d in pool", slots.length)}'
                    : '${members.length}',
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        children: [
          for (final m in members)
            _memberRow(context, '$m',
                inPool: byTag['$m'], chosen: '$m' == _manualSelected),
        ],
      ),
    );
  }






  Widget _memberRow(BuildContext context, String tag,
      {CcPoolSlot? inPool, bool chosen = false}) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _onTagTap(tag),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [


            if (_isManualGroup)
              InkResponse(
                key: ValueKey('member-select-$tag'),
                radius: 16,
                onTap: () => _selectMember(tag),
                child: SizedBox(
                  width: 24,
                  child: Icon(
                      chosen
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: chosen ? cs.primary : cs.onSurfaceVariant),
                ),
              )
            else
              SizedBox(
                width: 24,
                child: inPool == null
                    ? null
                    : Icon(Icons.check, size: 15, color: cs.onSurfaceVariant),
              ),
            Expanded(
              child: Text(tag,
                  style: TextStyle(
                      fontSize: 13,
                      color:
                          inPool == null ? cs.onSurfaceVariant : cs.onSurface),
                  overflow: TextOverflow.ellipsis),
            ),
            if (inPool != null && inPool.delay > 0) ...[
              const SizedBox(width: 8),

              Text('${inPool.delay} ms',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: poolDelayColor(context, inPool.delay))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kvRow(BuildContext context, String k, String v) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(k,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(v,
                style:
                    const TextStyle(fontSize: 13, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }








  List<Widget> _routeRows(BuildContext context) {







    final hops = _isBalancer
        ? [for (final h in _hops) if (!h.viaSelection) h]
        : _hops;
    final truncated = !_isBalancer && hops.isNotEmpty && hops.first.isGroup;
    return [
      _endpointRow(context, Icons.smartphone, 'Phone'),
      if (truncated) _ellipsisRow(context),
      for (var i = 0; i < hops.length; i++)
        _hopRow(context, hops[i], isSelf: i == hops.length - 1),

      if (_isBalancer) _poolHopTile(context),
      _endpointRow(context, Icons.public, 'Internet'),
    ];
  }







  Widget _poolHopTile(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final slots = _pool;


    final count = slots?.length ?? 0;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 28, bottom: 4),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        leading: Icon(Icons.account_tree_outlined,
            size: 20, color: cs.onSurfaceVariant),
        title: Text(
          count > 0
              ? getLocalText.plural("%d nodes in pool", count)
              : getLocalText.s("Pool"),
          style: const TextStyle(fontSize: 14),
        ),
        subtitle: Text(
          slots == null
              ? getLocalText.s("connect to see the live pool")
              : getLocalText.s("traffic is spread across slots"),
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        children: [
          for (final s in slots ?? const <CcPoolSlot>[])
            poolSlotRow(context, s, onTap: () => _onTagTap(s.tag)),
        ],
      ),
    );
  }

  Widget _endpointRow(BuildContext context, IconData icon, String label) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20, color: cs.onSurfaceVariant),
      title: Text(label,
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
    );
  }

  Widget _ellipsisRow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.more_vert, size: 20, color: cs.onSurfaceVariant),
      title: Text(
        getLocalText.s("connect to see the full path"),
        style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: cs.onSurfaceVariant),
      ),
    );
  }

  Widget _hopRow(BuildContext context, RuntimeHop hop,
      {required bool isSelf}) {
    final cs = Theme.of(context).colorScheme;


    final ch = hop.direction;
    final title = ch != null ? ch.displayLabel : hop.tag;
    final subtitle = [
      if (hop.isUnknown) 'not in config' else hop.type,
      if (hop.viaSelection) 'current pick',
      if (isSelf) 'this node',
    ].join(' · ');
    final icon = hop.isUnknown
        ? Icons.help_outline
        : hop.isGroup
            ? Icons.hub_outlined
            : Icons.dns_outlined;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20,
          color: isSelf ? cs.primary : cs.onSurfaceVariant),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isSelf ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      subtitle: Text(subtitle,
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      trailing: Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
      onTap: () => _onHopTap(hop),
    );
  }



  Widget _buildJsonTab(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: LxJsonView(text: _jsonCtrl.text),
    );
  }

}
