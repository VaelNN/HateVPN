import 'package:flutter/material.dart';

import '../models/direction.dart';
import '../services/ui_helpers.dart';
import 'home/filter_widgets.dart' show NegateToggle;
import '../models/source_replace.dart';
import '../services/l10n/locale_controller.dart';
import '../widgets/safe_bottom.dart';
import '../widgets/urltest_idle_hint.dart';








class DirectionEditScreen extends StatefulWidget {
  const DirectionEditScreen({
    super.key,
    required this.initial,
    required this.canDelete,
    required this.allNodeTags,
    this.directionsAbove = const [],
    this.foldCandidates = const [],
  });

  final Direction initial;


  final bool canDelete;


  final List<String> allNodeTags;






  final List<Direction> directionsAbove;





  final List<FoldCandidate> foldCandidates;

  @override
  State<DirectionEditScreen> createState() => _DirectionEditScreenState();
}

class _DirectionEditScreenState extends State<DirectionEditScreen> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _nodeFilterCtrl;
  late final TextEditingController _defaultFilterCtrl;
  late final TextEditingController _autoUrlCtrl;
  late final TextEditingController _autoIntervalCtrl;
  late final TextEditingController _autoToleranceCtrl;
  late final TextEditingController _autoIdleCtrl;

  late final TextEditingController _autoPoolCtrl;
  late final TextEditingController _autoPoolToleranceCtrl;

  late bool _includeDirect;
  late bool _includeBlock;




  late Set<String> _include;
  late bool _isDetour;
  late bool _interrupt;
  late bool _nodeFilterInvert;
  late bool _autoEnabled;
  late bool _autoInterrupt;

  late UrltestMode _autoMode;
  late Set<StickyHashKey> _autoSticky;

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    _labelCtrl = TextEditingController(text: c.label);
    _nodeFilterCtrl = TextEditingController(text: c.nodeFilter);
    _defaultFilterCtrl = TextEditingController(text: c.defaultFilter);
    _includeDirect = c.includeDirect;
    _includeBlock = c.includeBlock;
    _include = c.include.toSet();
    _isDetour = c.isDetour;
    _interrupt = c.interruptExistConnections;
    _nodeFilterInvert = c.nodeFilterInvert;
    _autoEnabled = c.auto != null;

    final a = c.auto ?? const DirectionAuto();
    _autoUrlCtrl = TextEditingController(text: a.url);
    _autoIntervalCtrl = TextEditingController(text: a.interval);
    _autoToleranceCtrl = TextEditingController(text: a.tolerance.toString());
    _autoIdleCtrl = TextEditingController(text: a.idleTimeout);
    _autoInterrupt = a.interruptExistConnections;

    _autoMode = a.mode;
    _autoPoolCtrl = TextEditingController(text: a.pool.toString());
    _autoPoolToleranceCtrl =
        TextEditingController(text: a.poolTolerance.toString());
    _autoSticky = a.stickyHash.toSet();

    for (final ctrl in [
      _labelCtrl,
      _nodeFilterCtrl,
      _defaultFilterCtrl,
      _autoUrlCtrl,
      _autoIntervalCtrl,
      _autoToleranceCtrl,
      _autoIdleCtrl,
      _autoPoolCtrl,
      _autoPoolToleranceCtrl,
    ]) {
      ctrl.addListener(_onAnyChange);
    }
  }

  @override
  void dispose() {
    for (final ctrl in [
      _labelCtrl,
      _nodeFilterCtrl,
      _defaultFilterCtrl,
      _autoUrlCtrl,
      _autoIntervalCtrl,
      _autoToleranceCtrl,
      _autoIdleCtrl,
      _autoPoolCtrl,
      _autoPoolToleranceCtrl,
    ]) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _onAnyChange() => setState(() {});



  Direction _snapshot() {
    final c = widget.initial;
    return c.copyWith(
      label: _labelCtrl.text.trim().isEmpty
          ? c.tag
          : _labelCtrl.text.trim(),
      includeDirect: _includeDirect,
      includeBlock: _includeBlock,



      include: _includeSnapshot(),
      isDetour: _isDetour,
      nodeFilter: _nodeFilterCtrl.text.trim(),
      nodeFilterInvert: _nodeFilterInvert,
      defaultFilter: _defaultFilterCtrl.text.trim(),
      interruptExistConnections: _interrupt,
      clearAuto: !_autoEnabled,
      auto: _autoEnabled
          ? DirectionAuto(
              url: _autoUrlCtrl.text.trim(),
              interval: _autoIntervalValue,




              tolerance: clampDirectionTolerance(
                  int.tryParse(_autoToleranceCtrl.text.trim()) ?? 50),
              idleTimeout: _autoIdleValue,
              interruptExistConnections: _autoInterrupt,


              mode: _autoMode,
              pool: clampDirectionPool(
                  int.tryParse(_autoPoolCtrl.text.trim()) ?? 3),
              poolTolerance: clampDirectionTolerance(
                  int.tryParse(_autoPoolToleranceCtrl.text.trim()) ?? 0),

              stickyHash: StickyHashKey.values
                  .where(_autoSticky.contains)
                  .toList(),
            )
          : null,
    );
  }






  List<String> _includeSnapshot() {
    final candidates = [
      for (final d in widget.directionsAbove) d.tag,
      for (final f in widget.foldCandidates) f.tag,
    ];
    final live = candidates.toSet();
    final out = <String>[
      for (final t in widget.initial.include)
        if (live.contains(t) && _include.contains(t)) t,
    ];
    for (final t in candidates) {
      if (_include.contains(t) && !out.contains(t)) out.add(t);
    }
    return out;
  }

  bool _isDirty() {
    final s = _snapshot();
    final i = widget.initial;
    return s.label != i.label ||
        s.includeDirect != i.includeDirect ||
        s.includeBlock != i.includeBlock ||
        !_sameTags(s.include, i.include) ||
        s.isDetour != i.isDetour ||
        s.nodeFilter != i.nodeFilter ||
        s.nodeFilterInvert != i.nodeFilterInvert ||
        s.defaultFilter != i.defaultFilter ||
        s.interruptExistConnections != i.interruptExistConnections ||
        (s.auto == null) != (i.auto == null) ||
        (s.auto != null &&
            i.auto != null &&
            (s.auto!.url != i.auto!.url ||
                s.auto!.interval != i.auto!.interval ||
                s.auto!.tolerance != i.auto!.tolerance ||
                s.auto!.idleTimeout != i.auto!.idleTimeout ||
                s.auto!.interruptExistConnections !=
                    i.auto!.interruptExistConnections ||

                s.auto!.mode != i.auto!.mode ||
                s.auto!.pool != i.auto!.pool ||
                s.auto!.poolTolerance != i.auto!.poolTolerance ||
                !_sameSticky(s.auto!.stickyHash, i.auto!.stickyHash)));
  }





  List<Widget> _includeSection(ColorScheme cs) {
    if (widget.directionsAbove.isEmpty && widget.foldCandidates.isEmpty) {
      return const [];
    }
    return [
      if (widget.directionsAbove.isNotEmpty) ...[
      const Divider(height: 20),
      Text(getLocalText.s("Other directions"),
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      Text(getLocalText.s("only directions listed above this one"),
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      const SizedBox(height: 4),
      for (final d in widget.directionsAbove)
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          visualDensity: VisualDensity.compact,
          title: Text(d.displayLabel, style: const TextStyle(fontSize: 14)),
          subtitle: Text(d.tag,
              style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: cs.onSurfaceVariant)),
          value: _include.contains(d.tag),
          onChanged: (v) => _toggleInclude(d.tag, v ?? false),
        ),
      ],

      if (widget.foldCandidates.isNotEmpty) ...[
        const Divider(height: 20),
        Text(getLocalText.s("Replace groups"),
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        Text(getLocalText.s("a folder or subscription replaced with one group"),
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        const SizedBox(height: 4),
        for (final f in widget.foldCandidates)
          CheckboxListTile(
            key: ValueKey('direction-include-fold-${f.tag}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            visualDensity: VisualDensity.compact,
            title: Text(f.tag, style: const TextStyle(fontSize: 14)),
            subtitle: Text(f.source,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            value: _include.contains(f.tag),
            onChanged: (v) => _toggleInclude(f.tag, v ?? false),
          ),
      ],
    ];
  }

  void _toggleInclude(String tag, bool on) => setState(() {
        on ? _include.add(tag) : _include.remove(tag);
      });



  static bool _sameTags(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }



  static bool _sameSticky(List<StickyHashKey> a, List<StickyHashKey> b) =>
      a.length == b.length && a.toSet().containsAll(b);

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
    Navigator.pop(context, DirectionEditResult.saved(_snapshot()));
  }

  Future<void> _delete() async {
    final confirmed = await showDeleteConfirmDialog(
      context,
      title: getLocalText.s("Delete direction?"),
      message: getLocalText.s(
          "Remove \"%1\$s\" (%2\$s)? References to it fall back to vpn-1.",
          widget.initial.label,
          widget.initial.tag),
    );
    if (confirmed == true && mounted) {
      Navigator.pop(context, DirectionEditResult.deleted());
    }
  }




  RegExp? _compile(String pattern) {
    if (pattern.isEmpty) return null;
    try {



      return RegExp(pattern, caseSensitive: false);
    } catch (_) {
      return null;
    }
  }



  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final c = widget.initial;
    final dirty = _isDirty();

    final nodeFilterText = _nodeFilterCtrl.text.trim();


    final re = _compile(nodeFilterText);
    final nodeFilterValid = nodeFilterText.isEmpty || re != null;

    final matchedNodes = nodeFilterText.isEmpty
        ? widget.allNodeTags
        : (re == null
            ? widget.allNodeTags
            : widget.allNodeTags
                .where((t) => re.hasMatch(t) != _nodeFilterInvert)
                .toList());

    final defaultText = _defaultFilterCtrl.text.trim();
    final defaultRe = _compile(defaultText);
    final defaultValid = defaultText.isEmpty || defaultRe != null;
    final defaultPick = (defaultText.isEmpty || defaultRe == null)
        ? null
        : _firstMatch(matchedNodes, defaultRe);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(getLocalText.s("Edit direction · %s", c.tag)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleBack,
          ),
          actions: [
            if (widget.canDelete)
              IconButton(
                tooltip: getLocalText.s("Delete direction"),
                icon: Icon(Icons.delete_outline, color: cs.error),
                onPressed: _delete,
              ),
            IconButton(
              tooltip: getLocalText.s("Save"),
              icon: Icon(Icons.check,
                  color: dirty ? cs.primary : cs.onSurfaceVariant),
              onPressed: _save,
            ),
          ],
        ),


        body: Theme(
          data: Theme.of(context).copyWith(
            inputDecorationTheme:
                Theme.of(context).inputDecorationTheme.copyWith(
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant.withAlpha(110),
                      ),
                    ),
          ),
          child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32).withSafeBottom(context),
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
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),






            _sectionHeader(
                theme,
                getLocalText.s("What goes into this direction"),
                getLocalText.s("options offered in the selector")),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              visualDensity: VisualDensity.compact,
              title: Text(getLocalText.s("Include direct-out"),
                  style: const TextStyle(fontSize: 14)),
              subtitle: Text(getLocalText.s("direct connection option in the selector"),
                  style: const TextStyle(fontSize: 11)),
              value: _includeDirect,
              onChanged: (v) => setState(() => _includeDirect = v ?? false),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              visualDensity: VisualDensity.compact,
              title: Text(getLocalText.s("Include block"),
                  style: const TextStyle(fontSize: 14)),
              subtitle: Text(getLocalText.s("drop traffic option in the selector"),
                  style: const TextStyle(fontSize: 11)),
              value: _includeBlock,
              onChanged: (v) => setState(() => _includeBlock = v ?? false),
            ),




            ...(_includeSection(cs)),
            const SizedBox(height: 12),




            _sectionHeader(theme, getLocalText.s("Behavior"),
                getLocalText.s("how this direction acts when used")),





            if (!c.isRequired)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                visualDensity: VisualDensity.compact,
                title: Text(getLocalText.s("Use as detour"),
                    style: const TextStyle(fontSize: 14)),
                subtitle: Text(getLocalText.s("can be picked as a detour target for servers and folders"),
                    style: const TextStyle(fontSize: 11)),
                value: _isDetour,



                onChanged: (v) => setState(() {
                  _isDetour = v ?? false;
                  _labelCtrl.text = Direction.normalizeLabel(
                      _labelCtrl.text.trim(), _isDetour);
                }),
              ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              visualDensity: VisualDensity.compact,
              title: Text(getLocalText.s("Interrupt connections on switch"),
                  style: const TextStyle(fontSize: 14)),
              value: _interrupt,
              onChanged: (v) => setState(() => _interrupt = v ?? false),
            ),
            const Divider(height: 24),



            Text(getLocalText.s("Node filter (regex)"),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: NegateToggle(
                    active: _nodeFilterInvert,
                    onToggle: () => setState(
                        () => _nodeFilterInvert = !_nodeFilterInvert),
                    tooltip: getLocalText.s("Exclude matching (invert)"),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _nodeFilterCtrl,
                    decoration: InputDecoration(
                      hintText: getLocalText.s("e.g. 🇩🇪|🇳🇱 — empty = all nodes"),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      errorText: nodeFilterValid ? null : 'Invalid regex',
                      errorStyle: const TextStyle(fontSize: 10),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _previewLine(
              cs,
              widget.allNodeTags.isEmpty
                  ? 'No node snapshot (connect to preview)'
                  : '${_nodeFilterInvert ? "excluded → " : ""}matched: '
                      '${matchedNodes.length} / ${widget.allNodeTags.length} nodes',
            ),
            const SizedBox(height: 16),


            Text(getLocalText.s("Default (regex)"),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            TextField(
              controller: _defaultFilterCtrl,
              decoration: InputDecoration(
                hintText: getLocalText.s("first matching node becomes default"),
                border: const OutlineInputBorder(),
                isDense: true,
                errorText: defaultValid ? null : 'Invalid regex',
                errorStyle: const TextStyle(fontSize: 10),
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            if (defaultText.isNotEmpty)
              _previewLine(
                cs,
                defaultPick == null
                    ? 'no match → first option used'
                    : '→ "$defaultPick"',
              ),
            const Divider(height: 24),


            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              visualDensity: VisualDensity.compact,
              title: Text(getLocalText.s("Include auto (urltest)"),
                  style: const TextStyle(fontSize: 14)),
              subtitle: Text(getLocalText.s("latency-tested twin of this direction"),
                  style: const TextStyle(fontSize: 11)),
              value: _autoEnabled,
              onChanged: (v) => setState(() => _autoEnabled = v ?? false),
            ),
            if (_autoEnabled) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _autoUrlCtrl,
                decoration: InputDecoration(
                  labelText: getLocalText.s("Test URL"),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              Row(



                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _autoIntervalCtrl,
                      decoration: InputDecoration(
                        labelText: getLocalText.s("Interval"),

                        hintText: '15m',


                        helperText: getLocalText.s("Larger values save battery"),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _autoToleranceCtrl,
                      keyboardType: TextInputType.number,


                      enabled: _autoMode == UrltestMode.leastTest,
                      decoration: InputDecoration(
                        labelText: getLocalText.s("Tolerance (ms)"),
                        border: const OutlineInputBorder(),
                        isDense: true,
                        helperText: _autoMode == UrltestMode.roundRobin
                            ? getLocalText.s("used in Fastest mode")
                            : null,
                        helperStyle: const TextStyle(fontSize: 10),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _autoIdleCtrl,
                decoration: InputDecoration(
                  labelText: getLocalText.s("Idle timeout"),

                  hintText: '30m',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 13),
              ),



              if (urltestIdleRaiseTarget(_autoIntervalValue, _autoIdleValue)
                  case final target?) ...[
                const SizedBox(height: 4),
                UrltestIdleRaiseHint(
                  key: const ValueKey('direction-auto-idle-raise-hint'),
                  target: target,
                ),
              ],
              const SizedBox(height: 12),




              Text(getLocalText.s("Mode"),
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              SegmentedButton<UrltestMode>(
                segments: [
                  ButtonSegment(
                    value: UrltestMode.leastTest,
                    label: Text(getLocalText.s("Fastest")),
                    icon: const Icon(Icons.bolt, size: 16),
                  ),
                  ButtonSegment(
                    value: UrltestMode.roundRobin,
                    label: Text(getLocalText.s("Load balance")),
                    icon: const Icon(Icons.hub_outlined, size: 16),
                  ),
                ],
                selected: {_autoMode},
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
                ),
                onSelectionChanged: (s) =>
                    setState(() => _autoMode = s.first),
              ),
              const SizedBox(height: 4),
              _previewLine(
                cs,
                _autoMode == UrltestMode.leastTest
                    ? 'single best server by latency'
                    : 'spread connections across a pool of servers',
              ),
              if (_autoMode == UrltestMode.roundRobin) ..._balancerControls(cs),
              const SizedBox(height: 4),

              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                visualDensity: VisualDensity.compact,
                title: Text(getLocalText.s("Interrupt connections on switch"),
                    style: const TextStyle(fontSize: 14)),
                value: _autoInterrupt,
                onChanged: (v) => setState(() => _autoInterrupt = v ?? false),
              ),
            ],
          ],
          ),
        ),
      ),
    );
  }

  Widget _previewLine(ColorScheme cs, String text) => Text(
        text,
        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
      );





  Widget _sectionHeader(ThemeData theme, String title, String description) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 2),
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





  List<Widget> _balancerControls(ColorScheme cs) {
    final nodeCount = widget.allNodeTags.length;
    return [
      const SizedBox(height: 10),
      _previewLine(cs, '15m interval recommended for large pools'),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _autoPoolCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: getLocalText.s("Pool size"),
                border: const OutlineInputBorder(),
                isDense: true,
                helperText: nodeCount > 0
                    ? getLocalText.plural("of %d nodes", nodeCount)
                    : null,
                helperStyle: const TextStyle(fontSize: 10),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _autoPoolToleranceCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: getLocalText.s("Pool tolerance (ms)"),
                border: const OutlineInputBorder(),
                isDense: true,
                helperText: getLocalText.s("0 = keep pool full"),
                helperStyle: const TextStyle(fontSize: 10),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Text(getLocalText.s("Sticky session by"),
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      const SizedBox(height: 4),


      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final k in StickyHashKey.values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(_stickyLabel(k),
                      style: const TextStyle(fontSize: 12)),
                  selected: _autoSticky.contains(k),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (sel) => setState(() {
                    if (sel) {
                      _autoSticky.add(k);
                    } else {
                      _autoSticky.remove(k);
                    }
                  }),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 2),
      _previewLine(
        cs,
        _autoSticky.isEmpty
            ? 'none selected → no stickiness (pure rotation)'
            : 'sessions stick to a server by the selected keys',
      ),
    ];
  }


  static String _stickyLabel(StickyHashKey k) {
    switch (k) {
      case StickyHashKey.process:
        return 'process';
      case StickyHashKey.domain:
        return 'domain';
      case StickyHashKey.sourceIp:
        return 'source ip';
      case StickyHashKey.destIp:
        return 'dest ip';
      case StickyHashKey.destPort:
        return 'dest port';
    }
  }



  String get _autoIntervalValue {
    final v = _autoIntervalCtrl.text.trim();
    return v.isEmpty ? '5m' : v;
  }

  String get _autoIdleValue {
    final v = _autoIdleCtrl.text.trim();
    return v.isEmpty ? '30m' : v;
  }

  static String? _firstMatch(List<String> tags, RegExp re) {
    for (final t in tags) {
      if (re.hasMatch(t)) return t;
    }
    return null;
  }
}


class DirectionEditResult {
  const DirectionEditResult._({this.saved, this.wasDeleted = false});
  final Direction? saved;
  final bool wasDeleted;

  factory DirectionEditResult.saved(Direction direction) =>
      DirectionEditResult._(saved: direction);
  factory DirectionEditResult.deleted() =>
      const DirectionEditResult._(wasDeleted: true);
}


Future<DirectionEditResult?> openDirectionEditor(
  BuildContext context, {
  required Direction initial,
  required bool canDelete,
  required List<String> allNodeTags,
  List<Direction> directionsAbove = const [],
  List<FoldCandidate> foldCandidates = const [],
}) =>
    Navigator.push<DirectionEditResult>(
      context,
      MaterialPageRoute(
        builder: (_) => DirectionEditScreen(
          initial: initial,
          canDelete: canDelete,
          allNodeTags: allNodeTags,
          directionsAbove: directionsAbove,
          foldCandidates: foldCandidates,
        ),
      ),
    );



typedef FoldCandidate = ({String tag, String source});


List<FoldCandidate> foldCandidatesOf(
        Iterable<({String name, SourceReplace? replace})> sources) =>
    [
      for (final s in sources)
        if (s.replace != null && s.replace!.tag.trim().isNotEmpty)
          (tag: s.replace!.tag, source: s.name),
    ];
