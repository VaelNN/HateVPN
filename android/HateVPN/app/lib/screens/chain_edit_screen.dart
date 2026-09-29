






















import 'package:flutter/material.dart';

import '../models/config_node.dart';
import '../models/direction.dart';
import '../models/node_link.dart';
import '../models/server_list.dart';
import '../models/source_chain.dart';
import '../services/builder/node_link_pool.dart';
import '../services/builder/node_link_resolve.dart';
import '../services/contract/chain_strip.dart';
import '../services/contract/registry_warning.dart';
import '../services/l10n/locale_controller.dart';
import '../services/ui_helpers.dart';
import '../widgets/reorder_grab_strip.dart';
import 'chain_edit/chain_form_validation.dart';
import 'chain_edit/chain_hop_candidate.dart';
import 'chain_edit/chain_hop_targets.dart';
import '../widgets/app_bottom_sheet.dart';


class ChainEditResult {
  const ChainEditResult._({this.saved, this.wasDeleted = false});

  final SourceChain? saved;
  final bool wasDeleted;

  factory ChainEditResult.saved(SourceChain chain) =>
      ChainEditResult._(saved: chain);
  factory ChainEditResult.deleted() => const ChainEditResult._(wasDeleted: true);
}


Future<ChainEditResult?> openChainEditor(
  BuildContext context, {
  required SourceChain initial,
  required ParsedConfig config,
  required List<Direction> directions,
  required List<SourceChain> chains,
  NodeLinkTargets? pool,
  List<ServerList> lists = const [],
}) =>
    Navigator.push<ChainEditResult>(
      context,
      MaterialPageRoute(
        builder: (_) => ChainEditScreen(
          initial: initial,
          config: config,
          directions: directions,
          chains: chains,
          pool: pool,
          lists: lists,
        ),
      ),
    );

class ChainEditScreen extends StatefulWidget {
  const ChainEditScreen({
    super.key,
    required this.initial,
    required this.config,
    required this.directions,
    required this.chains,
    this.pool,
    this.lists = const [],
  });

  final SourceChain initial;



  final NodeLinkTargets? pool;


  final List<ServerList> lists;



  final ParsedConfig config;

  final List<Direction> directions;



  final List<SourceChain> chains;

  @override
  State<ChainEditScreen> createState() => _ChainEditScreenState();
}

class _ChainEditScreenState extends State<ChainEditScreen> with SnackHelper {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _idleCtrl;



  late List<NodeLink> _hops;
  late bool _enabled;
  late bool? _stripEvasion;
  late Map<String, bool> _strip;



  bool _advancedOpen = false;

  late List<ChainHopCandidate> _cands;
  late Map<String, ChainHopCandidate> _lookup;

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    _labelCtrl = TextEditingController(text: c.label)..addListener(_onChange);
    _idleCtrl = TextEditingController(text: c.idleTimeout)
      ..addListener(_onChange);
    _hops = [...c.hops];
    _enabled = c.enabled;
    _stripEvasion = c.stripEvasion;
    _strip = {...c.strip};
    _cands = collectChainHopTargets(
      config: widget.config,
      directions: widget.directions,
      chains: widget.chains,
      selfTag: c.tag,
      pool: widget.pool,
    );
    _lookup = chainHopLookup(_cands);
  }


  String _shown(NodeLink hop) =>
      nodeLinkDisplay(hop, widget.pool, lists: widget.lists);

  @override
  void dispose() {
    _labelCtrl.dispose();
    _idleCtrl.dispose();
    super.dispose();
  }

  void _onChange() => setState(() {});

  SourceChain _snapshot() => widget.initial.copyWith(
        label: _labelCtrl.text.trim(),
        enabled: _enabled,
        hops: _hops,
        idleTimeout: _idleCtrl.text.trim(),
        stripEvasion: _stripEvasion,
        clearStripEvasion: _stripEvasion == null,
        strip: _strip,
      );

  bool _isDirty() {
    final s = _snapshot();
    final i = widget.initial;
    return s.label != i.label ||
        s.enabled != i.enabled ||
        s.idleTimeout != i.idleTimeout ||
        s.stripEvasion != i.stripEvasion ||
        !_sameHops(s.hops, i.hops) ||
        !_sameStrip(s.strip, i.strip);
  }

  static bool _sameHops(List<NodeLink> a, List<NodeLink> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _sameStrip(Map<String, bool> a, Map<String, bool> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  List<ChainFormIssue> _issues() => validateChainForm(
        ChainFormState.of(_snapshot(),
            pool: widget.pool, lists: widget.lists),
        ChainFormContext(
          candidates: _lookup,
          targetsKnown: chainTargetsKnown(widget.config),





          takenTags: _takenTags(),
          originalTag: widget.initial.tag,
        ),
      );



  Set<String> _takenTags() => {
        for (final d in widget.directions) d.tag,
        for (final c in widget.chains)
          if (c.tag != widget.initial.tag) c.tag,
        for (final t in widget.config.byTag.keys)
          if (t != widget.initial.tag) t,
      };

  Future<void> _handleBack() async {
    if (!_isDirty()) {
      Navigator.pop(context);
      return;
    }
    final action = await showUnsavedChangesDialog(context);
    if (!mounted) return;
    if (action == 'save') {
      _save();
    } else if (action == 'discard') {
      Navigator.pop(context);
    }
  }




  void _save() {
    final blockers = _issues().where((i) => i.blocks).toList();
    if (blockers.isNotEmpty) {
      showSnack(blockers.first.message);
      return;
    }
    Navigator.pop(context, ChainEditResult.saved(_snapshot()));
  }

  Future<void> _delete() async {
    final confirmed = await showDeleteConfirmDialog(
      context,
      title: getLocalText.s("Delete hop chain?"),
      message: getLocalText.s(
          "Remove \"%s\"? Other chains using it as a position will stop building until you fix them.",
          widget.initial.displayLabel),
    );
    if (confirmed == true && mounted) {
      Navigator.pop(context, ChainEditResult.deleted());
    }
  }




  void _refreshCandidates() {
    _cands = collectChainHopTargets(
      config: widget.config,
      directions: widget.directions,
      chains: widget.chains,
      selfTag: widget.initial.tag,
      pool: widget.pool,
    );
    _lookup = chainHopLookup(_cands);
  }

  Future<void> _addHop() async {
    setState(_refreshCandidates);
    final chosen = _hops.map(_shown).toSet();
    final options = [
      for (final c in _cands)
        if (!chosen.contains(c.tag) && c.offered) c,
    ];
    if (options.isEmpty) {
      showSnack(getLocalText.s(
          "Nothing left to add: every available target is already in the chain."));
      return;
    }
    final picked = await showAppBottomSheet<String>(
      context: context,
      isScrollControlled: true,



      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      builder: (ctx) => _HopPickerSheet(options: options),
    );
    if (picked == null || !mounted) return;

    final link = _lookup[picked]?.address ?? NodeLink(tag: picked);
    setState(() => _hops = [..._hops, link]);
  }

  void _removeHop(int index) {
    setState(() {
      final next = [..._hops]..removeAt(index);
      _hops = next;
    });
  }














  void _reorderHop(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    setState(() {
      final next = [..._hops];
      final hop = next.removeAt(oldIndex);
      next.insert(newIndex, hop);
      _hops = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = widget.initial;
    final issues = _issues();
    final canSave = chainFormCanSave(issues);
    final dirty = _isDirty();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(getLocalText.s("Hop chain · %s", c.tag)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleBack,
          ),
          actions: [
            IconButton(
              tooltip: getLocalText.s("Delete hop chain"),
              icon: Icon(Icons.delete_outline, color: cs.error),
              onPressed: _delete,
            ),
            IconButton(
              tooltip: getLocalText.s("Save"),
              icon: Icon(Icons.check,
                  color: !canSave
                      ? cs.onSurfaceVariant.withValues(alpha: 0.4)
                      : (dirty ? cs.primary : cs.onSurfaceVariant)),
              onPressed: canSave ? _save : null,
            ),
          ],
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, MediaQuery.of(context).padding.bottom + 32),
          children: [
            Text(c.tag,
                style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            TextField(
              controller: _labelCtrl,
              decoration: InputDecoration(
                labelText: getLocalText.s("Title"),
                hintText: getLocalText.s("optional — defaults to the tag"),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 14),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(getLocalText.s("Enabled"),
                  style: const TextStyle(fontSize: 14)),
              subtitle: Text(
                  getLocalText.s("A disabled chain is not built and cannot be used as a position"),
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),

            const SizedBox(height: 8),
            ..._issueBanners(issues, cs),

            const SizedBox(height: 8),
            Text(getLocalText.s("Positions"),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),



            Text(
                getLocalText.s(
                    "In packet order: the first position is the hop closest to you, the last one is what the destination sees."),
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            const SizedBox(height: 6),
            _hopsList(cs),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addHop,
                icon: const Icon(Icons.add, size: 18),
                label: Text(getLocalText.s("Add position")),
              ),
            ),

            const SizedBox(height: 8),
            _advancedSection(cs),
          ],
        ),
      ),
    );
  }

  List<Widget> _issueBanners(List<ChainFormIssue> issues, ColorScheme cs) {
    if (issues.isEmpty) return const [];
    return [
      for (final i in issues)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: switch (i.level) {
              ChainIssueLevel.blocking => cs.errorContainer,
              ChainIssueLevel.warning => cs.tertiaryContainer,
              ChainIssueLevel.info => cs.surfaceContainerHighest,
            },
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                switch (i.level) {
                  ChainIssueLevel.blocking => Icons.error_outline,
                  ChainIssueLevel.warning => Icons.warning_amber_outlined,
                  ChainIssueLevel.info => Icons.info_outline,
                },
                size: 18,
                color: i.level == ChainIssueLevel.blocking
                    ? cs.onErrorContainer
                    : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  i.message,
                  style: TextStyle(
                    fontSize: 12,
                    color: i.level == ChainIssueLevel.blocking
                        ? cs.onErrorContainer
                        : cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _hopsList(ColorScheme cs) {
    if (_hops.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(getLocalText.s("No positions yet — add at least two."),
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      );
    }



    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: _hops.length,
      onReorderItem: _reorderHop,
      itemBuilder: (ctx, i) =>
          KeyedSubtree(key: ValueKey('hop-${_hops[i]}'), child: _hopTile(i, cs)),
    );
  }

  Widget _hopTile(int index, ColorScheme cs) {
    final tag = _shown(_hops[index]);
    final cand = describeChainHop(tag, _lookup,
        targetsKnown: chainTargetsKnown(widget.config));
    final lost = cand.kind == ChainHopKind.unknown;
    final tile = ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 13,
        backgroundColor: lost ? cs.errorContainer : cs.secondaryContainer,
        child: Text('${index + 1}',
            style: TextStyle(
                fontSize: 12,
                color: lost ? cs.onErrorContainer : cs.onSecondaryContainer)),
      ),



      title: Text(tag,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: lost ? cs.error : null)),
      subtitle: Text(chainHopKindText(cand.kind),
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      trailing: IconButton(
        tooltip: getLocalText.s("Remove position"),
        icon: Icon(Icons.close, size: 18, color: cs.error),
        onPressed: () => _removeHop(index),
      ),
    );


    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReorderGrabStrip(index: index),
          Expanded(child: tile),
        ],
      ),
    );
  }

  Widget _advancedSection(ColorScheme cs) {


    final state = ChainFormState.of(_snapshot(),
        pool: widget.pool, lists: widget.lists);
    final keptByHop = {
      for (final u in chainHopUnstrips(
        stripEvasion: state.stripEvasion,
        patch: state.strip,
        hops: [for (final h in state.hops) (h, _lookup[h]?.body)],
      ))
        u.key,
    };
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: _advancedOpen,
        onExpansionChanged: (v) => _advancedOpen = v,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Text(getLocalText.s("Advanced"),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        children: [
          TextField(
            controller: _idleCtrl,
            decoration: InputDecoration(
              labelText: getLocalText.s("Idle timeout"),
              hintText: getLocalText.s("empty = core default (5m); 0s = keep until stop"),
              helperMaxLines: 2,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(getLocalText.s("Strip evasion tricks from links"),
                style: const TextStyle(fontSize: 14)),
            subtitle: Text(
                getLocalText.s(
                    "One-way DPI tricks make no sense on a link that dials through the previous hop."),
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),



            value: _snapshot().stripEvasionEnabled,
            onChanged: (v) => setState(() => _stripEvasion = v),
          ),
          const SizedBox(height: 4),
          Text(getLocalText.s("Per-key overrides"),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          for (final key in chainStripCatalog())
            _stripTile(key, cs, kept: keptByHop),
        ],
      ),
    );
  }










  Widget _stripTile(ChainStripKey entry, ColorScheme cs,
      {Set<String> kept = const {}}) {
    final key = entry.key;
    final explicit = _strip[key];
    final effective = !kept.contains(key) &&
        chainStripsKey(entry, stripEvasion: _stripEvasion, patch: _strip);
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      visualDensity: VisualDensity.compact,
      tristate: true,
      title: Text(key,
          style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
      subtitle: Text(
          entry.description(
              registryLangForTag(LocaleController.I.effectiveTag)),
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),

      value: explicit,
      onChanged: (v) => setState(() {
        final next = {..._strip};
        if (v == null) {
          next.remove(key);
        } else {
          next[key] = v;
        }
        _strip = next;
      }),
      secondary: Text(
          effective
              ? getLocalText.s("stripped")
              : getLocalText.s("kept"),
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
    );
  }

}



class _HopPickerSheet extends StatelessWidget {
  const _HopPickerSheet({required this.options});

  final List<ChainHopCandidate> options;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(getLocalText.s("Add position"),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
          Flexible(



            child: ListView(
              shrinkWrap: true,
              children: [
                for (final section in _sections(context))
                  ...section,
              ],
            ),
          ),
        ],
      ),
    );
  }



  List<List<Widget>> _sections(BuildContext context) {



    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    List<Widget> group(String title, List<ChainHopCandidate> items) {
      if (items.isEmpty) return const [];
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.primary)),
        ),
        for (final c in items)
          ListTile(
            title: Text(c.displayLabel.isNotEmpty ? c.displayLabel : c.tag,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: c.subline.isEmpty
                ? null
                : Text(
                    c.kind == ChainHopKind.chain
                        ? getLocalText.plural('%d hops', int.tryParse(c.subline) ?? 0)
                        : c.subline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: muted)),
            onTap: () => Navigator.pop(context, c.tag),
          ),
      ];
    }

    List<ChainHopCandidate> of(ChainHopKind k) =>
        [for (final c in options) if (c.kind == k) c];



    return [
      group(getLocalText.s("Directions"), of(ChainHopKind.direction)),
      group(getLocalText.s("Servers"), [
        ...of(ChainHopKind.node),
        ...of(ChainHopKind.unknown),
        ...of(ChainHopKind.pending),
      ]),
    ];
  }
}




String chainHopKindText(ChainHopKind kind) => switch (kind) {
      ChainHopKind.node => getLocalText.s("node"),
      ChainHopKind.group => getLocalText.s("group"),
      ChainHopKind.direction => getLocalText.s("direction"),
      ChainHopKind.chain => getLocalText.s("chain"),
      ChainHopKind.builtin => getLocalText.s("built-in"),
      ChainHopKind.pending => getLocalText.s("loading…"),
      ChainHopKind.unknown => getLocalText.s("not found"),
    };
