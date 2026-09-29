import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/auto_select.dart';
import '../models/core_reject_verdict.dart';
import '../models/import_rule.dart';
import '../models/node_link.dart';
import '../models/node_spec.dart';
import '../models/node_warning.dart';
import '../models/codec/source_record.dart';
import '../models/server_list.dart';
import '../models/source_replace.dart';
import '../models/source_entry.dart';
import '../models/ui_msg.dart';
import '../models/subscription_meta.dart';
import '../models/tunnel_status.dart';
import '../models/validation.dart';
import '../services/app_log.dart';
import 'subscription_controller/core_reject_ops.dart';
import '../services/core_reject/core_reject_guard.dart';
import '../services/automation/event_emitter.dart';
import '../services/config_dirty_check.dart';
import '../services/error_humanize.dart';
import '../services/parse_hints.dart';
import '../services/relative_time.dart';
import '../services/node_emoji.dart';
import '../services/node_hash.dart';
import '../services/node_identity.dart';
import '../services/node_link_address.dart';
import '../services/settings_storage/node_link_registry.dart';
import '../services/tailscale_state/state_keys.dart';
import '../services/tailscale_state/state_store.dart';
import '../services/url_mask.dart';
import '../services/builder/build_config.dart';
import '../services/builder/if_engine.dart' show TemplateWarning;
import '../services/builder/core_chain_capability.dart';
import '../vpn/box_vpn_client.dart';
import '../services/parser/body_decoder.dart';
import '../services/parser/ini_parser.dart';
import '../services/parser/json_comments.dart';
import '../services/parser/parse_all.dart';
import '../services/parser/tailscale_split.dart';
import '../services/parser/uri_parsers.dart';
import '../services/parser/uri_utils.dart';
import '../services/haptic_service.dart';
import '../services/hate_invitation.dart';
import '../services/settings_storage.dart';
import '../services/subscription/auto_updater.dart';
import '../services/subscription/http_cache.dart';
import '../services/subscription/import_rules.dart';
import '../services/subscription/input_helpers.dart';
import '../services/subscription/sources.dart';
import '../services/subscription/subscription_identity.dart';
import '../services/warp/masque_account.dart';
import '../services/warp/masquerade_params.dart';
import '../services/warp/warp_account.dart';
import '../services/warp/warp_client.dart';
import '../services/warp/warp_endpoint_picker.dart';
import '../services/warp/scan/candidate_generator.dart';
import '../services/warp/scan/scan_models.dart';
import '../services/warp/scan/scan_node_builder.dart';
import '../services/warp/scan/scan_pool.dart';
import '../services/workspaces/workspace_controller.dart';
import '../services/workspaces/workspace_store.dart';



part 'subscription_controller/subscription_entry.dart';




enum _JsonAdd { added, empty, notJson }



class SubscriptionController extends ChangeNotifier {















  final int _bornGeneration = WorkspaceController.I.generation;



  bool _disposed = false;





  bool get stale =>
      _disposed || WorkspaceController.I.generation != _bornGeneration;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }









  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  List<SubscriptionEntry> _entries = [];
  List<SubscriptionEntry> get entries => _entries;



  @visibleForTesting
  void debugSetEntries(List<SubscriptionEntry> entries) {
    _entries = entries;
  }




  AutoUpdater? _autoUpdater;
  void bindAutoUpdater(AutoUpdater u) {
    _autoUpdater = u;
  }

  bool _busy = false;
  bool get busy => _busy;




  bool _generating = false;




  bool get configDirty => SettingsStorage.configDirty;
  set configDirty(bool v) => SettingsStorage.configDirty = v;




  final Completer<void> _rehydrated = Completer<void>();
  Future<void> get rehydrationDone => _rehydrated.future;


  @visibleForTesting
  http.Client? httpClientForTesting;




  @visibleForTesting
  Future<void>? lastCacheSaveForTesting;

  UiMsg? _lastError;


  UiMsg? get lastError => _lastError;




  bool get lastCommentsRemoved => _lastCommentsRemoved;
  bool _lastCommentsRemoved = false;





  List<ValidationIssue> _lastFatalIssues = const [];
  List<ValidationIssue> get lastFatalIssues => _lastFatalIssues;




  Map<String, NodeSpec> _lastTagMap = const {};
  Map<String, NodeSpec> get lastEmittedTagMap => _lastTagMap;


  Map<String, List<NodeWarning>> _lastBuildWarningsByTag = const {};
  Map<String, List<NodeWarning>> get lastBuildWarningsByTag =>
      _lastBuildWarningsByTag;


  @visibleForTesting
  void debugSetLastEmittedTagMap(Map<String, NodeSpec> map) {
    _lastTagMap = map;
  }

  @visibleForTesting
  void debugSetLastBuildWarningsByTag(Map<String, List<NodeWarning>> map) {
    _lastBuildWarningsByTag = map;
  }






  List<String> _directionsWithoutNodes = const [];
  List<String> get directionsWithoutNodes => _directionsWithoutNodes;
  int _directionsWithoutNodesStamp = 0;
  int get directionsWithoutNodesStamp => _directionsWithoutNodesStamp;










  bool _groupDefaultsPending = false;
  bool get groupDefaultsPending => _groupDefaultsPending;

  List<TemplateWarning> _templateWarnings = const [];
  List<TemplateWarning> get templateWarnings => _templateWarnings;
  int _templateWarningsStamp = 0;
  int get templateWarningsStamp => _templateWarningsStamp;

  UiMsg? _progressMessage;
  UiMsg? get progressMessage => _progressMessage;

  String? _lastGeneratedConfig;
  String? get lastGeneratedConfig => _lastGeneratedConfig;

  Future<void> init() async {
    try {
      await _initBody();
    } catch (_) {



      if (!_rehydrated.isCompleted) _rehydrated.complete();
      rethrow;
    }
  }

  Future<void> _initBody() async {
    final lists = await SettingsStorage.getServerLists();
    _entries = lists.map((l) => SubscriptionEntry(list: l)).toList();








    if (configDirty) {
      AppLog.I.info('init: configDirty=true kept from this process');
    } else {
      configDirty = await ConfigDirtyCheck.isDirty();
      if (configDirty) {
        AppLog.I.info('init: configDirty=true via mtime compare');
      }
    }




    var swept = false;
    for (var i = 0; i < _entries.length; i++) {
      final l = _entries[i].list;
      if (l is SubscriptionServers &&
          l.lastUpdateStatus == UpdateStatus.inProgress) {
        _entries[i]._replaceList(
            l.copyWith(lastUpdateStatus: UpdateStatus.failed));
        swept = true;
      }
    }




    if (swept) await _persist(keepDirtyFlag: true);
    notifyListeners();



    unawaited(_rehydrateFromCache());
  }

  Future<void> _rehydrateFromCache() async {
    try {



      final entries = List<SubscriptionEntry>.of(_entries);
      for (final entry in entries) {
        final list = entry.list;
        if (list is! SubscriptionServers) continue;
        if (list.nodes.isNotEmpty) continue;
        final body = await HttpCache.loadBody(list.url);


        if (stale) return;
        if (body == null || body.isEmpty) continue;
        try {
          final decoded = decode(body);


          final dropped = <NodeWarning>[];
          final nodes = parseAll(decoded, dropped: dropped);






          _applyRulesToNodes(nodes, list.activeImportRules);
          if (nodes.isEmpty) {


            final hint = diagnoseEmptyParse(body);
            AppLog.I.warning(
                'Re-hydrate: cached body parsed to 0 nodes for '
                '${maskSubscriptionUrl(list.url)}${hint != null ? ' — $hint' : ''}');
            continue;
          }





          if (!_entries.contains(entry)) continue;
          final cur = entry.list;
          if (cur is! SubscriptionServers ||
              cur.url != list.url ||
              cur.nodes.isNotEmpty) {
            continue;
          }





          final migrated =
              migrateLegacyDisabledKeys(cur.disabledHashes, nodes);



          stampStoredVerdicts(nodes, cur.nodeWarnings);
          final next = cur.copyWith(
            nodes: nodes,
            lastNodeCount: nodes.length,
            disabledHashes: migrated,
            dropped: summaryDropped(dropped),
          );
          entry._replaceList(next);



          if (!identical(migrated, cur.disabledHashes)) {
            await _persist(keepDirtyFlag: true);
          }
          final detours = nodes.where((n) => n.chained != null).length;
          entry.nodeCount = nodes.length;
          entry.status =
              SubStatusNodes(nodes.length, detours: detours, cached: true);
          AppLog.I.info(
              'Re-hydrated ${nodes.length} nodes from cache: ${maskSubscriptionUrl(list.url)}');
        } catch (e) {
          AppLog.I.warning(
              'Re-hydrate failed for ${maskSubscriptionUrl(list.url)}: ${humanizeError(e).renderEn()}');
        }
      }
      notifyListeners();
    } finally {
      if (!_rehydrated.isCompleted) _rehydrated.complete();
    }
  }








  ({Set<String> disable, Set<String> enable}) _applyRulesToNodes(
      List<NodeSpec> nodes, List<ImportRule> rules) {




    for (final n in nodes) {
      n.patchedJson = null;
      n.ruleTrail = const [];
    }
    if (rules.isEmpty || nodes.isEmpty) return (disable: const {}, enable: const {});
    final result = applyImportRules(nodes, rules);
    if (result.isEmpty) return (disable: const {}, enable: const {});

    final disable = <String>{};
    final enable = <String>{};



    final identities = sourceNodeIdentities(nodes);
    result.outcomes.forEach((i, outcome) {
      if (i < 0 || i >= nodes.length) return;
      final node = nodes[i];
      if (outcome.patchedJson != null) {
        node.patchedJson = outcome.patchedJson;
        node.ruleTrail = outcome.replacements;
      }
      final identity = identities[node];
      if (identity == null) return;
      if (outcome.disabled == true) disable.add(identity);
      if (outcome.disabled == false) enable.add(identity);
    });




    _remapAutoSelectSynonyms(nodes);
    return (disable: disable, enable: enable);
  }




  void _remapAutoSelectSynonyms(List<NodeSpec> nodes) {
    final autos = nodes.whereType<AutoSelectSpec>().toList();
    if (autos.isEmpty) return;

    final moved = <String, String>{};
    for (final n in nodes) {
      if (n.patchedJson == null) continue;
      final before = nodeIdentityKeyRaw(n);
      final after = nodeIdentityKey(n);
      if (before != null && after != null && before != after) {
        moved[before] = after;
      }
    }
    if (moved.isEmpty) return;
    for (var i = 0; i < nodes.length; i++) {
      final a = nodes[i];
      if (a is! AutoSelectSpec || a.tagSynonyms.isEmpty) continue;
      nodes[i] = a.copyWith(tagSynonyms: {
        for (final e in a.tagSynonyms.entries) e.key: moved[e.value] ?? e.value,
      });
    }
  }






  Future<void> addUserServer(UserServer us) async {
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      final tagged = _autoEmoji(us);
      _entries
          .add(SubscriptionEntry(list: tagged, nodeCount: tagged.nodes.length));
      await _persist();
      AppLog.I.info(
          'addUserServer: ${us.id} ${us.name} (${us.nodes.length} node)');
    } catch (e) {
      _lastError = humanizeError(e);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }











  Future<WarpAccount?> addWarp({
    String? licenseKey,
    String endpoint = WarpAccount.defaultEndpoint,
    bool reuse = true,
    bool forceNew = false,
    bool obfuscate = false,
    QuicParams quicParams = const QuicParams(),


    bool? includeReserved,



    int? persistentKeepalive,
    WarpClient? client,
  }) async {
    _busy = true;
    _lastError = null;
    notifyListeners();
    final warp = client ?? WarpClient();
    try {
      WarpAccount? account =
          (reuse && !forceNew) ? await SettingsStorage.getWarpAccount() : null;



      final wantsLicense = licenseKey != null && licenseKey.trim().isNotEmpty;
      if (account != null && wantsLicense && !account.warpPlus) {
        account = null;
      }



      final picker = await WarpEndpointPicker.load();
      final resolvedParams = (quicParams.sni.trim().isEmpty &&
              picker.randomSni().isNotEmpty)
          ? quicParams.copyWith(sni: picker.randomSni())
          : quicParams;


      final userPicked = endpoint != WarpAccount.defaultEndpoint;

      final allowV6 = (await SettingsStorage.getVar('ipv6_enabled', 'false'))
              .toLowerCase() ==
          'true';
      final resolvedEndpoint = userPicked
          ? endpoint
          : (obfuscate
              ? (picker.randomEndpoint(allowV6: allowV6) ?? endpoint)
              : endpoint);

      account ??= await warp.register(
        licenseKey: licenseKey,
        endpoint: resolvedEndpoint,
        nowIso8601: DateTime.now().toUtc().toIso8601String(),
        obfuscate: obfuscate,
        quicParams: resolvedParams,

        randomEndpoint: null,
      );





      if (resolvedEndpoint != account.endpoint &&
          (userPicked || obfuscate)) {
        account = account.copyWith(endpoint: resolvedEndpoint);
      }




      account = _syncWarpObfuscation(account, obfuscate, resolvedParams);

      await SettingsStorage.setWarpAccount(account);




      final tag = _uniqueWarpTag(
          WarpAccount.nodeTag(warpPlus: account.warpPlus, hasAwg: account.awg != null));



      final withReserved = includeReserved ?? !obfuscate;



      if (account.awg != null) {
        await _addWarpObfuscated(account, tag, withReserved,
            persistentKeepalive: persistentKeepalive);
      } else {
        await _addWarpPlain(account, tag, withReserved,
            persistentKeepalive: persistentKeepalive);
      }
      if (_lastError != null) return null;
      return account;
    } catch (e) {
      _lastError = humanizeError(e);
      AppLog.I.error('addWarp failed: ${_lastError?.renderEn()}');
      return null;
    } finally {
      if (client == null) warp.close();
      _busy = false;
      notifyListeners();
    }
  }





  Future<MasqueAccount?> addMasque({
    String vhttp = 'h3',
    String? sni,
    String? idleTimeout,
    String? keepAlive,


    String? server,
    int? port,
    bool reuse = true,
    bool forceNew = false,
    WarpClient? client,
  }) async {
    _busy = true;
    _lastError = null;
    notifyListeners();
    final warp = client ?? WarpClient();
    try {
      MasqueAccount? account = (reuse && !forceNew)
          ? await SettingsStorage.getMasqueAccount()
          : null;

      account ??= await warp.registerMasque(
        nowIso8601: DateTime.now().toUtc().toIso8601String(),
        sni: sni,
        idleTimeout: idleTimeout,
        keepAlive: keepAlive,
      );



      account = account.copyWith(
        sni: sni,
        idleTimeout: idleTimeout,
        keepAlive: keepAlive,
      );

      await SettingsStorage.setMasqueAccount(account);





      final hasServerOverride = server != null && server.trim().isNotEmpty;
      final hasPortOverride = port != null && port > 0;
      if (hasServerOverride || hasPortOverride) {
        account = MasqueAccount(
          privKeyDer: account.privKeyDer,
          serverPubDer: account.serverPubDer,
          clientV4: account.clientV4,
          clientV6: account.clientV6,
          server: hasServerOverride ? server.trim() : account.server,
          port: hasPortOverride ? port : account.port,
          deviceId: account.deviceId,
          token: account.token,
          createdAt: account.createdAt,
          sni: account.sni,
          idleTimeout: account.idleTimeout,
          keepAlive: account.keepAlive,
        );
      }

      final tag = _uniqueWarpTag(MasqueAccount.nodeTag());
      await _addMasqueNode(account, tag, vhttp: vhttp);
      if (_lastError != null) return null;
      return account;
    } catch (e) {
      _lastError = humanizeError(e);
      AppLog.I.error('addMasque failed: ${_lastError?.renderEn()}');
      return null;
    } finally {
      if (client == null) warp.close();
      _busy = false;
      notifyListeners();
    }
  }


  Future<void> _addMasqueNode(MasqueAccount account, String tag,
      {String vhttp = 'h3'}) async {
    final spec =
        parseLinkViaPipeline(account.toMasqueUri(vhttp: vhttp)) as MasqueSpec?;
    if (spec == null) {
      _lastError = const ErrMsg(ErrKey.invalidMasqueConfig);
      return;
    }
    final tagged = MasqueSpec(
      id: spec.id,
      tag: tag,
      label: tag,
      server: spec.server,
      port: spec.port,
      rawSource: spec.rawSource,
      privateKeyDer: spec.privateKeyDer,
      publicKeyDer: spec.publicKeyDer,
      localAddresses: spec.localAddresses,
      profile: spec.profile,
      vhttp: spec.vhttp,
      sni: spec.sni,
      disableSni: spec.disableSni,
      mtu: spec.mtu,
      idleTimeout: spec.idleTimeout,
      keepAlive: spec.keepAlive,
      tlsExtra: spec.tlsExtra,
      warnings: spec.warnings,
    )..bodyDelta = spec.bodyDelta;
    _entries.add(SubscriptionEntry(
      list: UserServer(
        id: newUuidV4(),
        name: '',
        enabled: true,
        tagPrefix: '',
        detourPolicy: DetourPolicy.defaults,
        origin: UserSource.paste,
        rawBody: tagged.toUri(),
        nodes: [tagged],
      ),
      nodeCount: 1,
    ));
    await _persist();
  }






  WarpAccount _syncWarpObfuscation(
      WarpAccount account, bool obfuscate, QuicParams quicParams) {
    if (!obfuscate) {
      return account.awg == null ? account : account.copyWith(clearAwg: true);
    }
    return account.copyWith(awg: WarpClient.buildAmneziaAwg(quicParams));
  }



  String _uniqueWarpTag(String base) {
    final existing = <String>{
      for (final e in _entries)
        if (e.list is UserServer)
          for (final n in (e.list as UserServer).nodes) n.tag,
    };
    if (!existing.contains(base)) return base;
    for (var i = 2;; i++) {
      final candidate = '$base $i';
      if (!existing.contains(candidate)) return candidate;
    }
  }




  Future<void> _addWarpObfuscated(
      WarpAccount account, String tag, bool includeReserved,
      {int? persistentKeepalive}) async {
    final spec = parseWireguardIni(account.toWireguardConf(
        includeReserved: includeReserved,
        persistentKeepalive: persistentKeepalive));
    if (spec == null) {
      _lastError = const ErrMsg(ErrKey.invalidWarpConfigObfuscated);
      return;
    }
    final tagged = WireguardSpec(
      id: spec.id,
      tag: tag,
      label: tag,
      server: spec.server,
      port: spec.port,
      rawSource: spec.rawSource,
      privateKey: spec.privateKey,
      localAddresses: spec.localAddresses,
      peers: spec.peers,
      mtu: spec.mtu,
      awg: spec.awg,
      warnings: spec.warnings,
    )..bodyDelta = spec.bodyDelta;

    _entries.add(SubscriptionEntry(
      list: UserServer(
        id: newUuidV4(),
        name: '',
        enabled: true,
        tagPrefix: '',
        detourPolicy: DetourPolicy.defaults,
        origin: UserSource.paste,
        rawBody: tagged.toUri(),
        nodes: [tagged],
      ),
      nodeCount: 1,
    ));
    await _persist();
  }



  Future<void> _addWarpPlain(
      WarpAccount account, String tag, bool includeReserved,
      {int? persistentKeepalive}) async {
    final spec = parseLinkViaPipeline(account.toWireguardUri(
        includeReserved: includeReserved,
        persistentKeepalive: persistentKeepalive)) as WireguardSpec?;
    if (spec == null) {
      _lastError = const ErrMsg(ErrKey.invalidWarpConfig);
      return;
    }
    final tagged = WireguardSpec(
      id: spec.id,
      tag: tag,
      label: tag,
      server: spec.server,
      port: spec.port,
      rawSource: spec.rawSource,
      privateKey: spec.privateKey,
      localAddresses: spec.localAddresses,
      peers: spec.peers,
      mtu: spec.mtu,
      awg: spec.awg,
      warnings: spec.warnings,
    )..bodyDelta = spec.bodyDelta;
    _entries.add(SubscriptionEntry(
      list: UserServer(
        id: newUuidV4(),
        name: '',
        enabled: true,
        tagPrefix: '',
        detourPolicy: DetourPolicy.defaults,
        origin: UserSource.paste,
        rawBody: tagged.toUri(),
        nodes: [tagged],
      ),
      nodeCount: 1,
    ));
    await _persist();
  }





  UserServer _autoEmoji(UserServer us) {
    if (us.nodes.isEmpty || us.rawBody.isEmpty) return us;
    final newRaw = withDefaultEmoji(us.rawBody, us.nodes.first);
    if (newRaw == us.rawBody) return us;
    try {
      final newNodes = parseAll(decode(newRaw), own: true);
      return newNodes.isEmpty ? us : us.copyWith(rawBody: newRaw, nodes: newNodes);
    } catch (_) {
      return us;
    }
  }


  void _setParseInputReject(
    ErrKey key,
    String input, {
    RegistryWarning? verdict,
    List<NodeWarning>? dropped,
  }) {
    final all = <NodeWarning>[
      ?verdict,
      ...?dropped,
    ];
    final sorted = maskSecretDropWarnings(sortedDropWarnings(all));
    if (sorted.isEmpty) {
      _lastError = ErrMsg(key);
      return;
    }
    _lastError = ParseInputRejectedMsg(
      key,
      dropped: sorted,
      sourceLabel: inputSourceLabel(input),
    );
  }








  Future<void> addFromInput(String input,
      {String? nameHint, UserSource origin = UserSource.paste}) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return;



    if (HateInvitationClient.isLink(trimmed)) {
      _busy = true;
      _lastError = null;
      notifyListeners();
      try {
        final invitation = await HateInvitationClient.resolve(trimmed);
        await addFromInput(invitation.config,
            nameHint: invitation.name, origin: origin);
      } catch (e) {
        _lastError = humanizeError(e);
      } finally {
        _busy = false;
        notifyListeners();
      }
      return;
    }

    _busy = true;
    _lastError = null;
    _lastCommentsRemoved = false;
    notifyListeners();


    final inputPreview = isSubscriptionUrl(trimmed)
        ? maskSubscriptionUrl(trimmed)
        : (trimmed.startsWith('{') || trimmed.startsWith('['))
            ? '<JSON outbound>'
            : '<proxy link>';
    AppLog.I.info('addFromInput: $inputPreview');

    try {
      if (isSubscriptionUrl(trimmed)) {
        final list = SubscriptionServers(
          id: newUuidV4(),
          name: '',
          enabled: true,
          tagPrefix: '',
          detourPolicy: DetourPolicy.defaults,
          url: trimmed,
        );
        _entries.add(SubscriptionEntry(list: list));
        await _persist();
        await _fetchEntry(_entries.length - 1);
      } else if (isWireGuardConfig(trimmed)) {
        final verdict = XrayDropVerdict();
        var spec = parseWireguardIni(trimmed,
            nameHint: nameHint, dropped: verdict);
        if (spec == null) {
          _setParseInputReject(ErrKey.invalidWireguardConfig, trimmed,
              verdict: verdict.reason);
          return;
        }




        if (!hasEmoji(spec.tag)) {
          final emoji = defaultEmojiFor(spec);
          spec = WireguardSpec(
            id: spec.id,
            tag: '$emoji ${spec.tag}',


            label: spec.label.isEmpty ? '' : '$emoji ${spec.label}',
            server: spec.server,
            port: spec.port,
            rawSource: spec.rawSource,
            privateKey: spec.privateKey,
            localAddresses: spec.localAddresses,
            peers: spec.peers,
            mtu: spec.mtu,
            awg: spec.awg,
            warnings: spec.warnings,
          )..bodyDelta = spec.bodyDelta;
        }
        final wgServer = UserServer(
          id: newUuidV4(),
          name: '',
          enabled: true,
          tagPrefix: '',
          detourPolicy: DetourPolicy.defaults,
          origin: origin,
          rawBody: spec.rawSource,
          nodes: [spec],
        );
        _entries.add(SubscriptionEntry(
            list: wgServer, nodeCount: wgServer.nodes.length));
        await _persist();
      } else if (isAmneziaVpnLink(trimmed)) {



        final nodes = parseAll(decode(trimmed));
        if (nodes.isEmpty) {
          _lastError = const ErrMsg(ErrKey.noWgInVpnLink);
          return;
        }
        final vpnServer = _autoEmoji(UserServer(
          id: newUuidV4(),
          name: '',
          enabled: true,
          tagPrefix: '',
          detourPolicy: DetourPolicy.defaults,
          origin: origin,
          rawBody: trimmed,
          nodes: nodes,
        ));
        _entries.add(SubscriptionEntry(
            list: vpnServer, nodeCount: vpnServer.nodes.length));
        await _persist();
      } else if (isDirectLink(trimmed)) {
        final verdict = XrayDropVerdict();
        final spec = parseUri(trimmed, dropped: verdict);
        if (spec == null) {
          _setParseInputReject(ErrKey.couldNotParseDirectLink, trimmed,
              verdict: verdict.reason);
          return;
        }
        final dlServer = _autoEmoji(UserServer(
          id: newUuidV4(),
          name: '',
          enabled: true,
          tagPrefix: '',
          detourPolicy: DetourPolicy.defaults,
          origin: origin,
          rawBody: trimmed,
          nodes: [spec],
        ));
        _entries.add(SubscriptionEntry(
            list: dlServer, nodeCount: dlServer.nodes.length));
        await _persist();
      } else {


        final uncommented = uncommentedJson(trimmed);
        switch (await _addJsonNodes(uncommented ?? trimmed, origin: origin)) {
          case _JsonAdd.added:
            _lastCommentsRemoved = uncommented != null;
            await _persist();
          case _JsonAdd.empty:


            break;
          case _JsonAdd.notJson:
            _lastError = const ErrMsg(ErrKey.inputNotRecognized);
        }
      }
    } catch (e) {
      _lastError = humanizeError(e);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }











  Future<_JsonAdd> _addJsonNodes(String text,
      {UserSource origin = UserSource.paste}) async {
    final decoded = decode(text);










    if (decoded is UriLines && !_looksLikeUriList(text)) {
      return _addUriLines(decoded, text, origin: origin);
    }
    if (decoded is! JsonConfig) return _JsonAdd.notJson;




    if (decoded.source.mapper == null) return _JsonAdd.notJson;

    final dropped = <NodeWarning>[];
    var nodes = parseAll(decoded, dropped: dropped);


    if (nodes.isEmpty) nodes = acceptsOwnUnknownType(decoded) ?? nodes;
    if (nodes.isEmpty) {
      _setParseInputReject(ErrKey.noValidOutboundsInJson, text,
          dropped: dropped);
      return _JsonAdd.empty;
    }







    if (nodes.length > 1 && nodes.any((n) => n is TailscaleSpec)) {
      final rest = textWithoutTailscale(decoded);
      var added = false;
      for (final n in nodes.whereType<TailscaleSpec>()) {
        final srv = _autoEmoji(UserServer(
          id: newUuidV4(),
          name: '',
          enabled: true,
          tagPrefix: '',
          detourPolicy: DetourPolicy.defaults,
          origin: origin,
          rawBody: n.toUri(),
          nodes: [n],
        ));
        _entries.add(SubscriptionEntry(list: srv, nodeCount: 1));
        added = true;
      }
      if (rest != null) {
        final tail = await _addJsonNodes(rest, origin: origin);


        if (tail == _JsonAdd.empty && added) _lastError = null;
      }
      if (added) return _JsonAdd.added;
    }










    if (nodes.length > 1) {
      final url = 'file:${newUuidV4()}';
      await HttpCache.save(url, text, const {});
      final list = SubscriptionServers(
        id: newUuidV4(),
        name: '',
        enabled: true,
        tagPrefix: '',
        detourPolicy: DetourPolicy.defaults,
        url: url,
        lastUpdated: DateTime.now(),
        lastUpdateStatus: UpdateStatus.ok,
        lastNodeCount: nodes.length,
        updateIntervalHours: -1,
        dropped: summaryDropped(dropped),
        nodes: nodes,
      );
      _entries.add(SubscriptionEntry(list: list, nodeCount: nodes.length));
      return _JsonAdd.added;
    }



    var serverRaw = text;
    var serverNodes = nodes;
    if (decoded.source.kind == SourceKind.singboxOutbound) {

      final own = parseAll(decoded, own: true);
      if (own.isNotEmpty) serverNodes = own;
    } else if (decoded.source.mapper == 'singbox') {
      final bare = bareBodyTextOf(nodes.first);
      if (bare != null) {
        final reparsed = parseAll(decode(bare), own: true);
        if (reparsed.isNotEmpty) {
          serverRaw = bare;
          serverNodes = reparsed;
        }
      }
    }
    final jsonServer = _autoEmoji(UserServer(
      id: newUuidV4(),
      name: '',
      enabled: true,
      tagPrefix: '',
      detourPolicy: DetourPolicy.defaults,
      origin: origin,
      rawBody: serverRaw,
      nodes: serverNodes,
    ));
    _entries.add(SubscriptionEntry(
        list: jsonServer, nodeCount: jsonServer.nodes.length));
    return _JsonAdd.added;
  }






  static bool _looksLikeUriList(String text) => text.contains('://');







  Future<_JsonAdd> _addUriLines(UriLines decoded, String text,
      {UserSource origin = UserSource.paste}) async {
    final dropped = <NodeWarning>[];
    final nodes = parseAll(decoded, dropped: dropped);
    if (nodes.isEmpty) {
      _setParseInputReject(ErrKey.noValidOutboundsInJson, text,
          dropped: dropped);
      return _JsonAdd.empty;
    }

    if (nodes.length > 1) {
      final url = 'file:${newUuidV4()}';
      await HttpCache.save(url, text, const {});
      _entries.add(SubscriptionEntry(
        list: SubscriptionServers(
          id: newUuidV4(),
          name: '',
          enabled: true,
          tagPrefix: '',
          detourPolicy: DetourPolicy.defaults,
          url: url,
          lastUpdated: DateTime.now(),
          lastUpdateStatus: UpdateStatus.ok,
          lastNodeCount: nodes.length,
          updateIntervalHours: -1,
          dropped: summaryDropped(dropped),
          nodes: nodes,
        ),
        nodeCount: nodes.length,
      ));
      return _JsonAdd.added;
    }

    final srv = _autoEmoji(UserServer(
      id: newUuidV4(),
      name: '',
      enabled: true,
      tagPrefix: '',
      detourPolicy: DetourPolicy.defaults,
      origin: origin,
      rawBody: text,
      nodes: nodes,
    ));
    _entries.add(SubscriptionEntry(list: srv, nodeCount: srv.nodes.length));
    return _JsonAdd.added;
  }








  final List<NodeLinkNotice> _linkNotices = [];



  List<NodeLinkNotice> takeLinkNotices() {
    if (_linkNotices.isEmpty) return const [];
    final out = List<NodeLinkNotice>.of(_linkNotices);
    _linkNotices.clear();
    return out;
  }



  bool _chainsRelinked = false;


  bool takeChainsRelinked() {
    final v = _chainsRelinked;
    _chainsRelinked = false;
    return v;
  }

  List<ServerList> _lists() => [for (final e in _entries) e.list];









  Future<NodeLinkChange?> _relink(
    List<ServerList> before, {
    Map<NodeSpec, NodeSpec> renamed = const {},
    Set<String> goneContainers = const {},
    NodeLinkSubject? subject,
  }) async {
    final after = _lists();


    await _relinkTailscaleState(before, after, renamed);
    final diff = diffNodeAddresses(before, after, renamed: renamed);
    if (diff.moves.isEmpty && diff.gone.isEmpty && goneContainers.isEmpty) {
      return null;
    }
    final chains = await SettingsStorage.getChains();
    final r = relinkNodeLinks(
      after,
      chains,
      moves: diff.moves,
      gone: diff.gone,
      goneContainers: goneContainers,
    );
    for (var i = 0; i < _entries.length && i < r.lists.length; i++) {
      if (!identical(r.lists[i], after[i])) _entries[i]._replaceList(r.lists[i]);
    }
    if (r.cleared.chainsChanged || r.rewritten.chainsChanged) {
      await SettingsStorage.setChains(r.chains);
      _chainsRelinked = true;
    }
    final cleared = r.cleared;
    if (!cleared.isEmpty) {
      AppLog.I.info('Node links cleared: ${cleared.detourCarriers.length} '
          'detour(s), ${cleared.groupMembers} group member(s), '
          '${cleared.positions} chain position(s)');
      if (subject != null) {
        _linkNotices.add(NodeLinkNotice(subject: subject, change: cleared));
      }
    }
    if (!r.rewritten.isEmpty) {
      AppLog.I.info('Node links rewritten: '
          '${r.rewritten.detourCarriers.length} detour(s), '
          '${r.rewritten.groupMembers} group member(s), '
          '${r.rewritten.positions} chain position(s)');
    }
    return cleared;
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _entries.length) return;
    final before = _lists();
    final gone = _entries.removeAt(index);
    final list = gone.list;


    await _relink(
      before,
      goneContainers: {if (list is! UserServer) list.id},
      subject: NodeLinkSubject.of(list, name: gone.displayName),
    );
    await _persist();
    notifyListeners();
  }

  Future<void> renameAt(int index, String name) async {
    if (index < 0 || index >= _entries.length) return;
    _entries[index]._replaceList(_renameList(_entries[index].list, name));
    await _persist();
    notifyListeners();
  }

  Future<void> updateAt(int index) async {
    if (index < 0 || index >= _entries.length) return;
    final list = _entries[index].list;


    if (list is SubscriptionServers) {
      _autoUpdater?.resetFailCount(list.url);
    }
    await _fetchEntry(index, trigger: UpdateTrigger.manual);
  }





  Future<bool> addFileSubscription(String body, String fileName) async {
    final result = await parseFromSource(InlineSource(body));
    if (result.nodes.length <= 1) return false;

    final url = 'file:${newUuidV4()}';
    await HttpCache.save(url, body, const {});
    final name = result.meta?.profileTitle ?? _stripExt(fileName);
    final list = SubscriptionServers(
      id: newUuidV4(),
      name: name,
      enabled: true,
      tagPrefix: '',
      detourPolicy: DetourPolicy.defaults,
      url: url,
      meta: result.meta,
      lastUpdated: DateTime.now(),
      lastUpdateStatus: UpdateStatus.ok,
      lastNodeCount: result.nodes.length,
      updateIntervalHours: -1,
      dropped: summaryDropped(result.dropped),
      nodes: result.nodes,
    );
    final entry = SubscriptionEntry(list: list, nodeCount: result.nodes.length);
    _entries.add(entry);
    await _persist();
    notifyListeners();
    AppLog.I.info('Added file subscription "$name": ${result.nodes.length} nodes');
    return true;
  }







  Future<UiMsg?> updateSourceAt(int index,
      {String? httpUrl, String? fileBody}) async {
    if (index < 0 || index >= _entries.length) {
      return const ErrMsg(ErrKey.invalidSubscription);
    }
    final entry = _entries[index];
    final old = entry.list;
    if (old is! SubscriptionServers) {
      return const ErrMsg(ErrKey.notASubscription);
    }

    final toFile = fileBody != null;
    final newUrl = toFile ? 'file:${newUuidV4()}' : (httpUrl ?? '').trim();
    if (newUrl.isEmpty) return const ErrMsg(ErrKey.noSourceProvided);

    _busy = true;
    notifyListeners();
    try {


      final result = toFile
          ? await parseFromSource(InlineSource(fileBody))
          : await parseFromSource(UrlSource(newUrl, identity: old.identity),
              client: httpClientForTesting);


      if (result.nodes.isEmpty) {
        return const ErrMsg(ErrKey.couldNotLoadNewSource);
      }


      if (isFileSubscription(newUrl)) {
        await HttpCache.save(newUrl, fileBody!, const {});
      }
      if (old.url != newUrl) {
        await HttpCache.remove(old.url);
      }


      final nextInterval = toFile
          ? -1
          : (old.updateIntervalHours <= 0 ? 24 : old.updateIntervalHours);
      final next = old.copyWith(
        url: newUrl,
        meta: result.meta,
        lastUpdated: DateTime.now(),
        lastUpdateStatus: UpdateStatus.ok,
        lastNodeCount: result.nodes.length,
        consecutiveFails: 0,
        updateIntervalHours: nextInterval,
        dropped: summaryDropped(result.dropped),
        nodes: result.nodes,
      );
      entry._replaceList(next);
      entry.nodeCount = result.nodes.length;
      await _persist();
      notifyListeners();
      AppLog.I.info(
          'Source changed → ${maskSubscriptionUrl(newUrl)}: ${result.nodes.length} nodes');
      return null;
    } catch (e) {
      AppLog.I.warning('updateSourceAt failed (kept current): $e');
      return const ErrMsg(ErrKey.couldNotLoadNewSource);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }


  static String _stripExt(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }


  static String fileBaseName(String fileName) => _stripExt(fileName);





  static String memberNameHintFor(NodeSpec n) =>
      originKindOf(n.rawSource) == 'wg_ini' ? n.tag : '';






  static List<FolderMember> _bindAutoMembers(
    List<FolderMember> added,
    List<NodeSpec> nodes,
    String folderId,
  ) {
    if (nodes.length != added.length || !nodes.any((n) => n.isGroup)) {
      return added;
    }
    final rawTags = sourceNodeRawTags(nodes);
    final memberTag = <String, String>{};
    for (var i = 0; i < nodes.length; i++) {
      final raw = rawTags[nodes[i]];
      final tag = added[i].node?.tag ?? '';
      if (!nodes[i].isGroup && raw != null && tag.isNotEmpty) {
        memberTag[raw] = tag;
      }
    }
    return [
      for (var i = 0; i < added.length; i++)
        switch (nodes[i]) {
          final AutoSelectSpec g => FolderMember.auto(
              g.copyWith(
                membership: switch (g.membership) {
                  ExplicitMembers(:final members) => ExplicitMembers([
                      for (final l in members)
                        if (memberTag[l.tag] case final t?)
                          NodeLink(folderId: folderId, tag: t),
                    ]),
                  final RuleMembers m => m,
                },
              ),
              enabled: added[i].enabled,
            ),
          _ => added[i],
        },
    ];
  }





  static FolderMember _rehomeAutoMember(
      FolderMember m, String fromId, String toId) {
    final g = m.node;
    if (g is! AutoSelectSpec) return m;
    final membership = g.membership;
    if (membership is! ExplicitMembers) return m;
    return FolderMember.auto(
      g.copyWith(
        membership: ExplicitMembers([
          for (final l in membership.members)
            l.isRoot || l.folderId == fromId
                ? NodeLink(folderId: toId, tag: l.tag)
                : l,
        ]),
      ),
      enabled: m.enabled,
    );
  }


  static bool _rawHasOwnName(String raw) {
    final t = raw.trim();
    if (t.startsWith('{')) return t.contains('"tag"');
    return !t.contains('\n') && t.contains('://') && t.contains('#');
  }




  static String rawWithName(String raw, String name) {
    final t = raw.trim();
    if (t.startsWith('{')) {
      try {
        final m = jsonDecode(t);
        if (m is Map<String, dynamic>) {
          m['tag'] = name;
          return jsonEncode(m);
        }
      } catch (_) {}
      return raw;
    }
    if (t.contains('\n') || !t.contains('://')) return raw;
    final hash = t.indexOf('#');
    final base = hash >= 0 ? t.substring(0, hash) : t;
    return '$base#${Uri.encodeComponent(name)}';
  }



  static UserServer _memberToUserServer(FolderMember m) => UserServer(
        id: newUuidV4(),
        name: '',
        enabled: m.enabled,
        tagPrefix: '',
        detourPolicy: m.detour.isEmpty
            ? DetourPolicy.defaults
            : DetourPolicy.defaults.copyWith(overrideDetour: m.detour),

        origin: UserSource.manual,
        rawBody: m.raw,
        skipPresets: m.skipPresets,
        nodes: [if (m.node != null) m.node!],
      );


  Future<void> addFolder(String name) async {
    _entries.add(SubscriptionEntry(
      list: FolderServers(
        id: newUuidV4(),
        name: name,
        enabled: true,
        tagPrefix: '',
        detourPolicy: DetourPolicy.defaults,
      ),
      nodeCount: 0,
    ));
    await _persist();
    notifyListeners();
    AppLog.I.info('Folder created: $name');
  }


  static const kScanFolderName = 'WARP GENERATOR';



  String? lastScanNote;








  Future<int?> generateWarp({
    int seedCount = 100,
    Random? rng,
    WarpClient? client,

    ScanPool? poolOverride,
  }) async {
    lastScanNote = null;
    final pool = poolOverride ?? (await WarpEndpointPicker.load()).scan;
    if (pool == null) return null;




    final warp = client ?? WarpClient();
    ScanNodeBuilder builder;
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      var warpAcc = await SettingsStorage.getWarpAccount();
      warpAcc ??= await _tryRegisterWarp(warp, now);
      var masqueAcc = await SettingsStorage.getMasqueAccount();
      masqueAcc ??= await _tryRegisterMasque(warp, now);
      if (warpAcc == null && masqueAcc == null) return null;


      builder = ScanNodeBuilder(
        warp: warpAcc,
        masque: masqueAcc,
        wgKeepalive: pool.wgKeepalive,
      );
    } finally {
      if (client == null) warp.close();
    }



    final allowV6 =
        (await SettingsStorage.getVar('ipv6_enabled', 'false')).toLowerCase() ==
            'true';
    final gen = CandidateGenerator(pool, rng: rng, allowV6: allowV6);
    final seedUris = _candidatesToUris(gen.seed(seedCount), builder);
    if (seedUris.isEmpty) return null;
    return _recreateScanFolder(seedUris);
  }

  Future<WarpAccount?> _tryRegisterWarp(WarpClient warp, String now) async {
    try {
      final acc = await warp.register(endpoint: WarpAccount.defaultEndpoint, nowIso8601: now);
      await SettingsStorage.setWarpAccount(acc);
      return acc;
    } catch (e) {
      AppLog.I.warning('generateWarp: WARP register failed: $e');
      return null;
    }
  }

  Future<MasqueAccount?> _tryRegisterMasque(WarpClient warp, String now) async {
    try {
      final acc = await warp.registerMasque(nowIso8601: now);
      await SettingsStorage.setMasqueAccount(acc);
      return acc;
    } catch (e) {
      AppLog.I.warning('generateWarp: MASQUE register failed: $e');
      lastScanNote = 'MASQUE (h3/h2) unavailable: registration failed — $e';
      return null;
    }
  }

  List<String> _candidatesToUris(List<ScanCandidate> cs, ScanNodeBuilder b) =>
      [for (final c in cs) b.uriFor(c)].whereType<String>().toList();


  int? _scanFolderIndex() {
    for (var i = 0; i < _entries.length; i++) {
      final l = _entries[i].list;
      if (l is FolderServers && l.name == kScanFolderName) return i;
    }
    return null;
  }




  static const kScanProbeUrl = 'https://1.1.1.1/cdn-cgi/trace';




  Future<int> _recreateScanFolder(List<String> uris) async {
    final old = _scanFolderIndex();
    if (old != null) _entries.removeAt(old);
    _entries.add(SubscriptionEntry(
      list: FolderServers(
        id: newUuidV4(),
        name: kScanFolderName,
        enabled: true,
        tagPrefix: '',
        detourPolicy: DetourPolicy.defaults,
        members: [for (final u in uris) FolderMember(raw: u)],
        pingUrl: kScanProbeUrl,
        pingTimeoutMs: 3000,
      ),
      nodeCount: uris.length,
    ));
    await _persist();
    notifyListeners();
    return _entries.length - 1;
  }





  Future<void> deleteFolderAt(int index, {required bool keepServers}) async {
    if (index < 0 || index >= _entries.length) return;
    final list = _entries[index].list;
    if (list is! FolderServers) return;
    final before = _lists();
    _entries.removeAt(index);
    if (keepServers) {
      _entries.insertAll(
        index,
        list.members.where((m) => m.node?.isGroup != true).map((m) {
          final us = _memberToUserServer(m);
          return SubscriptionEntry(list: us, nodeCount: us.nodes.length);
        }),
      );
    }



    await _relink(
      before,
      goneContainers: {if (!keepServers) list.id},
      subject: NodeLinkSubject.of(list),
    );
    await _persist();
    notifyListeners();
    AppLog.I.info(
        'Folder deleted: ${list.name} (${keepServers ? 'servers kept' : 'servers removed'})');
  }





  Future<UiMsg?> addMembersToFolder(int index, String input,
      {String? nameFallback}) async {
    if (index < 0 || index >= _entries.length) {
      return const ErrMsg(ErrKey.folderNotFound);
    }
    final entry = _entries[index];
    final folder = entry.list;
    if (folder is! FolderServers) return const ErrMsg(ErrKey.notAFolder);

    List<NodeSpec> nodes;


    final dropped = <NodeWarning>[];
    try {


      nodes = parseAll(decode(input.trim()),
          nameHint: nameFallback, dropped: dropped);
    } catch (e) {
      return humanizeError(e);
    }
    if (nodes.isEmpty) {
      final sorted = maskSecretDropWarnings(sortedDropWarnings(dropped));
      if (sorted.isEmpty) return const ErrMsg(ErrKey.noServersFoundInInput);
      return ParseInputRejectedMsg(
        ErrKey.noServersFoundInInput,
        dropped: sorted,
        sourceLabel: inputSourceLabel(input),
      );
    }

    final usedNames = <String>{};
    final added = <FolderMember>[];
    for (final n in nodes) {



      var raw = n.rawSource;
      if (!n.isGroup &&
          nameFallback != null &&
          nameFallback.isNotEmpty &&
          originKindOf(raw) == 'uri' &&
          !_rawHasOwnName(raw)) {
        var candidate = nameFallback;
        var i = 2;
        while (!usedNames.add(candidate)) {
          candidate = '$nameFallback ${i++}';
        }
        raw = rawWithName(raw, candidate);
      }
      added.add(FolderMember(raw: raw, nameHint: memberNameHintFor(n)));
    }
    added.setAll(0, _bindAutoMembers(added, nodes, folder.id));
    entry._replaceList(folder.copyWith(members: [...folder.members, ...added]));
    entry.nodeCount = entry.list.nodes.length;
    await _persist();
    notifyListeners();
    AppLog.I.info('Folder "${folder.name}": +${added.length} servers');
    return null;
  }



  Future<UiMsg?> addUrlSnapshotToFolder(int index, String url) async {
    if (index < 0 || index >= _entries.length) {
      return const ErrMsg(ErrKey.folderNotFound);
    }
    final entry = _entries[index];
    if (entry.list is! FolderServers) return const ErrMsg(ErrKey.notAFolder);
    _busy = true;
    notifyListeners();
    try {
      final result = await parseFromSource(UrlSource(url.trim()),
          client: httpClientForTesting);
      if (result.nodes.isEmpty) {

        final sorted = maskSecretDropWarnings(sortedDropWarnings(result.dropped));
        if (sorted.isEmpty) return const ErrMsg(ErrKey.noServersFoundAtUrl);
        return ParseInputRejectedMsg(
          ErrKey.noServersFoundAtUrl,
          dropped: sorted,
          sourceLabel: inputSourceLabel(url),
        );
      }

      final cur = entry.list;
      if (cur is! FolderServers || !_entries.contains(entry)) {
        return const ErrMsg(ErrKey.folderNotFound);
      }
      final added = _bindAutoMembers(
          result.nodes
              .map((n) => FolderMember(
                  raw: n.rawSource,
                  nameHint: memberNameHintFor(n)))
              .toList(),
          result.nodes,
          cur.id);
      entry._replaceList(cur.copyWith(members: [...cur.members, ...added]));
      entry.nodeCount = entry.list.nodes.length;
      await _persist();
      AppLog.I.info(
          'Folder "${cur.name}": +${added.length} servers (URL snapshot)');
      return null;
    } catch (e) {
      return humanizeError(e);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }








  Future<void> toggleSubscriptionNode(int index, NodeSpec node) async {
    if (index < 0 || index >= _entries.length) return;
    final entry = _entries[index];
    final list = entry.list;
    if (list is! SubscriptionServers) return;


    final hash = sourceNodeIdentities(list.nodes)[node];
    if (hash == null) return;
    final next = Map<String, DateTime>.from(list.disabledHashes);
    final enabling = next.containsKey(hash);
    if (enabling) {
      next.remove(hash);
    } else {
      next[hash] = DateTime.now();
    }



    var nextList = list.copyWith(disabledHashes: next);
    if (enabling) {
      nextList = clearSubscriptionVerdict(nextList, hash);
      unstampCoreRejected(node);
    }
    entry._replaceList(nextList);
    await _persist();
    notifyListeners();
  }








  Future<void> setAllSubscriptionNodes(int index,
      {required bool enabled}) async {
    if (index < 0 || index >= _entries.length) return;
    final entry = _entries[index];
    final list = entry.list;
    if (list is! SubscriptionServers) return;
    final Map<String, DateTime> next;
    if (enabled) {
      if (list.disabledHashes.isEmpty) return;
      next = const {};

      entry._replaceList(list.copyWith(
          disabledHashes: const {}, nodeWarnings: const {}));
      await _persist();
      notifyListeners();
      return;
    } else {
      if (list.nodes.isEmpty) return;
      final now = DateTime.now();
      next = {
        ...list.disabledHashes,


        for (final id in sourceNodeIdentities(list.nodes).values) id: now,
      };
    }
    entry._replaceList(list.copyWith(disabledHashes: next));
    await _persist();
    notifyListeners();
  }






  Future<void> setSubscriptionNodesEnabled(int index, Iterable<NodeSpec> nodes,
      {required bool enabled}) async {
    if (index < 0 || index >= _entries.length) return;
    final entry = _entries[index];
    final list = entry.list;
    if (list is! SubscriptionServers) return;



    final identities = sourceNodeIdentities(list.nodes);
    final hashes = {for (final n in nodes) ?identities[n]};
    if (hashes.isEmpty) return;
    final Map<String, DateTime> next;
    if (enabled) {
      next = Map<String, DateTime>.from(list.disabledHashes)
        ..removeWhere((h, _) => hashes.contains(h));
    } else {
      final now = DateTime.now();
      next = {...list.disabledHashes, for (final h in hashes) h: now};
    }
    entry._replaceList(list.copyWith(disabledHashes: next));
    await _persist();
    notifyListeners();
  }


  Future<void> toggleMemberAt(int index, int memberIndex) async {
    if (index < 0 || index >= _entries.length) return;
    final entry = _entries[index];
    final folder = entry.list;
    if (folder is! FolderServers) return;
    if (memberIndex < 0 || memberIndex >= folder.members.length) return;
    final members = [...folder.members];
    final on = !members[memberIndex].enabled;
    members[memberIndex] = members[memberIndex].copyWith(
      enabled: on,

      warnings: on ? dropVerdict(members[memberIndex].warnings) : null,
    );
    entry._replaceList(folder.copyWith(members: members));
    entry.nodeCount = entry.list.nodes.length;
    await _persist();
    notifyListeners();
  }




  Future<UiMsg?> updateMemberAt(int index, int memberIndex, String newRaw,
      {String? nameHint}) async {
    if (index < 0 || index >= _entries.length) {
      return const ErrMsg(ErrKey.folderNotFound);
    }
    final entry = _entries[index];
    final folder = entry.list;
    if (folder is! FolderServers) return const ErrMsg(ErrKey.notAFolder);
    if (memberIndex < 0 || memberIndex >= folder.members.length) {
      return const ErrMsg(ErrKey.serverNotFound);
    }

    final trimmed = bareNodeSourceOf(newRaw.trim());
    final hint = nameHint ?? folder.members[memberIndex].nameHint;
    final probe = FolderMember(raw: trimmed, nameHint: hint);
    if (probe.node == null) {
      return const ErrMsg(ErrKey.memberParseKeepCurrent);
    }
    final before = _lists();
    final members = [...folder.members];


    final previous = members[memberIndex].node;
    members[memberIndex] = members[memberIndex].copyWith(
      raw: trimmed,
      nameHint: hint,
    );
    var current = members[memberIndex].node;





    if (verdictDroppedByEdit(
      warnings: members[memberIndex].warnings,
      before: previous,
      after: current,
    )) {
      members[memberIndex] = members[memberIndex].copyWith(
        enabled: true,
        warnings: dropVerdict(members[memberIndex].warnings),
      );
      current = members[memberIndex].node;
    }
    entry._replaceList(folder.copyWith(members: members));
    entry.nodeCount = entry.list.nodes.length;

    await _relink(before, renamed: {
      if (previous != null && current != null) previous: current,
    });
    await _persist();
    notifyListeners();
    return null;
  }



  Future<UiMsg?> addAutoMemberToFolder(int index, AutoSelectSpec group) async {
    if (index < 0 || index >= _entries.length) {
      return const ErrMsg(ErrKey.folderNotFound);
    }
    final entry = _entries[index];
    final folder = entry.list;
    if (folder is! FolderServers) return const ErrMsg(ErrKey.notAFolder);
    entry._replaceList(folder.copyWith(
        members: [...folder.members, FolderMember.auto(group)]));
    entry.nodeCount = entry.list.nodes.length;
    await _persist();
    notifyListeners();
    AppLog.I.info('Folder "${folder.name}": +1 auto node');
    return null;
  }



  Future<UiMsg?> updateAutoMemberAt(
      int index, int memberIndex, AutoSelectSpec group) async {
    if (index < 0 || index >= _entries.length) {
      return const ErrMsg(ErrKey.folderNotFound);
    }
    final entry = _entries[index];
    final folder = entry.list;
    if (folder is! FolderServers) return const ErrMsg(ErrKey.notAFolder);
    if (memberIndex < 0 || memberIndex >= folder.members.length) {
      return const ErrMsg(ErrKey.serverNotFound);
    }
    final before = _lists();
    final members = [...folder.members];
    final previous = members[memberIndex].node;
    members[memberIndex] =
        FolderMember.auto(group, enabled: members[memberIndex].enabled);
    entry._replaceList(folder.copyWith(members: members));
    entry.nodeCount = entry.list.nodes.length;

    await _relink(before, renamed: {?previous: group});
    await _persist();
    notifyListeners();
    return null;
  }


  Future<void> removeMemberAt(int index, int memberIndex) async {
    if (index < 0 || index >= _entries.length) return;
    final entry = _entries[index];
    final folder = entry.list;
    if (folder is! FolderServers) return;
    if (memberIndex < 0 || memberIndex >= folder.members.length) return;
    final before = _lists();
    final gone = folder.members[memberIndex];
    final members = [...folder.members]..removeAt(memberIndex);
    entry._replaceList(folder.copyWith(members: members));
    entry.nodeCount = entry.list.nodes.length;


    await _relink(before, subject: NodeLinkSubject.member(folder, gone));
    await _persist();
    notifyListeners();
  }


  Future<void> reorderMember(int index, int from, int to) async {
    if (index < 0 || index >= _entries.length) return;
    final entry = _entries[index];
    final folder = entry.list;
    if (folder is! FolderServers) return;
    if (from < 0 || from >= folder.members.length) return;
    if (to < 0 || to >= folder.members.length) return;
    final before = _lists();
    final members = [...folder.members];
    final m = members.removeAt(from);
    members.insert(to, m);
    entry._replaceList(folder.copyWith(members: members));

    await _relink(before);
    await _persist();
    notifyListeners();
  }




  Future<void> ungroupMemberAt(int index, int memberIndex) async {
    if (index < 0 || index >= _entries.length) return;
    final entry = _entries[index];
    final folder = entry.list;
    if (folder is! FolderServers) return;
    if (memberIndex < 0 || memberIndex >= folder.members.length) return;
    final member = folder.members[memberIndex];
    if (member.node?.isGroup == true) return;
    final before = _lists();
    final members = [...folder.members]..removeAt(memberIndex);
    entry._replaceList(folder.copyWith(members: members));
    entry.nodeCount = entry.list.nodes.length;
    final us = _memberToUserServer(member);
    _entries.insert(
        index + 1, SubscriptionEntry(list: us, nodeCount: us.nodes.length));

    await _relink(before);
    await _persist();
    notifyListeners();
  }





  Future<UiMsg?> setMemberDetour(
      int index, int memberIndex, NodeLink detour) async {
    if (index < 0 || index >= _entries.length) {
      return const ErrMsg(ErrKey.folderNotFound);
    }
    final entry = _entries[index];
    final folder = entry.list;
    if (folder is! FolderServers) return const ErrMsg(ErrKey.notAFolder);
    if (memberIndex < 0 || memberIndex >= folder.members.length) {
      return const ErrMsg(ErrKey.serverNotFound);
    }

    if (detour.isNotEmpty) {


      final raw = <String, int>{};
      for (var k = 0; k < folder.members.length; k++) {
        final a = folderMemberAddress(folder, k);
        if (a != null) raw.putIfAbsent(a.tag, () => k);
      }
      int? intra(NodeLink l) => l.folderId == folder.id ? raw[l.tag] : null;
      final target = intra(detour);
      if (target == memberIndex) {
        return const ErrMsg(ErrKey.detourSelf);
      }
      if (target != null) {
        int? edgeOf(int k) {
          if (k == memberIndex) return target;
          final j = intra(folder.members[k].detour);
          return (j != null && j != k) ? j : null;
        }

        final seen = <int>{};
        int? cur = target;
        while (cur != null && seen.add(cur)) {
          if (cur == memberIndex) {
            return const ErrMsg(ErrKey.detourLoopInFolder);
          }
          cur = edgeOf(cur);
        }
      }
    }

    final members = [...folder.members];
    members[memberIndex] = members[memberIndex].copyWith(detour: detour);
    entry._replaceList(folder.copyWith(members: members));
    await _persist();
    notifyListeners();
    return null;
  }


  Future<void> setMembersEnabled(
      int index, Set<int> memberIndexes, bool enabled) async {
    if (index < 0 || index >= _entries.length) return;
    final entry = _entries[index];
    final folder = entry.list;
    if (folder is! FolderServers) return;
    var changed = false;
    final members = [...folder.members];
    for (final i in memberIndexes) {
      if (i < 0 || i >= members.length) continue;
      if (members[i].enabled == enabled) continue;
      members[i] = members[i].copyWith(enabled: enabled);
      changed = true;
    }
    if (!changed) return;
    entry._replaceList(folder.copyWith(members: members));
    entry.nodeCount = entry.list.nodes.length;
    await _persist();
    notifyListeners();
  }


  Future<void> removeMembersAt(int index, Set<int> memberIndexes) async {
    if (index < 0 || index >= _entries.length) return;
    final entry = _entries[index];
    final folder = entry.list;
    if (folder is! FolderServers) return;
    final members = <FolderMember>[
      for (var i = 0; i < folder.members.length; i++)
        if (!memberIndexes.contains(i)) folder.members[i],
    ];
    if (members.length == folder.members.length) return;
    final before = _lists();
    final gone = [
      for (var i = 0; i < folder.members.length; i++)
        if (memberIndexes.contains(i)) folder.members[i],
    ];
    entry._replaceList(folder.copyWith(members: members));
    entry.nodeCount = entry.list.nodes.length;

    await _relink(
      before,
      subject: gone.length == 1
          ? NodeLinkSubject.member(folder, gone.single)
          : NodeLinkSubject.servers(gone.length),
    );
    await _persist();
    notifyListeners();
  }



  Future<void> applyMembersOrder(int index, List<int> order) async {
    if (index < 0 || index >= _entries.length) return;
    final entry = _entries[index];
    final folder = entry.list;
    if (folder is! FolderServers) return;
    if (order.length != folder.members.length) return;
    if (order.toSet().length != order.length) return;
    if (order.any((i) => i < 0 || i >= folder.members.length)) return;
    final before = _lists();
    entry._replaceList(folder.copyWith(
        members: [for (final i in order) folder.members[i]]));

    await _relink(before);
    await _persist();
    notifyListeners();
  }


  Future<UiMsg?> moveMemberToFolder(
      int fromIndex, int memberIndex, int toIndex) async {
    if (fromIndex < 0 || fromIndex >= _entries.length) {
      return const ErrMsg(ErrKey.folderNotFound);
    }
    if (toIndex < 0 || toIndex >= _entries.length) {
      return const ErrMsg(ErrKey.folderNotFound);
    }
    if (fromIndex == toIndex) return null;
    final fromEntry = _entries[fromIndex];
    final toEntry = _entries[toIndex];
    final from = fromEntry.list;
    final to = toEntry.list;
    if (from is! FolderServers || to is! FolderServers) {
      return const ErrMsg(ErrKey.notAFolder);
    }
    if (memberIndex < 0 || memberIndex >= from.members.length) {
      return const ErrMsg(ErrKey.serverNotFound);
    }
    final before = _lists();
    final moved = from.members[memberIndex];
    final member = _rehomeAutoMember(moved, from.id, to.id);
    final fromMembers = [...from.members]..removeAt(memberIndex);
    fromEntry._replaceList(from.copyWith(members: fromMembers));
    fromEntry.nodeCount = fromEntry.list.nodes.length;
    toEntry._replaceList(to.copyWith(members: [...to.members, member]));
    toEntry.nodeCount = toEntry.list.nodes.length;



    await _relink(before, renamed: {
      if (moved.node != null && member.node != null && moved.node != member.node)
        moved.node!: member.node!,
    });
    await _persist();
    notifyListeners();
    return null;
  }




  Future<UiMsg?> moveServerToFolder(int serverIndex, int folderIndex) async {
    if (serverIndex < 0 || serverIndex >= _entries.length) {
      return const ErrMsg(ErrKey.serverNotFound);
    }
    if (folderIndex < 0 || folderIndex >= _entries.length) {
      return const ErrMsg(ErrKey.folderNotFound);
    }
    final serverEntry = _entries[serverIndex];
    final folderEntry = _entries[folderIndex];
    final server = serverEntry.list;
    final folder = folderEntry.list;
    if (server is! UserServer) {
      return const ErrMsg(ErrKey.onlySingleServersCanBeMoved);
    }
    if (folder is! FolderServers) return const ErrMsg(ErrKey.notAFolder);

    final before = _lists();


    final personalDetour = server.detourPolicy.useDetourServers
        ? server.detourPolicy.overrideDetour
        : NodeLink.none;
    final added = server.nodes.isEmpty

        ? [
            FolderMember(
                raw: server.rawBody,
                enabled: server.enabled,
                detour: personalDetour,
                skipPresets: server.skipPresets),
          ]
        : _bindAutoMembers([
            for (final n in server.nodes)
              FolderMember(
                  raw: n.rawSource,
                  nameHint: memberNameHintFor(n),
                  enabled: server.enabled,
                  detour: personalDetour,

                  skipPresets: server.skipPresets),
          ], server.nodes, folder.id);
    folderEntry._replaceList(
        folder.copyWith(members: [...folder.members, ...added]));
    folderEntry.nodeCount = folderEntry.list.nodes.length;
    _entries.remove(serverEntry);


    await _relink(before, renamed: {
      for (var k = 0; k < server.nodes.length && k < added.length; k++)
        server.nodes[k]: ?added[k].node,
    });
    await _persist();
    notifyListeners();
    AppLog.I.info(
        'Server moved to folder "${folder.name}" (+${added.length})');
    return null;
  }











  Future<bool> refreshEntry(SubscriptionEntry entry,
      {UpdateTrigger? trigger}) =>
      _fetchEntryByRef(entry, trigger: trigger);

  Future<void> toggleAt(int index) async {
    if (index < 0 || index >= _entries.length) return;
    final list = _entries[index].list;
    final enabling = !list.enabled;
    final ServerList next = switch (list) {
      UserServer u when enabling =>
        u.copyWith(enabled: true, warnings: dropVerdict(u.warnings)),
      _ => _toggleEnabled(list, enabling),
    };
    _entries[index]._replaceList(next);
    await _persist();
    notifyListeners();
  }

  Future<void> moveEntry(int from, int to) async {
    if (from < 0 || from >= _entries.length) return;
    if (to < 0 || to >= _entries.length) return;
    final entry = _entries.removeAt(from);
    _entries.insert(to, entry);
    await _persist();
    notifyListeners();
  }









  Future<List<SourceEntry>> sourceEntries() async {
    final disk = await SettingsStorage.getSourceEntries();
    final live = {for (final e in _entries) sourceKeyForIdOf(e.id): e.list};
    final seen = <String>{};
    final out = <SourceEntry>[];
    for (final e in disk) {
      final k = e.sourceKey;
      if (e is ContainerEntry) {
        final l = live[k];


        if (l == null) continue;
        out.add(ContainerEntry(l));
      } else {
        out.add(e);
      }
      seen.add(k);
    }


    for (final e in _entries) {
      if (seen.add(sourceKeyForIdOf(e.id))) out.add(ContainerEntry(e.list));
    }
    return out;
  }











  Future<bool> applySourceOrder(List<String> keys) async {
    if (stale) return false;
    final ok = await SettingsStorage.reorderSources(keys);
    if (!ok) return false;
    final rank = <String, int>{
      for (var i = 0; i < keys.length; i++) keys[i]: i,
    };



    _entries.sort((a, b) =>
        (rank[sourceKeyForIdOf(a.id)] ?? rank.length)
            .compareTo(rank[sourceKeyForIdOf(b.id)] ?? rank.length));
    configDirty = true;
    notifyListeners();
    return true;
  }









  Future<bool> applyEntryOrder(List<String> ids) async {
    final byId = {for (final e in _entries) e.id: e};
    if (ids.length != _entries.length || ids.toSet() != byId.keys.toSet()) {
      AppLog.I.warning('applyEntryOrder rejected: '
          'ids=${ids.length}, entries=${_entries.length}');
      return false;
    }
    _entries
      ..clear()
      ..addAll([for (final id in ids) byId[id]!]);
    await _persist();
    notifyListeners();
    return true;
  }
















  Future<bool> rememberGroupMember(String groupTag, String memberTag,
      {required bool live}) async {
    final group = _lastTagMap[groupTag];
    final member = _lastTagMap[memberTag];
    if (group is! AutoSelectSpec || !group.isManual || member == null) {
      return false;
    }
    for (final e in _entries) {
      final list = e.list;
      ServerList? next;
      switch (list) {
        case SubscriptionServers():
          if (!list.nodes.contains(group) || !list.nodes.contains(member)) {
            continue;
          }
          if (list.groupDefaults[group.tag] == member.tag) return true;
          next = list.copyWith(
              groupDefaults: {...list.groupDefaults, group.tag: member.tag});
        case FolderServers():
          final i = list.members.indexWhere((m) => m.node == group);
          if (i < 0) continue;
          final raw = list.members.firstWhere((m) => m.node == member,
              orElse: () => FolderMember(raw: ''));
          if (raw.node == null) return false;
          final m = list.members[i];
          final members = [...list.members];
          final chosen = group.copyWith(manualDefault: raw.node!.tag);
          members[i] = FolderMember.auto(chosen,
              enabled: m.enabled, warnings: m.warnings);
          next = list.copyWith(members: members);



          _lastTagMap = {..._lastTagMap, groupTag: chosen};
        case UserServer():
          continue;
      }
      e._replaceList(next);
      if (live) {
        _groupDefaultsPending = true;
        await _persist(keepDirtyFlag: true);
      } else {
        await _persist();
      }
      notifyListeners();
      return true;
    }
    return false;
  }









  Future<CoreRejectNodeRef?> disableNodeByCoreTag(String tag, String reason) async {
    final node = _lastTagMap[tag];
    if (node == null) return null;
    for (var i = 0; i < _entries.length; i++) {
      final list = _entries[i].list;
      final ref = nodeRefFor(list, node);
      final applied = applyVerdict(list, node, reason);
      if (!applied.changed) continue;
      _entries[i]._replaceList(applied.list);
      _entries[i].nodeCount = _entries[i].list.nodes.length;


      stampNodeWarnings(
          node, [StoredWarning.coreRejected(reason, ref: ref)]);
      await _persist();
      notifyListeners();
      return ref;
    }
    return null;
  }



  CoreRejectNavigationTarget? resolveCoreRejectNavigation(DisabledNode disabled) =>
      resolveCoreRejectNode(
        [
          for (var i = 0; i < _entries.length; i++)
            (i, _entries[i].id, _entries[i].list),
        ],
        disabled,
        emittedTagMap: _lastTagMap,
      );



  List<({String source, String tag, String reason})> get coreRejectedNodes {
    final out = <({String source, String tag, String reason})>[];
    for (final e in _entries) {
      final list = e.list;

      final source = e.displayName;
      switch (list) {
        case SubscriptionServers():
          for (final w in list.nodeWarnings.entries) {
            for (final v in w.value) {
              if (v.isCoreRejected) {
                out.add((source: source, tag: w.key, reason: v.reason));
              }
            }
          }
        case FolderServers():
          for (final m in list.members) {
            for (final v in m.warnings) {
              if (v.isCoreRejected) {
                out.add((
                  source: source,
                  tag: m.node?.tag ?? m.nameHint,
                  reason: v.reason
                ));
              }
            }
          }
        case UserServer():
          for (final v in list.warnings) {
            if (v.isCoreRejected) {
              out.add((
                source: source,
                tag: list.nodes.isEmpty ? source : list.nodes.first.tag,
                reason: v.reason
              ));
            }
          }
      }
    }
    return out;
  }






  Future<bool> enableNodeByCoreTag(String tag) async {
    final mapped = _lastTagMap[tag];
    if (mapped != null) {
      for (var i = 0; i < _entries.length; i++) {
        final applied = revertVerdict(_entries[i].list, mapped);
        if (!applied.changed) continue;
        _entries[i]._replaceList(applied.list);
        _entries[i].nodeCount = _entries[i].list.nodes.length;
        unstampCoreRejected(mapped);
        await _persist();
        notifyListeners();
        return true;
      }
    }
    for (var i = 0; i < _entries.length; i++) {
      final list = _entries[i].list;
      switch (list) {
        case SubscriptionServers():
          if (!list.nodeWarnings.containsKey(tag) &&
              !list.disabledHashes.containsKey(tag)) {
            continue;
          }
          final disabled = Map<String, DateTime>.from(list.disabledHashes)
            ..remove(tag);
          _entries[i]._replaceList(clearSubscriptionVerdict(
              list.copyWith(disabledHashes: disabled), tag));
        case FolderServers():
          final at = list.members.indexWhere(
              (m) => (m.node?.tag ?? m.nameHint) == tag);
          if (at < 0) continue;
          final members = [...list.members];
          members[at] = members[at]
              .copyWith(enabled: true, warnings: dropVerdict(members[at].warnings));
          _entries[i]._replaceList(list.copyWith(members: members));
        case UserServer():
          final own = list.nodes.isEmpty ? list.name : list.nodes.first.tag;
          if (own != tag) continue;
          _entries[i]._replaceList(
              list.copyWith(enabled: true, warnings: dropVerdict(list.warnings)));
      }
      _entries[i].nodeCount = _entries[i].list.nodes.length;
      await _persist();
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> replaceList(int index, ServerList next) async {
    if (index < 0 || index >= _entries.length) return;
    _entries[index]._replaceList(next);
    await _persist();
    notifyListeners();
  }

  Future<String?> generateConfig() async {




    if (await SettingsStorage.getConfigLockedForDebug()) {
      AppLog.I.info('generateConfig: skipped (config_locked_for_debug=true)');


      _lastFatalIssues = const [];
      return null;
    }
    _busy = true;
    _generating = true;
    _lastError = null;
    _lastFatalIssues = const [];
    notifyListeners();






    final before = _compositionSignature();
    try {
      final config = await _generate();
      _lastGeneratedConfig = config;
      if (_compositionSignature() == before) {
        configDirty = false;
      } else {
        AppLog.I.info(
            '§360: entries changed during rebuild — configDirty kept');
      }
      return config;
    } catch (e) {
      _lastError = humanizeError(e);

      if (e is FatalValidationException) _lastFatalIssues = e.issues;
      return null;
    } finally {
      _busy = false;
      _generating = false;
      _progressMessage = null;
      notifyListeners();
    }
  }



  static String? _filesDirCache;


  @visibleForTesting
  static set debugTailscaleStateRoot(String? root) => _filesDirCache = root;


  @visibleForTesting
  static Future<bool> Function()? debugCoreStopped;



  static Future<bool> _coreStopped() async {
    final override = debugCoreStopped;
    if (override != null) return override();
    try {
      final status = await BoxVpnClient().getVpnStatus();
      return status == TunnelStatus.disconnected ||
          status == TunnelStatus.revoked;
    } catch (_) {
      return false;
    }
  }




  Future<Map<NodeSpec, String>?> _prepareTailscaleState(
      String root, List<ServerList> lists) async {
    if (root.isEmpty) return null;
    try {
      final m = await WorkspaceStore.I.readManifest();
      return await TailscaleStateStore.I.prepareForBuild(
        root: root,
        slot: m.current,
        slotNames: m.names,
        lists: lists,
        coreStopped: _coreStopped,
      );
    } catch (e) {
      AppLog.I.warning('Tailscale state index unavailable: $e');
      return null;
    }
  }



  Future<void> _relinkTailscaleState(
    List<ServerList> before,
    List<ServerList> after,
    Map<NodeSpec, NodeSpec> renamed,
  ) async {
    if (!hasTailscaleNodes(before) && !hasTailscaleNodes(after)) return;
    final root = await _tailscaleStateRoot();
    if (root.isEmpty) return;
    try {
      final m = await WorkspaceStore.I.readManifest();
      await TailscaleStateStore.I.relink(
        root: root,
        slot: m.current,
        slotNames: m.names,
        before: before,
        after: after,
        renamed: renamed,
        coreStopped: _coreStopped,
      );
    } catch (e) {
      AppLog.I.warning('Tailscale state relink failed: $e');
    }
  }
  Future<String> _tailscaleStateRoot() async {
    final cached = _filesDirCache;
    if (cached != null) return cached;
    try {
      final native = await BoxVpnClient().getFilesDir();
      if (native != null && native.isNotEmpty) {
        _filesDirCache = native;
        return native;
      }
    } catch (_) {

    }
    return '';
  }




  Future<UiMsg?> setSkipPresets(int index, int? memberIndex, bool value) async {
    if (index < 0 || index >= _entries.length) {
      return const ErrMsg(ErrKey.serverNotFound);
    }
    final entry = _entries[index];
    final list = entry.list;
    if (memberIndex == null) {
      if (list is! UserServer) return const ErrMsg(ErrKey.serverNotFound);
      if (list.skipPresets == value) return null;
      entry._replaceList(list.copyWith(skipPresets: value));
    } else {
      if (list is! FolderServers) return const ErrMsg(ErrKey.notAFolder);
      if (memberIndex < 0 || memberIndex >= list.members.length) {
        return const ErrMsg(ErrKey.serverNotFound);
      }
      final members = [...list.members];
      if (members[memberIndex].skipPresets == value) return null;
      members[memberIndex] = members[memberIndex].copyWith(skipPresets: value);
      entry._replaceList(list.copyWith(members: members));
    }
    await _persist();
    notifyListeners();
    return null;
  }

  Future<String> _generate() async {
    AppLog.I.info('Generating config...');
    _progressMessage = const SubStatusBuildingConfig();
    notifyListeners();





    final originals = Map<NodeSpec, NodeSpec>.identity();
    final lists = <ServerList>[];
    for (final e in _entries) {
      final l = e.list;
      if (l is SubscriptionServers && l.groupDefaults.isNotEmpty) {
        final applied = l.withGroupDefaultsApplied();
        for (var k = 0; k < l.nodes.length; k++) {
          originals[applied.nodes[k]] = l.nodes[k];
        }
        lists.add(applied);
      } else {
        lists.add(l);
      }
    }


    final tailscaleStateRoot = await _tailscaleStateRoot();



    await SettingsStorage.seedLateDefaultPresets();

    final settings = BuildSettings(
      userVars: await SettingsStorage.getAllVars(),
      enabledGroups: await SettingsStorage.getEnabledGroups(),
      customRules: await SettingsStorage.getCustomRules(),
      routeFinal: await SettingsStorage.getRouteFinal(),
      directions: await SettingsStorage.getDirections(),
      chains: await SettingsStorage.getChains(),





      coreVersion:
          await CoreVersionCache.ensure(BoxVpnClient().getCoreVersion),
      tunApps: await SettingsStorage.getTunApps(),
      vpnMode: await SettingsStorage.getVpnMode(),
      idleSuspend: await SettingsStorage.getIdleSuspend(),
      idleSuspendReachable:
          await SettingsStorage.getIdleSuspendReachable(),
      wgBuildMax: await SettingsStorage.getWgBuildMax(),
      wgLazyBuild: await SettingsStorage.getWgLazyBuild(),
      passiveCheck: await SettingsStorage.getPassiveCheck(),
      tailscaleStateRoot: tailscaleStateRoot,

      tailscaleStateDirs:
          await _prepareTailscaleState(tailscaleStateRoot, lists),
    );

    final result = await buildConfig(lists: lists, settings: settings);
    _lastTagMap = originals.isEmpty
        ? result.nodeByEmittedTag
        : {
            for (final e in result.nodeByEmittedTag.entries)
              e.key: originals[e.value] ?? e.value,
          };
    _groupDefaultsPending = false;
    _lastBuildWarningsByTag = result.nodeBuildWarningsByEmittedTag;




    for (final e in result.generatedVars.entries) {
      await SettingsStorage.setVar(e.key, e.value);
    }

    final outs = (result.config['outbounds'] as List?)?.length ?? 0;
    final eps = (result.config['endpoints'] as List?)?.length ?? 0;
    AppLog.I.info('Config built: $outs outbounds + $eps endpoints, ${lists.length} lists');
    for (final w in result.emitWarnings) {
      AppLog.I.warning(w);
    }






    if (result.validation.hasFatal) {
      final fatal = result.validation.fatal;
      for (final issue in fatal) {
        AppLog.I.error('Validation: ${issue.renderEn()}');
      }
      throw FatalValidationException(fatal);
    }



    _directionsWithoutNodes = result.directionsWithoutNodes;
    if (_directionsWithoutNodes.isNotEmpty) {
      _directionsWithoutNodesStamp++;
      notifyListeners();
    }
    _templateWarnings = result.templateWarnings;
    if (_templateWarnings.isNotEmpty) {
      _templateWarningsStamp++;
      notifyListeners();
    }
    return result.configJson;
  }

  Future<bool> _fetchEntry(int index, {UpdateTrigger? trigger}) async {
    if (index < 0 || index >= _entries.length) return false;
    return _fetchEntryByRef(_entries[index], trigger: trigger);
  }












  Future<bool> _fetchEntryByRef(SubscriptionEntry entry,
      {UpdateTrigger? trigger}) async {
    final list = entry.list;
    if (list is! SubscriptionServers) return false;






    if (isFileSubscription(list.url)) {
      AppLog.I.debug('Skip fetch (file subscription): keeping cached nodes');
      return false;
    }






    if (list.lastUpdateStatus == UpdateStatus.inProgress) {
      AppLog.I.debug(
          'Fetch skipped — already inProgress: ${maskSubscriptionUrl(list.url)}');
      return false;
    }




    final shortUrl = maskSubscriptionUrl(list.url);
    final triggerName = trigger?.name ?? 'manual';
    AppLog.I.info('Fetching subscription [$triggerName]: $shortUrl');
    final attemptAt = DateTime.now();
    var compositionChanged = false;
    try {
      entry.status = const SubStatusFetching();









      entry._replaceList(list.copyWith(
        lastUpdateAttempt: attemptAt,
        lastUpdateStatus: UpdateStatus.inProgress,
      ));
      await _persist(keepDirtyFlag: true);
      notifyListeners();




      final result = await parseFromSource(
          UrlSource(list.url, identity: list.identity),
          client: httpClientForTesting);




      if (stale) {
        AppLog.I.warning(
            'workspaces: fetch result dropped — workspace switched: $shortUrl');
        return false;
      }
      AppLog.I.info(
          'Fetched ${result.nodes.length} nodes from $shortUrl'
          '${result.meta?.profileTitle == null ? "" : " (title: ${result.meta!.profileTitle})"}');





      if (result.nodes.isEmpty) {
        final hint = diagnoseEmptyParse(result.rawBody);
        if (hint != null) AppLog.I.warning('Parse hint: $hint');
        AppLog.I.warning(
            'Fetch returned 0 nodes for $shortUrl — keeping previous state');
        entry.status = entry.nodeCount > 0
            ? SubStatusUpdateFailed(entry.nodeCount, zeroParsed: true)
            : SubStatusZeroNodes(hint);
        final current = entry.list as SubscriptionServers;
        entry._replaceList(current.copyWith(
          lastUpdateAttempt: attemptAt,
          lastUpdateStatus: UpdateStatus.failed,
          consecutiveFails: current.consecutiveFails + 1,




          dropped: summaryDropped(result.dropped),
        ));
        try {




          await _persist(keepDirtyFlag: true);
        } catch (e) {



          AppLog.I.error(
              'Persist failed after empty fetch: ${humanizeError(e).renderEn()}');
        }
        if (trigger == UpdateTrigger.manual) HapticService.I.onFetchError();

        AutomationEventEmitter.I
            .emitSubRefreshFailed(shortUrl, '0 nodes parsed');
        notifyListeners();
        return false;
      }




      final saveFuture = HttpCache.save(list.url, result.rawBody, result.headers);
      lastCacheSaveForTesting = saveFuture;
      unawaited(saveFuture);
      final warnNodes = result.nodes.where((n) => n.warnings.isNotEmpty).length;
      if (warnNodes > 0) {
        AppLog.I.warning('$warnNodes nodes with warnings (XHTTP fallback etc.)');
      }
      entry.nodeCount = result.nodes.length;
      final detours = result.nodes.where((n) => n.chained != null).length;
      entry.status = SubStatusNodes(result.nodes.length, detours: detours);

      final current = entry.list as SubscriptionServers;
      final nextName = current.name.isEmpty && result.meta?.profileTitle != null
          ? result.meta!.profileTitle!
          : current.name;






      final nextInterval = current.updateIntervalHours < 0
          ? current.updateIntervalHours
          : (result.meta?.updateIntervalHours ?? current.updateIntervalHours);









      final ruleNow = DateTime.now();
      final ruleMarks =
          _applyRulesToNodes(result.nodes, current.activeImportRules);







      final migrated =
          migrateLegacyDisabledKeys(current.disabledHashes, result.nodes);






      final freshIdentities = sourceNodeIdentities(result.nodes).values.toSet();
      final baseDisabled = migrated.isEmpty && ruleMarks.disable.isEmpty
          ? migrated
          : gcDisabledHashes(
              migrated,
              freshIdentities,
              updateIntervalHours: nextInterval,
              now: ruleNow,
            );


      final nextDisabled = applyRuleMarks(
        baseDisabled,
        enable: ruleMarks.enable,
        disable: ruleMarks.disable,
        now: ruleNow,
      );




      final gcWarnings = gcNodeWarnings(
        current.nodeWarnings,
        nextDisabled,
        freshIdentities,
      );
      final verdicts = refreshSubscriptionVerdicts(
        disabled: nextDisabled,
        warnings: gcWarnings,
        oldBodies: bodiesByIdentity(current.nodes),
        newBodies: bodiesByIdentity(result.nodes),
      );

      stampStoredVerdicts(result.nodes, verdicts.warnings);

      final next = current.copyWith(
        name: nextName,
        meta: result.meta,
        lastUpdated: DateTime.now(),
        lastUpdateAttempt: attemptAt,
        lastUpdateStatus: UpdateStatus.ok,
        lastNodeCount: result.nodes.length,
        consecutiveFails: 0,
        updateIntervalHours: nextInterval,
        disabledHashes: verdicts.disabled,
        nodeWarnings: verdicts.warnings,
        dropped: summaryDropped(result.dropped),
        nodes: result.nodes,
      );
      entry._replaceList(next);










      final sameComposition = _compositionKey(current.nodes, current.disabledHashes.keys) ==
          _compositionKey(result.nodes, verdicts.disabled.keys);





      final affectsConfig = current.enabled;





      await _persist(keepDirtyFlag: sameComposition || !affectsConfig);
      compositionChanged = !sameComposition;
      if (sameComposition) {
        AppLog.I.debug('§331: composition unchanged for $shortUrl');
      }









      if (trigger == UpdateTrigger.manual && !sameComposition && affectsConfig) {
        switch (next.onUpdateAction) {
          case SubscriptionOnUpdateAction.reload:
            await _autoUpdater?.applyReaction(reload: true);
          case SubscriptionOnUpdateAction.rebuild:
            await _autoUpdater?.applyReaction(reload: false);
          case SubscriptionOnUpdateAction.none:
            break;
        }
      }

      if (trigger == UpdateTrigger.manual) HapticService.I.onFetchSuccess();



      AutomationEventEmitter.I.emitSubRefreshed(
        shortUrl,
        result.nodes.length,
        result.nodes.length - current.lastNodeCount,
      );
    } catch (e) {
      AppLog.I.error('Fetch failed for $shortUrl: $e');
      entry.status = entry.nodeCount > 0
          ? SubStatusUpdateFailed(entry.nodeCount)
          : PrefixedMsg(ErrPrefix.error, RawMsg('$e'));



      final current = entry.list;
      if (current is SubscriptionServers) {
        entry._replaceList(current.copyWith(
          lastUpdateAttempt: attemptAt,
          lastUpdateStatus: UpdateStatus.failed,
          consecutiveFails: current.consecutiveFails + 1,
        ));


        await _persist(keepDirtyFlag: true);
      }
      if (trigger == UpdateTrigger.manual) HapticService.I.onFetchError();


      AutomationEventEmitter.I
          .emitSubRefreshFailed(shortUrl, humanizeError(e).renderEn());
    }
    notifyListeners();
    return compositionChanged;
  }

  Future<void> persistSources() async {
    configDirty = true;
    await _persist();
  }





  Future<void> relinkServerTagPrefix(
      SubscriptionEntry entry, String oldPrefix) async {
    final list = entry.list;
    if (list is! UserServer || list.tagPrefix == oldPrefix) return;
    final index = _entries.indexOf(entry);
    if (index < 0) return;
    final before = _lists();
    before[index] = list.copyWith(tagPrefix: oldPrefix);
    if (await _relink(before) == null) return;
    await _persist();
    notifyListeners();
  }




  Future<void> updateConnectionAt(int index, List<String> connections,
      {String? nameHint}) async {
    if (index < 0 || index >= _entries.length) return;
    final list = _entries[index].list;
    if (list is! UserServer) return;



    final sources = [for (final c in connections) bareNodeSourceOf(c)];
    final nodes = <NodeSpec>[];
    for (final c in sources) {
      final decoded = decode(c);
      nodes.addAll(parseAll(decoded, nameHint: nameHint, own: true));
    }
    final before = _lists();





    final dropVerdictByEdit = verdictDroppedByEdit(
      warnings: list.warnings,
      before: list.nodes.isEmpty ? null : list.nodes.first,
      after: nodes.isEmpty ? null : nodes.first,
    );
    final next = list.copyWith(


      name: '',
      rawBody: sources.join('\n'),
      nodes: nodes,
      enabled: dropVerdictByEdit ? true : null,
      warnings: dropVerdictByEdit ? dropVerdict(list.warnings) : null,


    );
    _entries[index]._replaceList(next);
    _entries[index].nodeCount = nodes.length;
    _entries[index].status = const SubStatusJsonOutbound();


    await _relink(before, renamed: {
      for (var k = 0; k < list.nodes.length && k < nodes.length; k++)
        list.nodes[k]: nodes[k],
    });
    await _persist();
    notifyListeners();
  }




















  @visibleForTesting
  static String compositionKeyForTesting(
    List<NodeSpec> nodes,
    Iterable<String> disabledHashes,
  ) =>
      _compositionKey(nodes, disabledHashes);

  static String _compositionKey(
    List<NodeSpec> nodes,
    Iterable<String> disabledHashes,
  ) {




    String lenPrefixed(Iterable<String> items) =>
        items.map((s) => '${s.length}:$s').join();





    final tags = lenPrefixed([
      for (final n in nodes) '${n.tag}\u0000${legacyNodeIdentityHash(n)}',
    ]);
    final disabled = lenPrefixed(disabledHashes.toList()..sort());
    return '$tags|$disabled';
  }









  String _compositionSignature() {
    final parts = _entries.map((e) {
      final l = e.list;


      final nodes = l.nodes.map(legacyNodeIdentityHash).join(',');
      return '${l.id}:${l.enabled ? 1 : 0}:$nodes';
    });
    return parts.map((s) => '${s.length}:$s').join();
  }




























  Future<void> _persist({bool keepDirtyFlag = false}) async {
    if (stale) {
      AppLog.I.warning('workspaces: persist skipped — controller from '
          'generation $_bornGeneration, current '
          '${WorkspaceController.I.generation}'
          '${_disposed ? ' (disposed)' : ''}');
      return;
    }
    if (!_generating && !keepDirtyFlag) configDirty = true;
    await SettingsStorage.saveServerLists(_entries.map((e) => e.list).toList());
  }








  void syncDetourDirectionRefsCleared(String tag) {
    var changed = false;
    for (final e in _entries) {
      final r = clearDetourDirectionRefs(e.list, tag);
      if (r.healed != null) {
        e._replaceList(r.healed!);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  ServerList _renameList(ServerList l, String name) => switch (l) {
        SubscriptionServers() => l.copyWith(name: name),
        UserServer() => l.copyWith(name: name),
        FolderServers() => l.copyWith(name: name),
      };

  ServerList _toggleEnabled(ServerList l, bool enabled) => switch (l) {
        SubscriptionServers() => l.copyWith(enabled: enabled),
        UserServer() => l.copyWith(enabled: enabled),
        FolderServers() => l.copyWith(enabled: enabled),
      };
}


final class NodeLinkSubject {
  const NodeLinkSubject._(this.kind, this.name, [this.count = 1]);



  factory NodeLinkSubject.of(ServerList list, {String? name}) =>
      switch (list) {
        UserServer u => NodeLinkSubject._(
            NodeLinkSubjectKind.server,
            u.nodes.isNotEmpty
                ? containerFinalForm(u, u.nodes.first.tag)
                : (name ?? u.name),
          ),
        SubscriptionServers s => NodeLinkSubject._(
            NodeLinkSubjectKind.subscription, name ?? s.name),
        FolderServers f =>
          NodeLinkSubject._(NodeLinkSubjectKind.folder, f.name),
      };


  factory NodeLinkSubject.member(FolderServers folder, FolderMember m) =>
      NodeLinkSubject._(
        NodeLinkSubjectKind.server,
        m.node == null ? '' : containerFinalForm(folder, m.node!.tag),
      );


  factory NodeLinkSubject.servers(int count) =>
      NodeLinkSubject._(NodeLinkSubjectKind.servers, '', count);

  final NodeLinkSubjectKind kind;
  final String name;
  final int count;
}

enum NodeLinkSubjectKind { server, subscription, folder, servers }


final class NodeLinkNotice {
  const NodeLinkNotice({required this.subject, required this.change});

  final NodeLinkSubject subject;
  final NodeLinkChange change;
}
