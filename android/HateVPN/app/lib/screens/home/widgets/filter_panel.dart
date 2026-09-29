import 'package:flutter/material.dart';

import '../filter_widgets.dart';
import '../node_filter_view_model.dart';
import '../node_list_presenter.dart';
import '../../../services/l10n/locale_controller.dart';












class FilterPanel extends StatefulWidget {
  const FilterPanel({
    super.key,
    required this.filter,
    required this.emojis,
    required this.availableProtocols,
    required this.availableVariants,
    required this.sourceOptions,
    this.onSaveRegex,
  });

  final NodeFilterViewModel filter;
  final List<String> emojis;
  final List<String> availableProtocols;


  final List<String> availableVariants;


  final List<(String, String)> sourceOptions;


  final void Function(String pattern, bool invert)? onSaveRegex;

  @override
  State<FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<FilterPanel>
    with SingleTickerProviderStateMixin {

  late final TabController _tab = TabController(length: 4, vsync: this);

  NodeFilterViewModel get f => widget.filter;

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  String _sourceName(String id) {
    for (final (sid, name) in widget.sourceOptions) {
      if (sid == id) return name;
    }
    return id;
  }



  static String _truncate(String s, [int max = 15]) =>
      s.length > max ? '${s.substring(0, max)}…' : s;


  List<Widget> _summaryChips() {
    final chips = <Widget>[];

    String neg(bool invert) => invert ? '!' : '';
    if (f.regexActive) {
      chips.add(InputChip(
        label: Text(
            '${neg(f.regexInvert)}/${_truncate(f.regexController.text)}/'),
        onPressed: () => _tab.animateTo(0),
        onDeleted: f.clearRegex,
      ));
    }
    for (final proto in f.enabledProtocols) {
      chips.add(InputChip(
        label: Text('${neg(f.protocolsInvert)}${protoLabel(proto)}'),
        onPressed: () => _tab.animateTo(1),
        onDeleted: () => f.toggleProtocol(proto),
      ));
    }

    for (final v in f.enabledVariants) {
      chips.add(InputChip(
        label: Text('${neg(f.variantsInvert)}${autoModeLabel(v)}'),
        onPressed: () => _tab.animateTo(1),
        onDeleted: () => f.toggleVariant(v),
      ));
    }
    for (final id in f.enabledSubscriptions) {
      chips.add(InputChip(
        label:
            Text('${neg(f.subscriptionsInvert)}${_truncate(_sourceName(id))}'),
        onPressed: () => _tab.animateTo(2),
        onDeleted: () => f.toggleSubscription(id),
      ));
    }
    final ms = f.activeMaxPingMs;
    if (ms != null) {
      chips.add(InputChip(
        label: Text(getLocalText.s("≤%dms", ms)),
        onPressed: () => _tab.animateTo(3),
        onDeleted: f.clearPing,
      ));
    }



    if (f.detourActive) {
      chips.add(InputChip(
        tooltip: f.detourHide
            ? getLocalText.s("Detour hidden")
            : getLocalText.s("Detour only"),
        label: f.detourHide
            ? _gearOffIcon()
            : const Icon(Icons.settings, size: 18),
        onPressed: () => _tab.animateTo(3),
        onDeleted: () => f.setDetourEnabled(false),
      ));
    }
    if (f.nonMatchingHidden) {
      chips.add(InputChip(
        tooltip: getLocalText.s("Non-matching hidden"),
        label: const Icon(Icons.visibility_off, size: 18),
        onPressed: () => _tab.animateTo(3),
        onDeleted: () => f.setShowNonMatching(true),
      ));
    }
    return chips;
  }



  Widget _gearOffIcon() {
    final c = Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      width: 20,
      height: 20,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.settings, size: 17, color: c),
          Transform.rotate(
            angle: -0.785,
            child: Container(width: 22, height: 2, color: c),
          ),
        ],
      ),
    );
  }

  Widget _dotTab(String label, bool active) {
    return Tab(
      height: 40,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (active) ...[
            const SizedBox(width: 5),
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Colors.amber,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );

  Widget _tabContent(int index) {
    switch (index) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RegexFilterField(
              controller: f.regexController,
              onChanged: f.onRegexChanged,
              valid: f.regexValid,
              invert: f.regexInvert,
              onInvertToggle: f.toggleRegexInvert,
              onClear: f.clearRegex,
              onSaveRegex: widget.onSaveRegex,
            ),
            if (widget.emojis.isNotEmpty) ...[
              const SizedBox(height: 8),
              EmojiChipsRow(
                emojis: widget.emojis,
                onTap: f.onEmojiChipTap,
                selected: f.selectedEmojis,
              ),
            ],
          ],
        );
      case 1:
        return widget.availableProtocols.isEmpty
            ? _hint('No protocols')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MultiSelectChipsRow(
                    options: [
                      for (final p in widget.availableProtocols)
                        (p, protoLabel(p)),
                    ],
                    enabled: f.enabledProtocols,
                    onToggle: f.toggleProtocol,
                    invert: f.protocolsInvert,
                    onInvertToggle: f.toggleProtocolsInvert,
                  ),
                  if (widget.availableVariants.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    MultiSelectChipsRow(
                      options: [
                        for (final v in widget.availableVariants)
                          (v, autoModeLabel(v)),
                      ],
                      enabled: f.enabledVariants,
                      onToggle: f.toggleVariant,
                      invert: f.variantsInvert,
                      onInvertToggle: f.toggleVariantsInvert,
                    ),
                  ],
                ],
              );
      case 2:
        return widget.sourceOptions.isEmpty
            ? _hint('No sources')
            : MultiSelectChipsRow(
                options: widget.sourceOptions,
                enabled: f.enabledSubscriptions,
                onToggle: f.toggleSubscription,
                invert: f.subscriptionsInvert,
                onInvertToggle: f.toggleSubscriptionsInvert,
              );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PingFilterField(
              controller: f.pingController,
              onChanged: f.onPingChanged,
              enabled: f.pingEnabled,
              onEnabledChanged: f.setPingEnabled,
              onClear: f.clearPing,
            ),



            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: Checkbox(
                      value: f.detourEnabled,
                      onChanged: (v) => f.setDetourEnabled(v ?? false),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 2),
                  NegateToggle(



                    active: f.detourHide,
                    onToggle: f.toggleDetourHide,
                    tooltip: getLocalText.s("Hide detour (on) / detour only (off)"),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(



                      f.detourHide
                          ? getLocalText.s("Hide detour servers")
                          : getLocalText.s("Show only detour servers"),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            FilterCheckboxRow(
              label: 'Show non-matching (dimmed)',
              value: f.showNonMatching,
              onChanged: f.setShowNonMatching,
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final summary = _summaryChips();
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.outlineVariant.withAlpha(128))),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tab,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                  tabs: [
                    _dotTab('Regex', f.regexActive),
                    _dotTab('Protocol', f.protocolActive || f.variantActive),
                    _dotTab('Sources', f.subscriptionActive),
                    _dotTab('Settings', f.settingsActive),
                  ],
                ),
              ),
              IconButton(
                tooltip: getLocalText.s("Close filters"),
                visualDensity: VisualDensity.compact,
                onPressed: f.togglePanel,
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),

          if (summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < summary.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    summary[i],
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),

          AnimatedBuilder(
            animation: _tab,
            builder: (_, _) => _tabContent(_tab.index),
          ),
        ],
      ),
    );
  }
}
