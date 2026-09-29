import 'dart:async';
import '../models/node_spec.dart';
import '../services/node_identity.dart';
import 'auto_group_edit_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/subscription_controller.dart';
import '../controllers/subscription_controller/core_reject_ops.dart';
import '../models/direction.dart';
import '../models/node_warning.dart';
import '../models/node_link.dart';
import '../models/server_list.dart';
import '../services/error_format.dart';
import '../services/node_link_address.dart';
import '../services/probe/probe_controller.dart';
import '../services/probe/probe_runner.dart';
import 'probe_gate_mixin.dart';
import '../services/settings_storage.dart';
import '../services/subscription/input_helpers.dart';
import 'home/filter_widgets.dart';
import 'node_settings_screen.dart';
import 'home/node_list_presenter.dart' show protoLabel;
import 'subscription_detail_screen/detour_mode.dart';
import 'subscription_detail_screen/tag_prefix_cascade.dart';
import 'subscription_detail_screen/widgets/subscription_settings_tab.dart';
import 'subscriptions_screen/folder_picker.dart';
import '../widgets/detour_target_picker.dart';
import '../widgets/probe_badge.dart';
import 'subscription_detail_screen/widgets/node_warning_row.dart';
import 'subscriptions_screen/entry_warnings.dart';
import '../widgets/reorder_grab_strip.dart';
import '../services/l10n/locale_controller.dart';
import '../services/file_import.dart';
import '../widgets/app_bottom_sheet.dart';




class FolderDetailScreen extends StatefulWidget {
  const FolderDetailScreen({
    super.key,
    required this.entry,
    required this.controller,
    this.focusMemberIndex,
  });

  final SubscriptionEntry entry;
  final SubscriptionController controller;



  final int? focusMemberIndex;

  @override
  State<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends State<FolderDetailScreen>
    with SingleTickerProviderStateMixin, ProbeGateMixin<FolderDetailScreen> {
  late final TabController _tabCtrl;
  bool _editing = false;
  late TextEditingController _nameCtrl;





  final Map<String, ProbeResult> _probe = {};
  ProbeRunner? _runner;



  Timer? _probeFlushTimer;
  bool _testing = false;
  ProbeThresholds _thresholds = const ProbeThresholds();



  final _filterRegexCtl = TextEditingController();
  bool _filterExpanded = false;
  bool _regexInvert = false;
  final Set<String> _selectedProtocols = {};
  bool _protocolsInvert = false;



  List<Direction> _directions = const [];




  late String _committedTagPrefix;

  FolderServers get _folder => widget.entry.list as FolderServers;





  final _scrollController = ScrollController();
  final _memberKeys = <int, GlobalKey>{};
  int? _highlightedMember;
  Timer? _highlightTimer;

  GlobalKey _memberKey(int i) => _memberKeys.putIfAbsent(i, GlobalKey.new);




  Set<String> _chainLinkTags() {
    final folder = _folder;
    final bareByAddress = <NodeLink, String>{};
    for (var k = 0; k < folder.members.length; k++) {
      final a = folderMemberAddress(folder, k);
      if (a != null) bareByAddress[a] = folder.members[k].node!.tag;
    }
    final links = <String>{};
    for (var k = 0; k < folder.members.length; k++) {
      final d = folder.members[k].detour;
      if (d.isEmpty || d.folderId != folder.id) continue;
      final bare = bareByAddress[d];
      if (bare == null) continue;
      if (d == folderMemberAddress(folder, k)) continue;
      links.add(bare);
    }
    return links;
  }


  int get _index => widget.controller.entries.indexOf(widget.entry);







  bool _leaving = false;

  void _onEntriesChanged() {
    if (_leaving || _index >= 0) return;
    _leaving = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null || !route.isActive) return;
      if (route.isCurrent) {
        Navigator.pop(context);
      } else {


        Navigator.of(context).removeRoute(route);
      }
    });


    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _nameCtrl = TextEditingController(text: widget.entry.name);
    _committedTagPrefix = widget.entry.tagPrefix;
    widget.controller.addListener(_onEntriesChanged);
    unawaited(_loadThresholds());
    unawaited(_loadDirections());
    final focus = widget.focusMemberIndex;
    if (focus != null && focus >= 0 && focus < _folder.members.length) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _focusMember(focus, attempt: 0));
    }
  }





  void _focusMember(int i, {required int attempt}) {
    if (!mounted) return;
    if (attempt == 0) setState(() => _highlightedMember = i);
    const maxAttempts = 6;
    final ctx = _memberKeys[i]?.currentContext;
    if (ctx != null) {
      unawaited(Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: 0.3));
    } else if (attempt < maxAttempts && _scrollController.hasClients) {


      final target = (i * 64.0)
          .clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.jumpTo(target);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _focusMember(i, attempt: attempt + 1));
      return;
    }
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _highlightedMember = null);
    });
  }



  Future<void> _commitTagPrefix() async {
    final oldPrefix = _committedTagPrefix;
    final newPrefix = widget.entry.tagPrefix;
    if (oldPrefix == newPrefix) return;
    _committedTagPrefix = newPrefix;
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

  @override
  void dispose() {
    widget.controller.removeListener(_onEntriesChanged);

    _runner?.cancel();
    _probeFlushTimer?.cancel();
    _probeFlushTimer = null;
    _tabCtrl.dispose();
    _nameCtrl.dispose();
    _filterRegexCtl.dispose();
    _scrollController.dispose();
    _highlightTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadThresholds() async {
    final t = await ProbeController.loadThresholds();
    if (!mounted) return;
    setState(() => _thresholds = t);
  }





  void _scheduleProbeFlush() {
    if (_probeFlushTimer != null) return;
    _probeFlushTimer = Timer(const Duration(milliseconds: 120), () {
      _probeFlushTimer = null;
      if (mounted) setState(() {});
    });
  }

  Future<void> _toggleTest() async {
    if (_testing) {
      _runner?.cancel();
      _probeFlushTimer?.cancel();
      _probeFlushTimer = null;
      setState(() => _testing = false);
      return;
    }
    if (_folder.members.isEmpty) return;



    if (await ensureVpnStoppedForProbe()) {
      await _runProbe();
    }
  }



  Future<void> _runProbe() async {
    if (_folder.members.isEmpty) return;


    final (:url, :timeoutMs) = await ProbeController.resolvePingOptions(
      overrideUrl: _folder.pingUrl,
      overrideTimeoutMs: _folder.pingTimeoutMs,
    );
    if (!mounted) return;



    final probeKeys = _memberProbeKeys();
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
    _runner = runner;



    final err = await runner.run(
      [for (final m in _folder.members) m.node],
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
      await _showError(err);
      return;
    }
  }



  void _showTestSettings() {
    showAppBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(getLocalText.s("Ping URL & timeout…")),
              subtitle: Text(getLocalText.s("Shared with the home screen ping")),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_editPingTarget());
              },
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: Text(getLocalText.s("Ping color thresholds…")),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_editThresholds());
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editPingTarget() async {
    final target = await ProbeController.globalPingTarget();
    if (!mounted) return;
    final urlCtl = TextEditingController(text: target.url);
    final timeoutCtl = TextEditingController(text: '${target.timeoutMs}');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(getLocalText.s("Ping target")),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlCtl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: getLocalText.s("Test URL"),
                hintText: getLocalText.s("empty = core default"),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: timeoutCtl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: getLocalText.s("Timeout, ms"),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(getLocalText.s("Cancel"))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(getLocalText.s("Save"))),
        ],
      ),
    );
    final url = urlCtl.text.trim();
    final timeout = int.tryParse(timeoutCtl.text.trim());
    urlCtl.dispose();
    timeoutCtl.dispose();
    if (saved != true || !mounted) return;
    await ProbeController.saveGlobalPing(url, timeoutMs: timeout);
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

  Future<void> _disableSlowerThan() async {
    final ctl = TextEditingController(text: '${_thresholds.orangeMs}');
    final ms = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(getLocalText.s("Disable slow servers")),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: getLocalText.s("Slower than, ms"),
            border: const OutlineInputBorder(),
          ),
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
      await _showError(getLocalText.s("No tested servers slower than %d ms", ms));
      return;
    }
    final idx = _index;
    if (idx < 0) return;
    await widget.controller.setMembersEnabled(idx, slow, false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(getLocalText.plural("Disabled %1\$d servers > %2\$d ms", slow.length, ms))),
    );
    setState(() {});
  }





  List<FolderMember>? _probeKeysFor;
  List<String> _probeKeysCache = const [];
  List<String> _memberProbeKeys() {
    final members = _folder.members;
    if (!identical(_probeKeysFor, members)) {
      _probeKeysFor = members;
      _probeKeysCache = ProbeController.probeKeys(members);
    }
    return _probeKeysCache;
  }






  Map<int, ProbeResult> _probeByIndex() {
    final keys = _memberProbeKeys();
    return {
      for (var i = 0; i < keys.length; i++) i: ?_probe[keys[i]],
    };
  }



  bool get _hasProbeVerdict =>
      _probe.values.any((r) => r.status != ProbeStatus.pending &&
          r.status != ProbeStatus.group);


  Set<int> _unreachableIndexes() =>
      ProbeController.unreachableIndexes(_probeByIndex());



  Future<void> _disableUnreachable() async {
    final dead = _unreachableIndexes();
    if (dead.isEmpty) {
      await _showError(
          getLocalText.s("No unreachable or broken servers in last test"));
      return;
    }
    final idx = _index;
    if (idx < 0) return;
    await widget.controller.setMembersEnabled(idx, dead, false);
  }

  Future<void> _deleteUnreachable() async {
    final dead = _unreachableIndexes();
    if (dead.isEmpty) {
      await _showError(getLocalText.s("No unreachable or broken servers in last test"));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(getLocalText.s("Delete unreachable?")),
        content: Text(getLocalText.plural("Remove %d servers that failed the test (unreachable or broken)?", dead.length)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(getLocalText.s("Cancel"))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error),
            child: Text(getLocalText.s("Delete")),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final idx = _index;
    if (idx < 0) return;
    await widget.controller.removeMembersAt(idx, dead);
    if (!mounted) return;


    setState(() {});
  }

  Future<void> _sortByPing() async {
    final idx = _index;
    if (idx < 0) return;
    final order =
        ProbeController.pingSortOrder(_probeByIndex(), _folder.members.length);
    await widget.controller.applyMembersOrder(idx, order);
    if (!mounted) return;

    setState(() {});
  }

  Future<void> _editThresholds() async {
    if (!mounted) return;
    final g = TextEditingController(text: '${_thresholds.greenMs}');
    final y = TextEditingController(text: '${_thresholds.yellowMs}');
    final o = TextEditingController(text: '${_thresholds.orangeMs}');
    Widget field(TextEditingController c, String label) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        );
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(getLocalText.s("Ping color thresholds")),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            field(g, getLocalText.s("Green up to, ms")),
            field(y, getLocalText.s("Yellow up to, ms")),
            field(o, getLocalText.s("Orange up to, ms")),
            Text(
              getLocalText.s("Anything above is red."),
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(getLocalText.s("Cancel"))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(getLocalText.s("Save"))),
        ],
      ),
    );
    final gv = int.tryParse(g.text.trim());
    final yv = int.tryParse(y.text.trim());
    final ov = int.tryParse(o.text.trim());
    g.dispose();
    y.dispose();
    o.dispose();
    if (saved != true || !mounted) return;
    final next = await ProbeController.saveThresholds(
      greenMs: gv,
      yellowMs: yv,
      orangeMs: ov,
    );
    if (!mounted) return;
    setState(() => _thresholds = next);
  }

  void _toggleEdit() {
    if (_editing) {
      final name = _nameCtrl.text.trim();
      final idx = _index;
      if (idx >= 0 && name.isNotEmpty) {
        unawaited(widget.controller.renameAt(idx, name));
      }
    }
    setState(() => _editing = !_editing);
  }

  Future<void> _delete() async {

    final choice =
        await showDeleteFolderDialog(context, _folder, widget.entry.displayName);
    if (choice == null || !mounted) return;
    final idx = _index;
    if (idx < 0) {
      if (mounted) Navigator.pop(context);
      return;
    }


    _leaving = true;
    try {
      await widget.controller
          .deleteFolderAt(idx, keepServers: choice == 'keep');
    } catch (_) {




      _leaving = false;
      _onEntriesChanged();
      rethrow;
    }
    if (mounted) Navigator.pop(context);
  }



  Future<void> _showError(String err) async {
    if (err.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }

  Future<void> _addFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      await _showError(getLocalText.s("Clipboard is empty"));
      return;
    }
    final idx = _index;
    if (idx < 0) return;
    final err = await widget.controller.addMembersToFolder(idx, text);
    if (!mounted) return;
    if (err != null) {
      await _showError(err.render());
      return;
    }
    setState(() {});
  }

  Future<void> _addFromFiles() async {
    try {

      final outcome = await pickFileSafely(allowMultiple: true);
      if (outcome is! PickedFiles) {
        final problem = pickProblemText(outcome);
        if (problem != null && mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(problem)));
        }
        return;
      }
      var added = 0;
      final errors = <String>[];
      for (final file in outcome.files) {
        final text = file.text.trim();
        if (text.isEmpty) continue;
        final idx = _index;
        if (idx < 0) return;
        final err = await widget.controller.addMembersToFolder(
          idx,
          text,
          nameFallback: SubscriptionController.fileBaseName(file.name),
        );
        if (err == null) {
          added++;
        } else {
          if (!mounted) return;
          errors.add('${file.name}: ${err.render()}');
        }
      }
      if (!mounted) return;
      if (errors.isNotEmpty) {
        await _showError(errors.join('\n'));
      } else if (added == 0) {
        await _showError(getLocalText.s("No servers found in selected files"));
      }
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      await _showError(getLocalText.s("Error: %s", formatUserError(e).render()));
    }
  }



  Future<void> _addAutoNode() async {
    final idx = _index;
    if (idx < 0) return;
    final folder = widget.controller.entries[idx].list;
    if (folder is! FolderServers) return;

    final candidates = _poolCandidates(folder);
    final res = await Navigator.of(context).push<AutoGroupEditResult>(
      MaterialPageRoute(
        builder: (_) => AutoGroupEditScreen(
          initial: null,
          candidates: candidates,
          canDelete: false,
        ),
      ),
    );
    if (!mounted || res is! AutoGroupSaved) return;


    final err =
        await widget.controller.addAutoMemberToFolder(idx, res.spec);
    if (!mounted) return;
    if (err != null) {
      await _showError(err.render());
      return;
    }
    setState(() {});
  }



  Future<void> _editAutoNode(int memberIndex, AutoSelectSpec node) async {
    final idx = _index;
    if (idx < 0) return;
    final folder = widget.controller.entries[idx].list;
    if (folder is! FolderServers) return;

    final res = await Navigator.of(context).push<AutoGroupEditResult>(
      MaterialPageRoute(
        builder: (_) => AutoGroupEditScreen(
          initial: node,
          candidates: _poolCandidates(folder),
          canDelete: true,
        ),
      ),
    );
    if (!mounted || res == null) return;

    switch (res) {
      case AutoGroupSaved(:final spec):
        final err = await widget.controller
            .updateAutoMemberAt(idx, memberIndex, spec);
        if (!mounted) return;
        if (err != null) {
          await _showError(err.render());
          return;
        }
      case AutoGroupDeleted():
        await widget.controller.removeMemberAt(idx, memberIndex);
        if (!mounted) return;
    }
    setState(() {});
  }




  List<({NodeLink key, String label})> _poolCandidates(FolderServers folder) {
    final out = <({NodeLink key, String label})>[];
    for (final m in folder.members) {
      final n = m.node;
      if (n == null || n.isGroup || n.tag.isEmpty) continue;
      if (nodeIdentityKey(n) == null) continue;
      out.add((
        key: NodeLink(folderId: folder.id, tag: n.tag),
        label: n.label.isEmpty ? n.tag : n.label,
      ));
    }
    return out;
  }

  Future<void> _addFromUrl() async {
    final ctl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(getLocalText.s("Add servers by URL")),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: getLocalText.s("URL"),

                hintText: 'https://…',
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
            const SizedBox(height: 8),
            Text(
              getLocalText.s("Fetched once — servers are added as a snapshot and won't auto-update. For live updates add a subscription instead."),
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(getLocalText.s("Cancel"))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            child: Text(getLocalText.s("Fetch")),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (url == null || url.isEmpty || !mounted) return;
    if (!isSubscriptionUrl(url)) {
      await _showError(getLocalText.s("Enter a valid http(s):// URL"));
      return;
    }
    final idx = _index;
    if (idx < 0) return;
    final err = await widget.controller.addUrlSnapshotToFolder(idx, url);
    if (!mounted) return;
    if (err != null) {
      await _showError(err.render());
      return;
    }
    setState(() {});
  }



  Future<void> _editMember(int memberIndex) async {


    if (!mounted) return;
    final member = _folder.members[memberIndex];


    final node = member.node;
    if (node is AutoSelectSpec) {
      await _editAutoNode(memberIndex, node);
      return;
    }

    final ctl = TextEditingController(text: member.raw);
    final newRaw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(getLocalText.s("Edit server")),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLines: 8,
          minLines: 3,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: getLocalText.s("Proxy link, WireGuard config or outbound JSON"),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(getLocalText.s("Cancel"))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text),
            child: Text(getLocalText.s("Save")),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (newRaw == null || !mounted) return;
    final idx = _index;
    if (idx < 0) return;
    final err = await widget.controller.updateMemberAt(idx, memberIndex, newRaw);
    if (!mounted) return;
    if (err != null) {
      await _showError(err.render());
      return;
    }
    setState(() {});
  }

  Future<void> _moveMember(int memberIndex) async {
    if (!mounted) return;
    final toIndex = await showFolderPicker(context, widget.controller,
        excludeId: widget.entry.id);
    if (toIndex == null || !mounted) return;
    final idx = _index;
    if (idx < 0) return;
    final err =
        await widget.controller.moveMemberToFolder(idx, memberIndex, toIndex);
    if (!mounted) return;
    if (err != null) {
      await _showError(err.render());
      return;
    }
    setState(() {});
  }

  Future<void> _ungroupMember(int memberIndex) async {
    final idx = _index;
    if (idx < 0) return;
    await widget.controller.ungroupMemberAt(idx, memberIndex);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(getLocalText.s("Moved out of folder"))),
    );
    setState(() {});
  }

  Future<void> _deleteMember(int memberIndex) async {
    if (!mounted) return;
    final member = _folder.members[memberIndex];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(getLocalText.s("Delete server?")),
        content: Text(getLocalText.s("Remove \"%s\" from this folder?", _memberTitle(member))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(getLocalText.s("Cancel"))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error),
            child: Text(getLocalText.s("Delete")),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final idx = _index;
    if (idx < 0) return;
    await widget.controller.removeMemberAt(idx, memberIndex);
    setState(() {});
  }

  void _showMemberMenu(int memberIndex) {



    final isGroup = _folder.members[memberIndex].node?.isGroup == true;
    showAppBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(getLocalText.s("Edit…")),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_editMember(memberIndex));
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: Text(getLocalText.s("Move to folder…")),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_moveMember(memberIndex));
              },
            ),
            if (!isGroup)
              ListTile(
                leading: const Icon(Icons.folder_off_outlined),
                title: Text(getLocalText.s("Move out of folder")),
                subtitle: Text(getLocalText.s("Becomes a standalone server")),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(_ungroupMember(memberIndex));
                },
              ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(ctx).colorScheme.error),
              title: Text(getLocalText.s("Delete"),
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_deleteMember(memberIndex));
              },
            ),
          ],
        ),
      ),
    );
  }

  static String _memberTitle(FolderMember m) {
    final node = m.node;
    if (node == null) {
      final line = m.raw.split('\n').first.trim();
      return line.length > 40 ? '${line.substring(0, 40)}…' : line;
    }
    return node.label.isNotEmpty ? node.label : node.tag;
  }



  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: widget.entry,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: _editing
              ? TextField(
                  controller: _nameCtrl,
                  autofocus: true,
                  style: theme.textTheme.titleLarge,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: getLocalText.s("Folder name"),
                  ),
                  onSubmitted: (_) => _toggleEdit(),
                )
              : Row(
                  children: [
                    const Icon(Icons.folder_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.entry.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
          actions: [
            IconButton(
              tooltip: _editing ? getLocalText.s("Save") : getLocalText.s("Rename"),
              icon: Icon(_editing ? Icons.check : Icons.edit_outlined),
              onPressed: _toggleEdit,
            ),
            PopupMenuButton<String>(
              tooltip: getLocalText.s("Add servers"),
              icon: const Icon(Icons.add),
              onSelected: (v) {
                if (v == 'paste') unawaited(_addFromClipboard());
                if (v == 'file') unawaited(_addFromFiles());
                if (v == 'url') unawaited(_addFromUrl());
                if (v == 'auto') unawaited(_addAutoNode());
              },
              itemBuilder: (menuCtx) => [
                PopupMenuItem(
                    value: 'paste',
                    child: Text(getLocalText.s("Paste from clipboard"))),
                PopupMenuItem(
                    value: 'file',
                    child: Text(getLocalText.s("Import from files…"))),
                PopupMenuItem(
                    value: 'url', child: Text(getLocalText.s("Add by URL…"))),
                const PopupMenuDivider(),

                PopupMenuItem(
                    value: 'auto',
                    child: Text(getLocalText.s("Add auto node…"))),
              ],
            ),
            IconButton(
              tooltip: getLocalText.s("Delete folder"),
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          ],
          bottom: TabBar(
            controller: _tabCtrl,
            tabs: [
              Tab(text: getLocalText.s("Servers")),
              Tab(text: getLocalText.s("Settings")),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabCtrl,
          children: [
            _buildMembersTab(theme),
            _buildSettingsTab(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildMembersTab(ThemeData theme) {
    final members = _folder.members;
    if (members.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_open,
                  size: 48, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(getLocalText.s("Folder is empty"),
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                getLocalText.s("Add servers with the + button above, or long-press a standalone server on the Servers screen and choose \"Move to folder…\"."),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }
    final visible = _visibleMembers();
    final Widget list;
    if (_filterActive) {


      list = ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(
            12, 4, 12, MediaQuery.of(context).padding.bottom + 24),
        itemCount: visible.length,
        itemBuilder: (context, vi) {
          final (i, m) = visible[vi];
          return _memberTile(i, m, reorderable: false);
        },
      );
    } else {
      list = ReorderableListView.builder(
        scrollController: _scrollController,
        padding: EdgeInsets.fromLTRB(
            12, 4, 12, MediaQuery.of(context).padding.bottom + 24),
        buildDefaultDragHandles: false,
        itemCount: members.length,
        onReorderItem: (oldIndex, newIndex) {


          final idx = _index;
          if (idx < 0) return;
          unawaited(widget.controller.reorderMember(idx, oldIndex, newIndex));


        },
        itemBuilder: (context, i) =>
            _memberTile(i, members[i], reorderable: true),
      );
    }
    return Column(
      children: [
        _buildControlBar(theme),
        if (_filterExpanded) _buildFilterPanel(theme),
        const Divider(height: 1),
        Expanded(child: list),
      ],
    );
  }

  Widget _memberTile(int i, FolderMember m, {required bool reorderable}) {
    final cs = Theme.of(context).colorScheme;
    final highlighted = _highlightedMember == i;
    final keys = _memberProbeKeys();
    final probe = i < keys.length ? _probe[keys[i]] : null;


    return KeyedSubtree(
      key: ValueKey('member-$i-${m.raw.hashCode}'),
      child: AnimatedContainer(
        key: _memberKey(i),
        duration: const Duration(milliseconds: 200),
        decoration: highlighted
            ? BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.5),
                border: Border(
                    left: BorderSide(color: cs.primary, width: 3)),
              )
            : null,
        child: _MemberTile(
          member: m,
      isChainLink:
          m.node != null && _chainLinkTags().contains(m.node!.tag),
      dragIndex: i,
      reorderable: reorderable,
      folderEnabled: widget.entry.enabled,
      probe: probe,
      thresholds: _thresholds,
      onToggle: () {
        final idx = _index;
        if (idx < 0) return;
        unawaited(widget.controller
            .toggleMemberAt(idx, i)
            .then((_) => mounted ? setState(() {}) : null));
      },
      onLongPress: () => _showMemberMenu(i),


      onTap: m.node == null
          ? () => _showMemberMenu(i)
          : () {
              final idx = _index;
              if (idx < 0) return;
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => NodeSettingsScreen(
                    entry: widget.entry,
                    index: idx,
                    memberIndex: i,
                    subController: widget.controller,
                  ),
                ),
              ).then((_) => mounted ? setState(() {}) : null);
            },
      onProbeBadgeTap: () {
        final r = probe;
        if (r == null || r.message.isEmpty) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(r.message)),
        );
      },
        ),
      ),
    );
  }






  Widget _buildControlBar(ThemeData theme) {
    final muted = theme.colorScheme.onSurfaceVariant;
    final s = _probeSummary();
    final String info;
    if (_testing) {
      info = getLocalText.s("Testing… %d done", s.ok + s.dead);
    } else if (_probe.isNotEmpty) {
      info = [
        getLocalText.s("%d ok", s.ok),
        getLocalText.plural("%d err", s.dead),
        if (s.broken > 0) getLocalText.plural("%d broken", s.broken),
      ].join(' · ');
    } else {
      final total = _folder.members.length;
      final off = _folder.disabledCount;
      info = [
        getLocalText.plural("%d servers", total),
        if (off > 0) getLocalText.s("%d off", off),
      ].join(' · ');
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(info, style: TextStyle(fontSize: 12, color: muted)),
          ),


          GestureDetector(
            onTap: _folder.members.isEmpty
                ? null
                : () => unawaited(_toggleTest()),
            onLongPress: _showTestSettings,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                _testing ? Icons.stop_circle_outlined : Icons.speed,
                size: 22,
                color: _folder.members.isEmpty
                    ? Theme.of(context).disabledColor
                    : null,
              ),
            ),
          ),


          IconButton(
            tooltip: _filterExpanded
                ? getLocalText.s("Hide filters")
                : getLocalText.s("Show filters"),
            visualDensity: VisualDensity.compact,
            onPressed: () =>
                setState(() => _filterExpanded = !_filterExpanded),
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.filter_list,
                  size: 20,
                  color: _filterActive ? theme.colorScheme.primary : null,
                ),
                if (_filterActive)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: IgnorePointer(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.amber,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),




          PopupMenuButton<String>(
            tooltip: getLocalText.s("Test actions"),
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (v) {
              if (v == 'disable_slow') unawaited(_disableSlowerThan());
              if (v == 'disable_dead') unawaited(_disableUnreachable());
              if (v == 'delete_dead') unawaited(_deleteUnreachable());
              if (v == 'sort') unawaited(_sortByPing());
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
                PopupMenuItem(
                    value: 'delete_dead',
                    enabled: ready,
                    child: Text(getLocalText.s("Delete unreachable"))),
                PopupMenuItem(
                    value: 'sort',
                    enabled: ready,
                    child: Text(getLocalText.s("Sort by ping"))),
              ];
            },
          ),
        ],
      ),
    );
  }

  bool get _filterActive =>
      _filterRegexCtl.text.trim().isNotEmpty || _selectedProtocols.isNotEmpty;

  bool get _regexValid {
    final t = _filterRegexCtl.text.trim();
    if (t.isEmpty) return true;
    try {
      RegExp(t);
      return true;
    } catch (_) {
      return false;
    }
  }



  List<(int, FolderMember)> _visibleMembers() {
    RegExp? re;
    final pattern = _filterRegexCtl.text.trim();
    if (pattern.isNotEmpty) {
      try {
        re = RegExp(pattern, caseSensitive: false);
      } catch (_) {
        re = null;
      }
    }
    final out = <(int, FolderMember)>[];
    for (var i = 0; i < _folder.members.length; i++) {
      final m = _folder.members[i];
      final node = m.node;
      if (re != null) {
        final hay = node == null ? m.raw : '${node.tag} ${node.label}';
        if (re.hasMatch(hay) == _regexInvert) continue;
      }
      if (_selectedProtocols.isNotEmpty) {
        final match = _selectedProtocols.contains(node?.protocol ?? '');
        if (match == _protocolsInvert) continue;
      }
      out.add((i, m));
    }
    return out;
  }



  Widget _buildFilterPanel(ThemeData theme) {
    final protocols = <String>{
      for (final m in _folder.members)
        if (m.node != null) m.node!.protocol,
    }.toList()
      ..sort();
    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RegexFilterField(
            controller: _filterRegexCtl,
            onChanged: (_) => setState(() {}),
            valid: _regexValid,
            invert: _regexInvert,
            onInvertToggle: () => setState(() => _regexInvert = !_regexInvert),
            onClear: () {
              _filterRegexCtl.clear();
              setState(() {});
            },
          ),
          if (protocols.isNotEmpty) ...[
            const SizedBox(height: 4),
            MultiSelectChipsRow(
              options: [for (final p in protocols) (p, protoLabel(p))],
              enabled: _selectedProtocols,
              onToggle: (id) => setState(() {
                if (!_selectedProtocols.add(id)) _selectedProtocols.remove(id);
              }),
              invert: _protocolsInvert,
              onInvertToggle: () =>
                  setState(() => _protocolsInvert = !_protocolsInvert),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingsTab(ThemeData theme) {




    final hasDetour = _folder.nodes.any((n) => n.chained != null) ||
        _folder.members.any((m) => m.detour.isNotEmpty);
    return SubscriptionSettingsTab(
      entry: widget.entry,
      folderMode: true,
      directions: _directions,


      detourPathHopsOf: (stored) => detourPathHops(stored,
          controller: widget.controller,
          directions: _directions,
          folder: widget.entry.list is FolderServers
              ? widget.entry.list as FolderServers
              : null),
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


      onCopyUrl: () {},
      onShowIntervalPicker: () {},
      onShowOnUpdateActionPicker: () {},
      onRefreshNow: () {},
      onEditSource: () {},
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

  Future<void> _showOverrideDetourPicker() async {



    await _loadDirections();
    if (!mounted) return;
    final chosen = await showDetourTargetPicker(
      context,
      controller: widget.controller,
      directions: _directions,
      currentFolder: _folder,
    );
    if (chosen == null || !mounted) return;
    setState(() {
      widget.entry.overrideDetour = chosen.link;
      if (chosen.link.isNotEmpty) widget.entry.useDetourServers = true;
    });
    unawaited(widget.controller.persistSources());
  }
}



class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.dragIndex,
    required this.folderEnabled,
    required this.onToggle,
    required this.onLongPress,
    required this.onTap,
    this.reorderable = true,
    this.isChainLink = false,
    this.onProbeBadgeTap,
    this.probe,
    this.thresholds = const ProbeThresholds(),
  });

  final FolderMember member;
  final int dragIndex;



  final bool reorderable;



  final bool isChainLink;
  final bool folderEnabled;
  final VoidCallback onToggle;
  final VoidCallback onLongPress;
  final VoidCallback onTap;


  final VoidCallback? onProbeBadgeTap;


  final ProbeResult? probe;
  final ProbeThresholds thresholds;


  Widget? _probeBadge(BuildContext context, ThemeData theme) {
    final r = probe;
    if (r == null) return null;
    return ProbeBadge(result: r, thresholds: thresholds, onTap: onProbeBadgeTap);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final node = member.node;
    final active = member.enabled && folderEnabled;
    final muted = theme.colorScheme.onSurfaceVariant;
    var title = node == null
        ? getLocalText.s("Unreadable entry")
        : (node.label.isNotEmpty ? node.label : node.tag);
    if (isChainLink) title = '⚙ $title';


    final warnings =
        node == null ? const <NodeWarning>[] : mergedNodeWarnings(node, member.warnings);
    final hideProto = node != null && member.warnings.any((w) => w.isCoreRejected);
    final subtitle = node == null
        ? getLocalText.s("Tap to edit or delete")
        : hideProto
            ? null
            : node is AutoSelectSpec && node.isManual

                ? [
                    node.protocol.toUpperCase(),
                    if (node.manualDefault.isNotEmpty) node.manualDefault,
                  ].join(' · ')
                : node.isAddressless
                    ? node.protocol.toUpperCase()
                    : '${node.protocol.toUpperCase()} · ${node.server}:${node.port}';

    final Widget? trailing = _probeBadge(context, theme);

    final tile = ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 40,
        child: Switch(
          value: member.enabled,
          onChanged: (_) => onToggle(),
        ),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: active ? null : muted,
          fontStyle: node == null ? FontStyle.italic : null,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitle != null)
            Text(subtitle,
                style: TextStyle(fontSize: 12, color: muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          if (nodeHasActionableWarnings(warnings)) NodeWarningRow(warnings),
        ],
      ),
      trailing: trailing,
      onLongPress: onLongPress,
      onTap: onTap,
    );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (reorderable) ReorderGrabStrip(index: dragIndex),
          Expanded(
            child: Column(
              children: [
                tile,
                const Divider(height: 1),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
