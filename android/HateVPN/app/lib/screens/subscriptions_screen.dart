import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/home_controller.dart';
import '../controllers/subscription_controller.dart';
import '../models/server_list.dart';
import '../models/ui_msg.dart';
import '../services/community_servers_loader.dart';
import '../services/error_format.dart';
import '../services/settings_storage.dart';
import '../services/subscription/auto_updater.dart';
import '../services/url_launcher.dart';
import 'add_server_wizard_screen.dart';
import 'app_settings_screen.dart';
import 'folder_detail_screen.dart';
import 'node_settings_screen.dart';
import 'qr_scan_screen.dart';
import 'subscription_detail_screen.dart';
import 'subscription_detail_screen/widgets/node_warnings_sheet.dart';
import 'warp_wizard_screen.dart';
import 'subscriptions_screen/clipboard_analysis.dart';
import 'subscriptions_screen/entry_context_menu.dart';
import 'subscriptions_screen/folder_picker.dart';
import 'subscriptions_screen/paste_dialogs.dart';
import 'subscriptions_screen/public_test_servers.dart';
import '../models/source_chain.dart';
import '../models/source_entry.dart';
import 'chain_edit/chain_edit_flow.dart';
import 'chain_edit/new_chain_dialog.dart';
import 'subscriptions_screen/widgets/add_icon_button.dart';
import 'subscriptions_screen/widgets/parse_input_error_banner.dart';
import 'subscriptions_screen/widgets/chains_section.dart';
import 'subscriptions_screen/widgets/subscription_entry_tile.dart';
import 'subscriptions_screen/widgets/subscriptions_empty_state.dart';
import '../services/l10n/locale_controller.dart';
import '../services/file_import.dart';

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({
    super.key,
    required this.subController,
    required this.homeController,
    required this.autoUpdater,
    this.focusEntryId,
    this.initialInput,
  });

  final SubscriptionController subController;
  final HomeController homeController;
  final AutoUpdater autoUpdater;



  final String? focusEntryId;




  final String? initialInput;

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  final _inputController = TextEditingController();
  bool _autoUpdateEnabled = true;








  List<SourceEntry> _sources = const [];



  List<SourceChain> get _chains => [
    for (final e in _sources)
      if (e is ChainEntry) e.chain,
  ];




  bool? _hasCamera;



  final _scrollController = ScrollController();
  final _tileKeys = <String, GlobalKey>{};
  String? _highlightedEntryId;
  _HighlightMode _highlightMode = _HighlightMode.none;
  double _highlightOpacity = 0;
  double? _highlightScrollBaseline;






  double _snackBarClearance = 0;
  Timer? _highlightTimer;
  Timer? _highlightFadeTimer;


  bool _ignoreInputDismiss = false;


  bool _programmaticScroll = false;

  GlobalKey _tileKey(String id) => _tileKeys.putIfAbsent(id, GlobalKey.new);

  Set<String> _entryIds(SubscriptionController ctrl) =>
      ctrl.entries.map((e) => e.id).toSet();

  String? _firstNewEntryId(Set<String> before, SubscriptionController ctrl) {
    for (final e in ctrl.entries) {
      if (!before.contains(e.id)) return e.id;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadAutoUpdateFlag());
    unawaited(_loadCameraAvailability());
    unawaited(_loadSourceOrder());
    widget.subController.addListener(_onControllerForSourceOrder);

    final prefill = widget.initialInput;
    if (prefill != null && prefill.trim().isNotEmpty) {
      _inputController.text = prefill.trim();
    }
    _inputController.addListener(_onInputForHighlightDismiss);
    _scrollController.addListener(_onScrollForHighlightDismiss);
    final focus = widget.focusEntryId;
    if (focus != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focusEntry(focus, attempt: 0),
      );
    }
  }

  void _onInputForHighlightDismiss() {
    if (_ignoreInputDismiss) return;
    if (_highlightMode == _HighlightMode.newEntry) {
      _dismissHighlight(animated: true);
    }
  }

  void _onScrollForHighlightDismiss() {
    if (_programmaticScroll) return;
    if (_highlightMode != _HighlightMode.newEntry) return;
    if (!_scrollController.hasClients) return;
    final baseline = _highlightScrollBaseline;
    if (baseline == null) return;
    final screenH = MediaQuery.sizeOf(context).height;
    if ((_scrollController.offset - baseline).abs() > screenH) {
      _dismissHighlight(animated: true);
    }
  }

  void _onUserInteractionDismissHighlight() {
    if (_highlightMode == _HighlightMode.newEntry) {
      _dismissHighlight(animated: true);
    }
  }

  void _dismissHighlight({required bool animated}) {
    _highlightTimer?.cancel();
    _highlightFadeTimer?.cancel();
    if (_highlightedEntryId == null) return;
    if (!animated || _highlightMode != _HighlightMode.newEntry) {
      if (!mounted) return;
      setState(() {
        _highlightedEntryId = null;
        _highlightMode = _HighlightMode.none;
        _highlightOpacity = 0;
        _highlightScrollBaseline = null;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _highlightOpacity = 0);
    _highlightFadeTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() {
        _highlightedEntryId = null;
        _highlightMode = _HighlightMode.none;
        _highlightScrollBaseline = null;
      });
    });
  }




  Future<void> _focusEntry(String id, {required int attempt}) async {
    if (!mounted) return;
    if (attempt == 0) {
      _highlightTimer?.cancel();
      _highlightFadeTimer?.cancel();
      setState(() {
        _highlightedEntryId = id;
        _highlightMode = _HighlightMode.focus;
        _highlightOpacity = 1;
      });
    }
    const maxAttempts = 6;
    final ctx = _tileKeys[id]?.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.3,
      );
    } else if (attempt < maxAttempts && _scrollController.hasClients) {
      final idx = widget.subController.entries.indexWhere((e) => e.id == id);
      if (idx >= 0) {
        final target = (idx * 88.0).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.jumpTo(target);
      }
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focusEntry(id, attempt: attempt + 1),
      );
      return;
    }
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 2200), () {
      _dismissHighlight(animated: false);
    });
  }


  Future<void> _beginNewEntryHighlight(String id) async {
    if (!mounted) return;
    _highlightTimer?.cancel();
    _highlightFadeTimer?.cancel();
    setState(() {
      _highlightedEntryId = id;
      _highlightMode = _HighlightMode.newEntry;
      _highlightOpacity = 1;
      _snackBarClearance = 80;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    _programmaticScroll = true;
    await _scrollToEntry(id);
    _programmaticScroll = false;
    if (!mounted) return;
    _highlightScrollBaseline = _scrollController.hasClients
        ? _scrollController.offset
        : 0;
    _highlightTimer = Timer(const Duration(seconds: 7), () {
      _dismissHighlight(animated: true);
    });
  }





  Future<void> _scrollToEntry(String id, {int attempt = 0}) async {
    if (!mounted) return;
    final ctx = _tileKeys[id]?.currentContext;
    if (ctx != null) {
      unawaited(
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: 0.45,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 320));
      return;
    }
    if (attempt < 6 && _scrollController.hasClients) {
      final idx = widget.subController.entries.indexWhere((e) => e.id == id);
      if (idx >= 0) {
        final target = (idx * 88.0).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.jumpTo(target);
      }
      await WidgetsBinding.instance.endOfFrame;
      return _scrollToEntry(id, attempt: attempt + 1);
    }
  }

  Future<void> _loadAutoUpdateFlag() async {
    final v = await SettingsStorage.getAutoUpdateSubs();
    if (!mounted) return;
    setState(() => _autoUpdateEnabled = v);
  }




  Future<void> _loadCameraAvailability() async {
    final v = await UrlLauncher.hasCamera();
    if (!mounted) return;
    setState(() => _hasCamera = v);
  }




  Future<void> _loadSourceOrder() async {
    final sources = await widget.subController.sourceEntries();
    if (!mounted) return;
    setState(() => _sources = sources);
  }

  void _onControllerForSourceOrder() {
    _forgetGoneEntries();
    unawaited(_loadSourceOrder());
  }




  void _forgetGoneEntries() {
    final ids = _entryIds(widget.subController);
    _tileKeys.removeWhere((id, _) => !ids.contains(id));
    final hl = _highlightedEntryId;
    if (hl != null && !ids.contains(hl)) _dismissHighlight(animated: false);
  }



  @visibleForTesting
  Future<void> debugReorderRows(int oldIndex, int newIndex) =>
      _reorderRows(widget.subController, oldIndex, newIndex);


  @visibleForTesting
  Future<void> debugReloadSources() => _loadSourceOrder();

  @visibleForTesting
  String? get debugHighlightedEntryId => _highlightedEntryId;

  @visibleForTesting
  Iterable<String> get debugTileKeyIds => _tileKeys.keys;






  Future<void> _addChain() async {
    final directions = await SettingsStorage.getDirections();
    if (!mounted) return;
    final req = await showNewChainDialog(
      context,
      usedTags: [..._chains.map((c) => c.tag), ...directions.map((d) => d.tag)],
    );
    if (req == null || !mounted) return;
    final SourceChain created;
    try {
      created = await SettingsStorage.addChain(
        tag: req.tag,
        label: req.label.isEmpty ? null : req.label,
      );
    } on StateError catch (e) {


      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    await _loadSourceOrder();
    if (!mounted) return;
    await _editChain(created);
  }

  Future<void> _editChain(SourceChain chain) async {
    final outcome = await editChainAndPersist(
      context,
      chain,
      subController: widget.subController,
      homeController: widget.homeController,
    );
    if (outcome == null || !mounted) return;
    await _loadSourceOrder();
    if (!mounted) return;



    _notifyChainPositionsRemoved(outcome.positionsRemoved);


    await _regenerateAndSave();
  }









  void _notifyLinksCleared(NodeLinkNotice notice) {
    if (!mounted) return;
    String names(List<String> carriers) {
      final all = [
        for (final n in carriers)
          if (n.isNotEmpty) n,
      ];
      if (all.isEmpty) return '';
      final shown = all.take(3).map((n) => '"$n"').join(', ');
      return ' ($shown${all.length > 3 ? ' +${all.length - 3}' : ''})';
    }

    final subject = notice.subject;
    final lead = switch (subject.kind) {
      NodeLinkSubjectKind.server => getLocalText.s(
        'Server "%s" deleted',
        subject.name,
      ),
      NodeLinkSubjectKind.subscription => getLocalText.s(
        'Subscription "%s" deleted',
        subject.name,
      ),
      NodeLinkSubjectKind.folder => getLocalText.s(
        'Folder "%s" deleted',
        subject.name,
      ),
      NodeLinkSubjectKind.servers => getLocalText.plural(
        '%d servers deleted',
        subject.count,
      ),
    };
    final change = notice.change;
    final parts = [
      if (change.detourCarriers.isNotEmpty)
        getLocalText.s(
              'detour removed from %s source(s)',
              '${change.detourCarriers.length}',
            ) +
            names(change.detourCarriers),
      if (change.groupMembers > 0)
        getLocalText.s('%s group member(s) removed', '${change.groupMembers}') +
            names(change.touchedGroups),
      if (change.positions > 0)
        getLocalText.s('%s chain position(s) removed', '${change.positions}') +
            names(change.touchedChains),
    ];
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$lead — ${parts.join(', ')}.')));
  }


  void _notifyChainPositionsRemoved(int removed) {
    if (removed <= 0 || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          getLocalText.s('%s chain position(s) removed', '$removed'),
        ),
      ),
    );
  }






  void _drainLinkNotices() {
    final ctrl = widget.subController;
    if (ctrl.takeChainsRelinked()) {
      unawaited(
        _loadSourceOrder(),
      );
    }
    for (final notice in ctrl.takeLinkNotices()) {
      _notifyLinksCleared(notice);
    }
  }

  Future<void> _toggleChain(SourceChain chain) async {
    await SettingsStorage.updateChain(chain.copyWith(enabled: !chain.enabled));
    await _loadSourceOrder();
    if (!mounted) return;
    await _regenerateAndSave();
  }

  Future<void> _toggleAutoUpdate() async {
    final next = !_autoUpdateEnabled;
    await SettingsStorage.setAutoUpdateSubs(next);
    if (!mounted) return;
    setState(() => _autoUpdateEnabled = next);
  }

  @override
  void deactivate() {



    _highlightTimer?.cancel();
    _highlightFadeTimer?.cancel();
    _highlightedEntryId = null;
    _highlightMode = _HighlightMode.none;
    _highlightOpacity = 0;
    _highlightScrollBaseline = null;
    super.deactivate();
  }

  @override
  void dispose() {
    widget.subController.removeListener(_onControllerForSourceOrder);
    _inputController.removeListener(_onInputForHighlightDismiss);
    _scrollController.removeListener(_onScrollForHighlightDismiss);
    _inputController.dispose();
    _scrollController.dispose();
    _highlightTimer?.cancel();
    _highlightFadeTimer?.cancel();
    super.dispose();
  }

  Future<bool> _onWillPop() async {



    final pending = _inputController.text.trim();
    if (pending.isEmpty) return true;
    if (!mounted) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(getLocalText.s("Discard input?")),
        content: Text(
          getLocalText.s(
            "You have unsaved text in the input field. Leave and discard it?",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(getLocalText.s("Stay")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(getLocalText.s("Discard")),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }




  void _openAddServerWizard() {
    final baseline = _entryIds(widget.subController);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AddServerWizardScreen(
          subController: widget.subController,
          onAdded: () => _regenerateAndSave(entryBaseline: baseline),
        ),
      ),
    );
  }


  void _openSubscriptionSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AppSettingsScreen(initialTab: 2),
      ),
    );
  }


  void _openWarpWizard() {
    final baseline = _entryIds(widget.subController);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WarpWizardScreen(
          subController: widget.subController,
          onAdded: () => _regenerateAndSave(entryBaseline: baseline),
        ),
      ),
    );
  }


  void _presentParseRejectSheetIfNeeded() {
    final err = widget.subController.lastError;
    if (err is! ParseInputRejectedMsg || !err.hasDropped || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showNodeWarningsSheet(context, err.dropped, sourceLabel: err.sourceLabel);
    });
  }


  void _snackCommentsRemoved() {
    if (!mounted || !widget.subController.lastCommentsRemoved) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(getLocalText.s("Comments were removed."))),
    );
  }

  Future<void> _add() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) {


      await _pasteFromClipboard();
      return;
    }
    final baseline = _entryIds(widget.subController);
    await widget.subController.addFromInput(text);
    if (widget.subController.lastError == null) {
      _ignoreInputDismiss = true;
      _inputController.clear();
      _ignoreInputDismiss = false;
      _snackCommentsRemoved();
      await _regenerateAndSave(entryBaseline: baseline);
    } else {
      _presentParseRejectSheetIfNeeded();
    }
  }






  Future<void> _regenerateAndSave({Set<String>? entryBaseline}) async {
    final applied = await regenerateSourcesConfig(
      widget.subController,
      widget.homeController,
    );
    if (!mounted || applied == null) return;
    final n = widget.subController.entries
        .where((e) => e.enabled)
        .fold<int>(0, (s, e) => s + e.nodeCount);
    final newEntryId = entryBaseline == null
        ? null
        : _firstNewEntryId(entryBaseline, widget.subController);
    if (newEntryId != null) {
      await _beginNewEntryHighlight(newEntryId);
      if (!mounted) return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          applied
              ? getLocalText.plural("Config regenerated & applied: %d nodes", n)
              : getLocalText.plural("Config regenerated: %d nodes", n),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(getLocalText.s("Clipboard is empty"))),
        );
      }
      return;
    }

    final analysis = analyzeClipboard(text);
    if (!mounted) return;

    if (analysis.type == 'unknown') {
      showUnknownFormatDialog(context, text);
      return;
    }

    final confirmed = await showConfirmAddDialog(context, analysis);

    if (confirmed != true || !mounted) return;
    final baseline = _entryIds(widget.subController);
    await widget.subController.addFromInput(text);
    final addErr = widget.subController.lastError;
    if (addErr == null) {
      _snackCommentsRemoved();
      await _regenerateAndSave(entryBaseline: baseline);
    } else if (mounted) {
      _presentParseRejectSheetIfNeeded();
      if (addErr is! ParseInputRejectedMsg || !addErr.hasDropped) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(addErr.render())));
      }
    }
  }





  Future<void> _scanQrCode() async {
    final outcome = await Navigator.of(context).push<ScanOutcome>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (!mounted) return;


    if (outcome is! ScannedCode) {
      final problem = outcome == null ? null : scanProblemText(outcome);
      if (problem != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(problem)));
      }
      return;
    }

    final text = outcome.value;
    final analysis = analyzeClipboard(text);
    if (!mounted) return;

    if (analysis.type == 'unknown') {
      showUnknownFormatDialog(context, text);
      return;
    }

    final confirmed = await showConfirmAddDialog(context, analysis);
    if (confirmed != true || !mounted) return;

    final baseline = _entryIds(widget.subController);
    await widget.subController.addFromInput(text, origin: UserSource.qr);
    final addErr = widget.subController.lastError;
    if (addErr == null) {
      await _regenerateAndSave(entryBaseline: baseline);
    } else if (mounted) {
      _presentParseRejectSheetIfNeeded();
      if (addErr is! ParseInputRejectedMsg || !addErr.hasDropped) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(addErr.render())));
      }
    }
  }


  Future<void> _createFolder() async {
    final name = await showFolderNameDialog(context);
    if (name == null) return;
    final baseline = _entryIds(widget.subController);
    await widget.subController.addFolder(name);
    if (!mounted) return;
    final newId = _firstNewEntryId(baseline, widget.subController);
    if (newId != null) await _beginNewEntryHighlight(newId);
  }








  Future<void> _importFromFile() async {
    try {

      final outcome = await pickFileSafely(allowMultiple: true);
      if (outcome is! PickedFiles) {
        final problem = pickProblemText(outcome);
        if (problem != null && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(problem)));
        }
        return;
      }
      if (outcome.files.length > 1) {
        await _importFilesIntoFolder(outcome.files);
        return;
      }
      final file = outcome.single;
      final text = file.text.trim();
      if (text.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(getLocalText.s("File is empty"))),
          );
        }
        return;
      }
      if (!mounted) return;
      final baseline = _entryIds(widget.subController);



      final asFileSub = await widget.subController.addFileSubscription(
        text,
        file.name,
      );
      if (!asFileSub) {
        if (!mounted) return;




        await widget.subController.addFromInput(
          text,
          nameHint: SubscriptionController.fileBaseName(file.name),
        );
      }
      final importErr = widget.subController.lastError;
      if (importErr == null) {
        await _regenerateAndSave(entryBaseline: baseline);
      } else if (mounted) {
        _presentParseRejectSheetIfNeeded();
        if (importErr is! ParseInputRejectedMsg || !importErr.hasDropped) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(importErr.render())));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              getLocalText.s("Error: %s", formatUserError(e).render()),
            ),
          ),
        );
      }
    }
  }


  Future<void> _importFilesIntoFolder(List<PickedFile> files) async {
    final name = await showFolderNameDialog(
      context,
      title: getLocalText.plural("Import %d files into folder", files.length),
    );
    if (name == null || !mounted) return;
    final baseline = _entryIds(widget.subController);
    await widget.subController.addFolder(name);
    final folderIndex = widget.subController.entries.length - 1;
    var addedFiles = 0;
    final errors = <String>[];
    for (final file in files) {
      final text = file.text.trim();
      if (text.isEmpty) {
        errors.add(getLocalText.s("%s: empty file", file.name));
        continue;
      }
      final err = await widget.subController.addMembersToFolder(
        folderIndex,
        text,
        nameFallback: SubscriptionController.fileBaseName(file.name),
      );
      if (err == null) {
        addedFiles++;
      } else {
        errors.add('${file.name}: ${err.render()}');
      }
    }
    if (!mounted) return;
    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errors.join('\n'))));
    }
    if (addedFiles > 0) {
      await _regenerateAndSave(entryBaseline: baseline);
    }
  }

  Future<void> _updateAll() async {



    widget.autoUpdater.resetAllFailCounts();
    await widget.autoUpdater.maybeUpdateAll(UpdateTrigger.manual, force: true);
    if (!mounted) return;
    final config = await widget.subController.generateConfig();
    if (!mounted) return;
    if (config != null) {
      final ok = await widget.homeController.saveParsedConfig(config);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              getLocalText.plural(
                "Config generated: %d nodes",
                widget.subController.entries.fold<int>(
                  0,
                  (s, e) => s + e.nodeCount,
                ),
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.subController,
      builder: (context, _) {
        final ctrl = widget.subController;





        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _drainLinkNotices(),
        );
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            if (await _onWillPop()) {
              if (context.mounted) Navigator.of(context).pop();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Подключения'),
                  Text(
                    'Подписки и приглашения',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: getLocalText.s("Update all & generate"),
                  onPressed: ctrl.busy ? null : () => unawaited(_updateAll()),
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: 'Вставить из буфера',
                  onPressed: ctrl.busy
                      ? null
                      : () => unawaited(_pasteFromClipboard()),
                  icon: const Icon(Icons.content_paste_rounded),
                ),
              ],
            ),
            body: Column(
              children: [
                _buildInputBar(ctrl),
                if (ctrl.lastError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ParseInputErrorBanner(ctrl.lastError!),
                  ),
                if (ctrl.progressMessage != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(ctrl.progressMessage!.render())),
                      ],
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(



                    onRefresh: () async {
                      if (ctrl.busy) return;
                      await _updateAll();
                    },
                    child: _buildList(ctrl),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInputBar(SubscriptionController ctrl) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              onChanged: (_) => _onInputForHighlightDismiss(),
              decoration: InputDecoration(
                hintText: 'Ссылка подписки или приглашение HateVPN',
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: ctrl.busy ? null : () => unawaited(_add()),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }

  void _showContextMenu(
    BuildContext context,
    int index,
    SubscriptionEntry entry,
  ) {
    showEntryContextMenu(
      context,
      index,
      entry,
      subController: widget.subController,
      autoUpdater: widget.autoUpdater,
    );
  }

  Future<void> _launchUrl(String url) async {
    final opened = await UrlLauncher.open(url);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(getLocalText.s("Copied: %s", url))),
      );
    }
  }

  Future<void> _pickPublicTestServer() async {
    await pickPublicTestServer(
      context,
      onSelectSource: (source) => _inputController.text = source,
    );
  }







  List<_SourceRow> _rows(SubscriptionController ctrl) {
    final byId = <String, int>{
      for (var i = 0; i < ctrl.entries.length; i++) ctrl.entries[i].id: i,
    };
    if (_sources.isEmpty) {
      return [
        for (var i = 0; i < ctrl.entries.length; i++)
          _SourceRow.entry(ctrl.entries[i], i),
      ];
    }
    final rows = <_SourceRow>[];
    for (final e in _sources) {
      switch (e) {
        case ChainEntry(:final chain):
          rows.add(_SourceRow.chain(chain));
        case ContainerEntry(:final list):

          final at = byId[list.id];
          if (at != null) rows.add(_SourceRow.entry(ctrl.entries[at], at));
        case OpaqueEntry():


          break;
      }
    }
    return rows;
  }

  Widget _buildList(SubscriptionController ctrl) {
    if (_rows(ctrl).isEmpty) {
      return SubscriptionsEmptyState(
        busy: ctrl.busy,
        onPickPublicTestServer: null,
      );
    }
    final rows = _rows(ctrl);
    return ReorderableListView.builder(



      scrollController: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),


      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        MediaQuery.of(context).padding.bottom + 24 + _snackBarClearance,
      ),
      buildDefaultDragHandles: false,
      itemCount: rows.length,
      onReorderItem: (oldIndex, newIndex) {
        _onUserInteractionDismissHighlight();

        unawaited(_reorderRows(ctrl, oldIndex, newIndex));
      },
      itemBuilder: (context, i) {
        final row = rows[i];
        final chain = row.chain;
        if (chain != null) {
          return KeyedSubtree(
            key: ValueKey('chain:${chain.tag}'),
            child: ChainEntryTile(
              dragIndex: i,
              chain: chain,
              onTap: () => unawaited(_editChain(chain)),
              onToggle: () => unawaited(_toggleChain(chain)),
            ),
          );
        }
        final entry = row.entry!;
        final at = row.entryIndex;
        final highlighted = _highlightedEntryId == entry.id;
        final showNewBadge =
            highlighted &&
            _highlightMode == _HighlightMode.newEntry &&
            _highlightOpacity > 0;
        final cs = Theme.of(context).colorScheme;


        return KeyedSubtree(
          key: ValueKey(entry.id),
          child: AnimatedContainer(
            key: _tileKey(entry.id),
            duration: const Duration(milliseconds: 400),
            decoration: highlighted
                ? BoxDecoration(
                    color: cs.primaryContainer.withValues(
                      alpha: 0.5 * _highlightOpacity,
                    ),
                    border: _highlightMode == _HighlightMode.focus
                        ? Border(left: BorderSide(color: cs.primary, width: 3))
                        : null,
                  )
                : null,



            child: Material(
              type: MaterialType.transparency,
              child: SubscriptionEntryTile(
                dragIndex: i,
                entry: entry,
                subController: widget.subController,
                showNewBadge: showNewBadge,
                onToggle: () {
                  _onUserInteractionDismissHighlight();
                  unawaited(widget.subController.toggleAt(at));
                },
                onLaunchUrl: _launchUrl,
                onLongPress: (context) => _showContextMenu(context, at, entry),
                onTap: (context) {
                  _onUserInteractionDismissHighlight();

                  if (entry.list is FolderServers) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FolderDetailScreen(
                          entry: entry,
                          controller: widget.subController,
                        ),
                      ),
                    );
                    return;
                  }
                  final isDirectServer =
                      entry.url.isEmpty && entry.connections.isNotEmpty;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => isDirectServer
                          ? NodeSettingsScreen(
                              entry: entry,
                              index: at,
                              subController: widget.subController,
                            )
                          : SubscriptionDetailScreen(
                              entry: entry,
                              controller: widget.subController,
                            ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }








  Future<void> _reorderRows(
    SubscriptionController ctrl,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex == newIndex) return;
    final rows = _rows(ctrl);
    if (oldIndex < 0 || oldIndex >= rows.length) return;
    if (newIndex < 0 || newIndex >= rows.length) return;
    final moved = [...rows];
    moved.insert(newIndex, moved.removeAt(oldIndex));

    final oldChainTags = [
      for (final r in rows)
        if (r.chain != null) r.chain!.tag,
    ];
    final newChainTags = [
      for (final r in moved)
        if (r.chain != null) r.chain!.tag,
    ];

    await ctrl.applySourceOrder([
      for (final r in moved)
        if (r.chain != null)
          sourceKeyForChainOf(r.chain!.tag)
        else
          sourceKeyForIdOf(r.entry!.id),
    ]);
    await _loadSourceOrder();
    if (!mounted) return;
    var chainsMoved = oldChainTags.length != newChainTags.length;
    if (!chainsMoved) {
      for (var i = 0; i < oldChainTags.length; i++) {
        if (oldChainTags[i] != newChainTags[i]) {
          chainsMoved = true;
          break;
        }
      }
    }
    if (chainsMoved) await _regenerateAndSave();
  }
}


enum _HighlightMode { none, focus, newEntry }





class _SourceRow {
  const _SourceRow.entry(this.entry, this.entryIndex) : chain = null;
  const _SourceRow.chain(this.chain) : entry = null, entryIndex = -1;

  final SubscriptionEntry? entry;



  final int entryIndex;
  final SourceChain? chain;
}
