import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/home_controller.dart';
import '../controllers/subscription_controller.dart';
import '../models/custom_rule.dart';
import '../models/dns_ref.dart';
import '../services/builder/build_config.dart' show varIntInBounds;
import '../services/builder/post_steps.dart';
import '../services/dns/dns_controller.dart';
import '../services/dns/tailscale_endpoint_options.dart';
import '../services/l10n/template_aware_state.dart';
import '../services/template_loader.dart';
import '../services/preset_nodes_view.dart';
import '../services/preset_on_change.dart';
import '../services/ui_helpers.dart';
import '../services/settings_storage.dart';
import '../vpn/box_vpn_client.dart';
import '../vpn/cc_channel.dart';
import '../widgets/outbound_picker.dart';
import 'dns_server_edit_screen.dart';
import 'dns_settings_screen/dns_server_resolver.dart';
import 'dns_settings_screen/resolved_server.dart';
import 'dns_settings_screen/user_rule_editor_sheet.dart';
import 'dns_settings_screen/widgets/dns_mirror_group_card.dart';
import 'dns_settings_screen/widgets/dns_rule_tile.dart';
import 'dns_settings_screen/widgets/local_resolver_warning_banner.dart';
import 'dns_settings_screen/widgets/merged_server_tile.dart';
import 'dns_settings_screen/widgets/resolver_picker.dart';
import 'lazy_persist_mixin.dart';
import '../services/l10n/locale_controller.dart';






class DnsSettingsScreen extends StatefulWidget {
  const DnsSettingsScreen({
    super.key,
    required this.subController,
    required this.homeController,
  });

  final SubscriptionController subController;
  final HomeController homeController;

  @override
  State<DnsSettingsScreen> createState() => _DnsSettingsScreenState();
}

class _DnsSettingsScreenState extends State<DnsSettingsScreen>
    with
        WidgetsBindingObserver,
        LazyPersistMixin<DnsSettingsScreen>,
        TemplateAwareState<DnsSettingsScreen> {
  @override
  SubscriptionController get lazyController => widget.subController;








  List<DnsServerRef> _servers = [];



  Map<String, Map<String, dynamic>> _templateByTag = {};



  Map<String, Map<String, dynamic>> _presetServersByTag = {};


  List<DnsRuleRef> _rules = [];



  Map<String, Map<String, dynamic>> _templateRulesByName = {};




  Map<String, List<Map<String, dynamic>>> _presetRulesByPresetId = {};



  Map<String, String> _presetLabelByPresetId = {};


  Map<String, List<String>> _presetServedTagsByPresetId = {};




  List<OutboundOption> _outboundOptions = const [];



  List<CustomRule> _customRules = const [];






  Map<String, List<DnsMirrorEntry>> _dnsMirrorsByRuleId = const {};




  Map<String, bool> _presetDnsEnable = const {};



  List<TailscaleEndpointOption> get _tailscaleEndpoints =>
      collectTailscaleEndpointOptions(
        [for (final e in widget.subController.entries) e.list],
        lastEmittedTagMap: widget.subController.lastEmittedTagMap,
      );

  bool _loading = true;


  String _strategy = '';
  String _dnsFinal = '';
  String _defaultResolver = '';


  String _cacheCapacity = '';
  bool _optimistic = true;
  bool _storeCache = true;
  String _cacheCapacityError = '';
  final TextEditingController _cacheCapacityCtl = TextEditingController();

  @override
  void dispose() {
    _cacheCapacityCtl.dispose();
    super.dispose();
  }



  void _applyCacheCapacity(String raw) {
    final v = raw.trim();
    if (!varIntInBounds('dns_cache_capacity', v)) {
      setState(() => _cacheCapacityError =
          getLocalText.s("Range 1024..65535"));
      return;
    }
    setState(() {
      _cacheCapacityError = '';
      if (v == _cacheCapacity) return;
      _cacheCapacity = v;
      _markDirty();
    });
  }







  @override
  void onLocaleTemplateFetch({required bool first}) {
    unawaited(_load());


    if (first) unawaited(_pullDnsGroups());
  }


  void _markDirty() => markDirty();

  Future<void> _load() async {




    final template = await TemplateLoader.load();
    final s = await DnsController.load(
      presetNodes: presetNodesForView(
        [for (final e in widget.subController.entries) e.list],
        nodeTypes: forEachNodeTypes(template.selectableRules),
        lastEmittedTagMap: widget.subController.lastEmittedTagMap,
      ),
    );
    if (!mounted) return;
    setState(() {
      _servers = s.servers;
      _templateByTag = s.templateByTag;
      _presetServersByTag = s.presetServersByTag;
      _rules = s.rules;
      _templateRulesByName = s.templateRulesByName;
      _presetRulesByPresetId = s.presetRulesByPresetId;
      _presetLabelByPresetId = s.presetLabelByPresetId;
      _presetServedTagsByPresetId = s.presetServedTagsByPresetId;
      _presetDnsEnable = s.presetDnsEnable;
      _outboundOptions = s.outboundOptions;
      _customRules = s.customRules;
      _dnsMirrorsByRuleId = s.dnsMirrorsByRuleId;
      _strategy = s.strategy;
      _dnsFinal = s.dnsFinal;
      _defaultResolver = s.defaultResolver;
      _cacheCapacity = s.cacheCapacity;
      _optimistic = s.optimistic;
      _storeCache = s.storeCache;
      _cacheCapacityError = '';
      _cacheCapacityCtl.text = s.cacheCapacity;
      _loading = false;
    });

    if (s.resolverReset) _markDirty();
  }



  @override
  Future<void> stageChanges() async {


    await DnsController.stage(
      servers: _servers,
      rules: _rules,
      templateRulesByName: _templateRulesByName,
      presetRulesByPresetId: _presetRulesByPresetId,
      strategy: _strategy,
      dnsFinal: _dnsFinal,
      defaultResolver: _defaultResolver,
      cacheCapacity: _cacheCapacity,
      optimistic: _optimistic,
      storeCache: _storeCache,
    );
  }



  Map<String, String> get _ruleRefsByTag => {
        for (final cr in _customRules)
          if (cr.dnsMirrorActive)
            cr.dns!.serverTag: cr.name.isNotEmpty ? cr.name : 'rule',
      };


  List<ResolvedServer> get _displayedServers => resolveDisplayedServers(
      _servers, _templateByTag, _presetServersByTag,
      ruleRefsByTag: _ruleRefsByTag);



  List<String> get _enabledServerTags => enabledServerTags(_displayedServers);




  List<DnsMemberOption> get _dnsMemberOptions => [
        for (final s in _displayedServers)
          if (s.body['type'] != 'fakeip' && s.body['type'] != 'hosts')
            DnsMemberOption(
              tag: s.tag,
              type: s.body['type']?.toString() ?? '',
              enabled: s.enabled || s.locked,
            ),
      ];



  Map<String, CcDnsGroup> _liveDnsGroups = const {};

  Future<void> _pullDnsGroups() async {
    if (!widget.homeController.state.tunnelUp) return;
    final groups = await CcChannel.instance.getDnsGroups();
    if (!mounted || groups == null) return;
    setState(() {
      _liveDnsGroups = {for (final g in groups) g.tag: g};
    });
  }




  Future<void> _addServer() async {
    final result = await openDnsServerEditor(
      context,
      initialRef: DnsServerInline(
        enabled: true,
        tag: 'dns_new',


        description: getLocalText.s("My DNS"),
        body: const <String, dynamic>{'type': 'udp'},
      ),
      outboundOptions: _outboundOptions,
      dnsServerTags: _enabledServerTags,
      dnsMemberOptions: _dnsMemberOptions,
      tailscaleEndpoints: _tailscaleEndpoints,
      existingTags: {for (final s in _servers) s.tag},
    );
    if (result == null || !mounted) return;
    final saved = result.saved;
    if (saved == null) return;
    setState(() {

      _servers.removeWhere((s) => s.tag == saved.tag);
      _servers.add(saved);
      _markDirty();
    });
  }




  Future<void> _editServer(String tag) async {
    final idx = _servers.indexWhere((s) => s.tag == tag);
    if (idx < 0) return;
    ResolvedServer? resolved;
    for (final s in _displayedServers) {
      if (s.tag == tag) {
        resolved = s;
        break;
      }
    }
    if (resolved == null) return;

    final canonicalDescription = switch (resolved.kind) {
      ServerKind.template =>
        _templateByTag[tag]?['description']?.toString() ?? '',
      ServerKind.preset =>
        _presetServersByTag[tag]?['description']?.toString() ?? '',
      ServerKind.inline => '',
    };

    final result = await openDnsServerEditor(
      context,
      initialRef: _servers[idx],
      resolved: resolved,
      templateWrapper:
          resolved.kind == ServerKind.template ? _templateByTag[tag] : null,
      canonicalDescription: canonicalDescription,
      outboundOptions: _outboundOptions,

      dnsServerTags: _enabledServerTags.where((t) => t != tag).toList(),
      dnsMemberOptions: _dnsMemberOptions,
      tailscaleEndpoints: _tailscaleEndpoints,

      existingTags: {
        for (final s in _servers)
          if (s.tag != tag) s.tag,
      },
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.wasDeleted) {
        _servers.removeAt(idx);
      } else if (result.saved != null) {
        _servers[idx] = result.saved!;


        final newTag = result.saved!.tag;
        if (newTag.isNotEmpty && newTag != tag) {
          final updated = renameDnsServerTagRefs(
            servers: _servers,
            rules: _rules,
            templateByTag: _templateByTag,
            oldTag: tag,
            newTag: newTag,
            dnsFinal: _dnsFinal,
            defaultResolver: _defaultResolver,
          );
          _dnsFinal = updated.dnsFinal;
          _defaultResolver = updated.defaultResolver;
          final renamed = renameRuleDnsServerTag(_customRules, tag, newTag);
          if (!identical(renamed, _customRules)) {
            _customRules = renamed;


            unawaited(SettingsStorage.saveCustomRules(renamed));
          }
        }
      } else {
        return;
      }
      _markDirty();
    });
  }

  void _addUserRule() => _showUserRuleEditor(-1);



  static String _ruleIdentity(DnsRuleRef r) => switch (r) {
        DnsRuleInline(:final name) ||
        DnsRuleSrs(:final name) ||
        DnsRuleTemplate(:final name) =>
          name,
        DnsRulePreset(:final presetId) => presetId,
      };


  List<CustomRule> get _ruleMirrors =>
      [for (final cr in _customRules) if (cr.dnsMirrorActive) cr];






  List<int> get _ruleDisplayRows {
    final hasGroup =
        _rules.any((e) => e is DnsRulePreset) || _ruleMirrors.isNotEmpty;
    final rows = <int>[];
    var groupInserted = false;
    for (var i = 0; i < _rules.length; i++) {
      final entry = _rules[i];
      if (entry is DnsRulePreset) {
        if (!groupInserted) {
          rows.add(-1);
          groupInserted = true;
        }
        continue;
      }
      if (entry is DnsRuleTemplate && hasGroup && !groupInserted) {
        rows.add(-1);
        groupInserted = true;
      }
      rows.add(i);
    }
    if (hasGroup && !groupInserted) rows.add(-1);
    return rows;
  }




  List<Widget> _buildMirrorGroupChildren() {
    final presetIdxByPid = <String, int>{};
    for (var i = 0; i < _rules.length; i++) {
      final entry = _rules[i];
      if (entry is DnsRulePreset) presetIdxByPid[entry.presetId] = i;
    }
    final children = <Widget>[];
    final seenPresetIds = <String>{};
    for (final cr in _customRules) {
      if (cr is CustomRulePreset) {





        final idx = presetIdxByPid[cr.presetId];
        if (idx == null || !seenPresetIds.add(cr.presetId)) continue;
        final dnsEnable = _presetDnsEnable[cr.presetId];
        children.add(DnsMirrorTile(
          key: ValueKey('dns-rule-preset-${cr.presetId}'),
          title: _presetLabelByPresetId[cr.presetId] ?? cr.presetId,


          previewBodies: _presetRulesByPresetId[cr.presetId] ?? const [],
          sourceKind: 'preset',
          enabled: dnsEnable ?? true,
          onToggle: dnsEnable == null
              ? null
              : (v) => _togglePresetDnsEnable(cr.presetId, v),

          note: switch (_presetServedTagsByPresetId[cr.presetId]) {
            final List<String> tags => presetServedNodesLabel(tags),
            null => null,
          },
        ));
      } else {





        final hasServerAspect = cr.dnsMirrorEligible;




        final hasForceAspect = cr.forceIpv4Active;
        if (!hasServerAspect && !hasForceAspect) continue;
        final mirrors = _dnsMirrorsByRuleId[cr.id] ?? const <DnsMirrorEntry>[];
        Map<String, dynamic>? serverBody;
        Map<String, dynamic>? forceBody;
        for (final m in mirrors) {
          if (m.serverless) {
            forceBody ??= m.body;
          } else {
            serverBody ??= m.body;
          }
        }
        final missing =
            !_servers.any((s) => s.tag == (cr.dns?.serverTag ?? ''));
        children.add(DnsRuleAspectsTile(
          key: ValueKey('dns-mirror-${cr.id}'),
          title: cr.name,
          serverRow: hasServerAspect
              ? DnsAspectRow(
                  body: <String, dynamic>{
                    ...?serverBody,
                    'server': cr.dns!.serverTag,
                  },
                  enabled: cr.dns!.enabled,
                  onToggle: (v) => _toggleRuleDns(cr, v),
                  note: [
                    if (cr is CustomRuleSrs) getLocalText.s("matches only domains in the rule-set"),
                    if (missing) getLocalText.s("server missing"),
                  ].join(' · '),
                )
              : null,





          forceIpv4Row: hasForceAspect
              ? DnsAspectRow(
                  body: forceBody ??
                      const <String, dynamic>{
                        'ip_version': 6,
                        'action': 'predefined',
                        'rcode': 'NOERROR',
                      },
                  enabled: true,
                  onRemove: () => _toggleRuleForceIpv4(cr, false),
                )
              : null,
        ));
      }
    }
    return children;
  }





  void _onReorderRules(int oldIndex, int newIndex) {
    final rows = _ruleDisplayRows;
    if (oldIndex < 0 || oldIndex >= rows.length) return;
    final presetBlock = [
      for (final e in _rules)
        if (e is DnsRulePreset) e,
    ];
    final units = <List<DnsRuleRef>>[
      for (final r in rows) r == -1 ? presetBlock : [_rules[r]],
    ];
    final moved = units.removeAt(oldIndex);
    units.insert(newIndex.clamp(0, units.length), moved);
    setState(() {
      _rules
        ..clear()
        ..addAll([for (final u in units) ...u]);
      _markDirty();
    });
  }

  void _showUserRuleEditor(int index) {
    final isNew = index < 0;

    final existing = isNew ? null : _rules[index] as DnsRuleInline;
    showUserRuleEditor(
      context,
      isNew: isNew,
      existing: existing,
      onSave: (entry) {
        setState(() {
          if (isNew) {



            _rules.insert(0, entry);
          } else {
            _rules[index] = entry;
          }
          _markDirty();
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(getLocalText.s("DNS Settings"))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);



    final displayed = _displayedServers;
    final serverTags = enabledServerTags(displayed);




    final resolverTags = [
      for (final s in displayed)
        if (serverTags.contains(s.tag) &&
            s.body['type'] != 'fakeip' &&
            s.body['type'] != 'hosts')
          s.tag,
    ];
    final mirrors = _ruleMirrors;
    final rows = _ruleDisplayRows;

    return Scaffold(
      appBar: AppBar(title: Text(getLocalText.s("DNS Settings"))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(12, 12, 12, MediaQuery.of(context).padding.bottom + 24),
        children: [

          Row(
            children: [
              Text(getLocalText.s("DNS Servers"),
                  style: theme.textTheme.titleMedium),
              const Spacer(),
              IconButton(icon: const Icon(Icons.add), onPressed: _addServer),
            ],
          ),
          const SizedBox(height: 4),


          ...displayed.map((entry) => MergedServerTile(
                entry: entry,
                onToggleEnabled: _toggleServerEnabled,
                onTap: _editServer,
                liveGroup: _liveDnsGroups[entry.tag],
              )),
          const Divider(height: 32),


          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(getLocalText.s("Strategy")),
            trailing: DropdownButton<String>(
              value: ['prefer_ipv4', 'prefer_ipv6', 'ipv4_only', 'ipv6_only'].contains(_strategy)
                  ? _strategy : 'ipv4_only',
              items: const [
                DropdownMenuItem(value: 'prefer_ipv4', child: Text('prefer_ipv4')),
                DropdownMenuItem(value: 'prefer_ipv6', child: Text('prefer_ipv6')),
                DropdownMenuItem(value: 'ipv4_only', child: Text('ipv4_only')),
                DropdownMenuItem(value: 'ipv6_only', child: Text('ipv6_only')),
              ],
              onChanged: (v) { if (v != null) setState(() { _strategy = v; _markDirty(); }); },
            ),
          ),

          const Divider(height: 32),


          Row(
            children: [
              Text(getLocalText.s("DNS Rules"), style: theme.textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: _addUserRule,
                icon: const Icon(Icons.add, size: 18),
                label: Text(getLocalText.s("Add user rule")),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_rules.isEmpty && mirrors.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                getLocalText.s("No DNS rules. Add user rules manually, or enable presets / template defaults."),
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            )
          else


            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: rows.length,
              onReorderItem: _onReorderRules,
              itemBuilder: (ctx, i) {
                final row = rows[i];
                if (row == -1) {


                  final draggable = _rules.any((e) => e is DnsRulePreset);
                  return DnsMirrorGroupCard(
                    key: const ValueKey('dns-mirror-group'),
                    dragIndex: draggable ? i : null,
                    children: _buildMirrorGroupChildren(),
                  );
                }
                return DnsRuleTile(
                  index: row,
                  dragIndex: i,
                  entry: _rules[row],
                  templateRulesByName: _templateRulesByName,
                  presetRulesByPresetId: _presetRulesByPresetId,
                  presetLabelByPresetId: _presetLabelByPresetId,
                  onToggleEnabled: _toggleRuleEnabled,
                  onEdit: _showUserRuleEditor,
                  onDelete: _deleteRule,


                  key: ValueKey(
                    'dns-rule-$row-${_ruleIdentity(_rules[row])}',
                  ),
                );
              },
            ),
          const Divider(height: 32),







          ResolverPicker(
            title: getLocalText.s("DNS Final"),
            subtitle: getLocalText.s("For apps · default fallback when no DNS rule matches"),
            value: _dnsFinal,
            serverTags: resolverTags,
            onChanged: (v) => setState(() { _dnsFinal = v; _markDirty(); }),
            tooltip: getLocalText.s("Default fallback DNS server. Used when an app makes a DNS query and no DNS rule above matches it. Every app DNS query that isn't routed by a rule ends up here.\n\nRecommended:\n  • dns_shield — default; races 6 encrypted providers, answers from whichever replies first\n  • google_doh — encrypted (DoH)\n  • cloudflare_dot / google_dot — encrypted (DoT)\n  • cloudflare_udp / google_udp — fast plain UDP\n\nlocal_dns_resolver works but reveals queries to your ISP. Encrypted options keep them private."),
            warnIfLocal: false,
          ),








          ResolverPicker(
            title: getLocalText.s("Default Domain Resolver"),
            subtitle: getLocalText.s("For routing · resolves hostnames inside sing-box (outbound endpoints, routing rules)"),
            value: _defaultResolver,
            serverTags: resolverTags,
            onChanged: (v) => setState(() { _defaultResolver = v; _markDirty(); }),
            tooltip: getLocalText.s("Used by routing engine to resolve hostnames internally (outbound endpoints, routing rules). Not the resolver apps use.\n\nRecommended:\n  • dns_shield — default; races 6 encrypted providers, answers from whichever replies first\n  • cloudflare_udp — UDP to 1.1.1.1 (fast)\n  • google_udp — UDP to 8.8.8.8 (fast)\n  • google_doh — encrypted\n\n⚠ local_dns_resolver here leaks lookups to your ISP — system DNS bypasses the VPN."),
            warnIfLocal: true,
          ),
          if (_defaultResolver == 'local_dns_resolver')
            LocalResolverWarningBanner(
              hasCloudflareUdp:
                  _servers.any((s) => s.tag == 'cloudflare_udp'),
              onSwitchToCloudflareUdp: () => setState(() {
                _defaultResolver = 'cloudflare_udp';
                _markDirty();
              }),
            ),



          const Divider(height: 32),
          TextField(
            key: const ValueKey('dns_cache_capacity'),
            controller: _cacheCapacityCtl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: getLocalText.s("DNS cache size"),
              helperText: getLocalText.s("Number of cached answers."),
              errorText:
                  _cacheCapacityError.isEmpty ? null : _cacheCapacityError,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: _applyCacheCapacity,
          ),
          SwitchListTile(
            key: const ValueKey('dns_optimistic'),
            contentPadding: EdgeInsets.zero,
            title: Text(getLocalText.s("Serve stale answers")),
            subtitle: Text(getLocalText.s(
                "Answer from cache at once and refresh in the background.")),
            value: _optimistic,
            onChanged: (v) => setState(() {
              _optimistic = v;
              _markDirty();
            }),
          ),
          SwitchListTile(
            key: const ValueKey('dns_store_cache'),
            contentPadding: EdgeInsets.zero,
            title: Text(getLocalText.s("Keep DNS cache after restart")),
            value: _storeCache,
            onChanged: (v) => setState(() {
              _storeCache = v;
              _markDirty();
            }),
          ),




          ListTile(
            leading: Icon(Icons.cleaning_services_outlined,
                color: Theme.of(context).colorScheme.error),
            title: Text(getLocalText.s("Clear DNS cache")),
            subtitle: Text(getLocalText.s("Flush FakeIP allocations and cached DNS responses. Reloads the VPN if running.")),
            onTap: _confirmClearDnsCache,
          ),
        ],
      ),
    );
  }




  Future<void> _confirmClearDnsCache() async {
    final running = widget.homeController.state.tunnelUp;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(getLocalText.s("Clear DNS cache?")),
        content: Text(
          getLocalText.s("This deletes the DNS cache (FakeIP allocations and cached responses).\n\n%s", running
              ? getLocalText.s("The VPN will briefly reload to apply.")
              : getLocalText.s("It will be rebuilt clean on the next connect.")),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(getLocalText.s("Cancel")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(getLocalText.s("Clear")),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final ok = await BoxVpnClient().clearDnsCache();
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? (running
              ? getLocalText.s("DNS cache cleared — reloading")
              : getLocalText.s("DNS cache cleared"))
          : getLocalText.s("Could not clear DNS cache")),
    ));
  }


  void _toggleServerEnabled(String tag, bool value) {
    final idx = _servers.indexWhere((s) => s.tag == tag);
    if (idx < 0) return;
    setState(() {
      _servers[idx] = _servers[idx].withEnabled(value);
      _markDirty();
    });
  }


  void _toggleRuleEnabled(int index, bool value) {
    setState(() {
      _rules[index] = _rules[index].withEnabled(value);
      _markDirty();
    });
  }






  void _toggleRuleDns(CustomRule cr, bool value) {
    final idx = _customRules.indexWhere((r) => r.id == cr.id);
    if (idx < 0 || cr.dns == null) return;
    final updated = switch (cr) {
      CustomRuleInline() => cr.copyWith(dns: cr.dns!.copyWith(enabled: value)),
      CustomRuleSrs() => cr.copyWith(dns: cr.dns!.copyWith(enabled: value)),
      _ => cr,
    };
    setState(() {
      _customRules = [..._customRules]..[idx] = updated;
      _markDirty();
    });
    unawaited(SettingsStorage.saveCustomRules(_customRules));
  }





  void _toggleRuleForceIpv4(CustomRule cr, bool value) {
    final idx = _customRules.indexWhere((r) => r.id == cr.id);
    if (idx < 0) return;
    final next = (cr.dns ?? const RuleDns()).copyWith(forceIpv4: value);
    final clear =
        !next.forceIpv4 && !next.enabled && next.serverTag.isEmpty;
    final updated = switch (cr) {
      CustomRuleInline() =>
        clear ? cr.copyWith(clearDns: true) : cr.copyWith(dns: next),
      CustomRuleSrs() =>
        clear ? cr.copyWith(clearDns: true) : cr.copyWith(dns: next),
      _ => cr,
    };
    if (identical(updated, cr)) return;
    setState(() {
      _customRules = [..._customRules]..[idx] = updated;
      _markDirty();
    });
    unawaited(SettingsStorage.saveCustomRules(_customRules));
  }





  void _togglePresetDnsEnable(String presetId, bool value) {
    final idx = _customRules.indexWhere(
        (r) => r is CustomRulePreset && r.presetId == presetId);
    if (idx < 0) return;
    final cr = _customRules[idx] as CustomRulePreset;
    final updated = cr.copyWith(
      varsValues: {...cr.varsValues, 'dns_enable': value ? 'true' : 'false'},
    );
    setState(() {
      _customRules = [..._customRules]..[idx] = updated;
      _presetDnsEnable = {..._presetDnsEnable, presetId: value};
      _markDirty();
    });
    unawaited(SettingsStorage.saveCustomRules(_customRules));


    unawaited(() async {
      final template = await TemplateLoader.load();
      final match = template.selectableRules
          .where((p) => p.presetId == presetId)
          .firstOrNull;
      if (match != null) await applyPresetOnChange(match, updated);
    }());
  }



  Future<void> _deleteRule(int index) async {
    if (index < 0 || index >= _rules.length) return;
    final name = _ruleIdentity(_rules[index]);
    final confirmed = await showDeleteConfirmDialog(
      context,
      title: getLocalText.s("Delete rule?"),
      message: getLocalText.s("Remove \"%s\" permanently?", name),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      if (index < _rules.length) _rules.removeAt(index);
      _markDirty();
    });
  }

}
