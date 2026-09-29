import 'dart:async';

import 'package:flutter/material.dart';

import '../../../controllers/home_controller.dart';
import '../../../controllers/subscription_controller.dart';
import '../../../models/home_state.dart';
import '../../../models/node_warning.dart';
import '../../../services/direction_mutations.dart';
import '../../../services/settings_storage.dart';
import '../../../services/haptic_service.dart';
import '../../../services/networks_direction.dart';
import '../../../services/subscription/auto_updater.dart';
import '../../../widgets/node_row.dart';
import '../../../widgets/node_view_item.dart';
import '../../../widgets/reorder_grab_strip.dart';
import '../../direction_edit_screen.dart';
import '../node_actions.dart';
import '../node_filter_view_model.dart';
import '../../../models/auto_select.dart';
import '../../../models/node_spec.dart';
import '../node_list_presenter.dart';
import '../special_node_display.dart';
import 'add_server_cta.dart';
import 'filter_panel.dart';
import '../../../services/l10n/locale_controller.dart';
import '../../../widgets/safe_bottom.dart';















bool showAddServerGuide({
  required bool tunnelUp,
  required bool configEmpty,
  required int configNodeCount,
  required bool anyServerNodes,
}) =>
    !tunnelUp && (configEmpty || (configNodeCount == 0 && !anyServerNodes));





const double kNodeListTwoColumnsMinWidth = 600;








int nodeListColumnCount(
  double width, {
  required bool isManual,
  bool twoColumnsEnabled = true,
}) =>
    (twoColumnsEnabled && !isManual && width >= kNodeListTwoColumnsMinWidth)
        ? 2
        : 1;









class HomeNodeList extends StatelessWidget {
  const HomeNodeList({
    super.key,
    required this.controller,
    required this.subController,
    required this.autoUpdater,
    required this.filter,
    required this.presenter,
    required this.state,
    required this.showEmptyGuide,
    required this.onRestoreFromBackup,
    required this.onTapToConnect,
    required this.rowKeyFor,
    required this.onSelectServer,
    required this.onViewPool,
  });

  final HomeController controller;
  final SubscriptionController subController;
  final AutoUpdater autoUpdater;
  final NodeFilterViewModel filter;
  final NodeListPresenter presenter;
  final HomeState state;



  final bool showEmptyGuide;
  final Future<void> Function() onRestoreFromBackup;
  final VoidCallback onTapToConnect;



  final GlobalKey Function(String tag) rowKeyFor;
  final void Function(String tag) onSelectServer;


  final void Function(String autoTag) onViewPool;

  @override
  Widget build(BuildContext context) {



    if (showEmptyGuide) {
      return Expanded(
        child: AddServerCta(
          controller: controller,
          subController: subController,
          autoUpdater: autoUpdater,
          onRestoreFromBackup: onRestoreFromBackup,
        ),
      );
    }


    if (state.showingNetworks) return _buildNetworksList(context);
    if (state.nodes.isEmpty) {


      if (state.configRaw.isEmpty) {
        return Expanded(
          child: AddServerCta(
            controller: controller,
            subController: subController,
            autoUpdater: autoUpdater,
            onRestoreFromBackup: onRestoreFromBackup,
          ),
        );
      }
      final cs = Theme.of(context).colorScheme;

      if (state.tunnelUp) {
        return Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.dns_outlined,
                      size: 48, color: cs.onSurfaceVariant.withAlpha(120)),
                  const SizedBox(height: 12),
                  Text(
                    getLocalText.s("No nodes in this direction.\nTry another one."),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
        );
      }


      final canStart = !state.busy &&
          state.tunnel != TunnelStatus.connecting &&
          state.tunnel != TunnelStatus.stopping;
      return Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: canStart
                  ? () {
                      HapticService.I.onConnectTap();
                      onTapToConnect();
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_circle_outline,
                        size: 64, color: cs.primary),
                    const SizedBox(height: 12),
                    Text(
                      getLocalText.s("Tap to connect"),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final data = presenter.computeListData(state);

    return Expanded(
      child: Column(
        children: [
          if (filter.panelExpanded)
            FilterPanel(
              filter: filter,
              emojis: data.emojis,
              availableProtocols: data.availableProtocols,
              availableVariants: data.availableVariants,
              sourceOptions: data.sourceOptions,


              onSaveRegex: (state.selectedGroup != null &&
                      state.groups.contains(state.selectedGroup))
                  ? (pattern, invert) =>
                      _saveRegexToDirection(context, pattern, invert)
                  : null,
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.pullToRefresh,











              child: _NodeListColumns(
                isManual: state.sortMode == NodeSortMode.manual,
                builder: (context, columns, scrollController) => columns > 1
                    ? _buildNodeGrid(
                        context,
                        columns: columns,
                        scrollController: scrollController,
                        displayList: data.displayList,
                        cache: data.cache,
                        matchingSet: data.matchingSet,
                        warningsByTag: data.warningsByTag,
                      )
                    : _buildReorderableNodeList(
                        context,
                        scrollController: scrollController,
                        displayList: data.displayList,
                        cache: data.cache,
                        matchingSet: data.matchingSet,
                        warningsByTag: data.warningsByTag,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }




  Widget _buildNetworksList(BuildContext context) {
    final dividerColor =
        Theme.of(context).colorScheme.outlineVariant.withAlpha(128);
    final model = state.activeModel;
    final tags = state.networksNodes;
    void openDetails(String tag) => viewOutboundJson(context, tag, state,
        subController: subController,
        homeController: controller,
        openNetwork: true);
    return Expanded(
      child: ListView.builder(
        key: const ValueKey('networks-list'),
        padding: const EdgeInsets.only(bottom: 56).withSafeBottom(context),
        itemCount: tags.length,
        itemBuilder: (ctx, i) {
          final tag = tags[i];
          final node = model[tag];
          final protoType = model.protocolOf(tag);
          return KeyedSubtree(
            key: rowKeyFor(tag),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: dividerColor, width: 1),
                ),
              ),
              child: NodeRow(
                item: NodeViewItem(
                  tag: tag,
                  active: false,
                  highlighted: false,
                  delay: null,
                  pingBusy: false,
                  tunnelUp: state.tunnelUp,
                  busy: state.busy,
                  urltestNow: null,
                  hasDetour: node?.detour != null,
                  outboundType: node?.type,
                  notificationWarnings: const <NodeWarning>[],
                  protocolLabel: protoType == null
                      ? null
                      : [
                          protoLabel(protoType),
                          ?node?.transportLabel,
                          ?node?.securityLabel,
                        ].join('·'),
                  tailnetState: tailnetRowState(
                    tunnelUp: state.tunnelUp,
                    tag: tag,
                    byTag: state.tailscaleStatus,
                  ),
                ),
                onHighlight: () => openDetails(tag),

                onActivate: () {},
                onPing: () {},
                onCopyUri: () =>
                    unawaited(copyNodeUri(context, tag, subController)),
                onViewJson: () => openDetails(tag),
              ),
            ),
          );
        },
      ),
    );
  }






  Widget _buildReorderableNodeList(
    BuildContext context, {
    required ScrollController scrollController,
    required List<String> displayList,
    required ParsedConfig cache,
    required Set<String> matchingSet,
    required Map<String, List<NodeWarning>> warningsByTag,
  }) {





    final pinnedTags = state.pinnedTagSet;
    int pinnedCount = 0;
    while (pinnedCount < displayList.length &&
        pinnedTags.contains(displayList[pinnedCount])) {
      pinnedCount++;
    }

    final dividerColor =
        Theme.of(context).colorScheme.outlineVariant.withAlpha(128);




    final isManual = state.sortMode == NodeSortMode.manual;

    return ReorderableListView.builder(
      scrollController: scrollController,



      padding: const EdgeInsets.only(bottom: 56).withSafeBottom(context),
      buildDefaultDragHandles: false,
      itemCount: displayList.length,
      onReorderItem: (oldIndex, newIndex) {


        if (oldIndex < pinnedCount) return;
        if (newIndex < pinnedCount) newIndex = pinnedCount;
        final restOnly = displayList.skip(pinnedCount).toList();
        final restOld = oldIndex - pinnedCount;
        final restNew = newIndex - pinnedCount;
        final moved = restOnly.removeAt(restOld);
        restOnly.insert(restNew, moved);
        controller.commitManualReorder(restOnly);
      },
      itemBuilder: (ctx, i) {
        final tag = displayList[i];
        final keyedRow = _buildNodeCell(
          context,
          tag,
          cache: cache,
          matchingSet: matchingSet,
          warningsByTag: warningsByTag,
          dividerColor: dividerColor,
        );

        if (i < pinnedCount) {
          return KeyedSubtree(key: ValueKey('node-$tag'), child: keyedRow);
        }


        if (isManual) {
          return KeyedSubtree(
            key: ValueKey('node-$tag'),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ReorderGrabStrip(index: i),
                  Expanded(child: keyedRow),
                ],
              ),
            ),
          );
        }


        return KeyedSubtree(
          key: ValueKey('node-$tag'),
          child: LayoutBuilder(
            builder: (ctx, c) => Stack(
              children: [
                keyedRow,
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: c.maxWidth * 0.08,






                  child: ReorderableDelayedDragStartListener(
                    index: i,




                    child: Container(color: Colors.transparent),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }










  Widget _buildNodeGrid(
    BuildContext context, {
    required int columns,
    required ScrollController scrollController,
    required List<String> displayList,
    required ParsedConfig cache,
    required Set<String> matchingSet,
    required Map<String, List<NodeWarning>> warningsByTag,
  }) {
    final dividerColor =
        Theme.of(context).colorScheme.outlineVariant.withAlpha(128);
    final rows = (displayList.length + columns - 1) ~/ columns;
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: 56).withSafeBottom(context),
      itemCount: rows,
      itemBuilder: (ctx, r) {
        final cells = <Widget>[];
        for (var c = 0; c < columns; c++) {
          final i = r * columns + c;
          final Widget cell = i < displayList.length
              ? _buildNodeCell(
                  context,
                  displayList[i],
                  cache: cache,
                  matchingSet: matchingSet,
                  warningsByTag: warningsByTag,
                  dividerColor: dividerColor,
                )
              : const SizedBox.shrink();
          cells.add(Expanded(
            child: c < columns - 1

                ? DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                          right: BorderSide(color: dividerColor, width: 1)),
                    ),
                    child: cell,
                  )
                : cell,
          ));
        }
        return IntrinsicHeight(
          key: ValueKey('node-row-${displayList[r * columns]}'),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: cells,
          ),
        );
      },
    );
  }




  Widget _buildNodeCell(
    BuildContext context,
    String tag, {
    required ParsedConfig cache,
    required Set<String> matchingSet,
    required Map<String, List<NodeWarning>> warningsByTag,
    required Color dividerColor,
  }) {
    final urltestNow = state.urltestNowOf(tag);
    final group = state.groupOf(tag);
    final isUrltestGroup =
        group != null && group.type.toLowerCase().contains('urltest');


    final isDirectionAuto = controller.isDirectionAutoTag(tag);


    final protoSrc = cache.protocolOf(tag) != null
        ? tag
        : (urltestNow != null && cache.protocolOf(urltestNow) != null
            ? urltestNow
            : null);
    final protoSrcNode = protoSrc != null ? cache[protoSrc] : null;
    final protoType = protoSrc != null ? cache.protocolOf(protoSrc) : null;
    final transport = protoSrcNode?.transportLabel;
    final security = protoSrcNode?.securityLabel;
    final outboundType = cache[tag]?.type;
    final notificationWarnings = _notificationWarningsForRow(
      outboundType: outboundType,
      isDirectionAuto: isDirectionAuto,
      warnings: warningsByTag[tag],
    );
    final row = DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: dividerColor, width: 1),
        ),
      ),
      child: NodeRow(
        item: NodeViewItem(
          tag: tag,
          active: tag == state.activeInGroup,
          highlighted: tag == state.highlightedNode,
          delay: state.delayOf(tag),

          delayIsForeign: state.delayIsForeign(tag),
          pingBusy: state.pingBusy[tag] == '…',


          endpointState: state.endpointStates[tag] ?? '',
          tunnelUp: state.tunnelUp,
          busy: state.busy,



          urltestNow:
              cache.rawOf(tag)?['balancer'] != null ? null : urltestNow,
          hasDetour: cache[tag]?.detour != null,
          outboundType: outboundType,
          notificationWarnings: notificationWarnings,

          isDirectionAuto: isDirectionAuto,



          autoGroupLabel: isDirectionAuto
              ? null
              : _autoLabelWithBadges(
                  controller, subController, cache, tag),
          protocolLabel: protoType == null
              ? null
              : [
                  protoLabel(protoType),
                  ?transport,
                  ?security,
                ].join('·'),
          matches: matchingSet.contains(tag),


          isSickRoot: state.sickRoots.containsKey(tag),
        ),
        onHighlight: () => controller.setHighlightedNode(tag),
        onActivate: () => unawaited(controller.switchNode(tag)),
        onPing: () => unawaited(controller.runNodeUrltest(tag)),


        onCopyUri: () =>
            unawaited(copyNodeUri(context, tag, subController)),
        onViewJson: () => viewOutboundJson(context, tag, state,
            subController: subController, homeController: controller),
        onRunUrltest: isUrltestGroup
            ? () => unawaited(controller.runGroupUrltest(tag))
            : null,


        onSelectServer:
            urltestNow != null ? () => onSelectServer(urltestNow) : null,


        onViewPool: (isUrltestGroup && controller.isRoundRobinAuto(tag))
            ? () => onViewPool(tag)
            : null,




        onToggleEndpoint:
            state.tunnelUp && (state.endpointStates[tag] ?? '').isNotEmpty
                ? () => unawaited(toggleEndpoint(context, controller, tag))
                : null,
        onSickTap: state.sickRoots.containsKey(tag)
            ? () => viewOutboundJson(context, tag, state,
                subController: subController,
                homeController: controller,
                openDependents: true)
            : null,
      ),
    );


    return KeyedSubtree(key: rowKeyFor(tag), child: row);
  }






  Future<void> _saveRegexToDirection(
      BuildContext context, String pattern, bool invert) async {
    final tag = state.selectedGroup;
    if (tag == null) return;
    final directions = await SettingsStorage.getDirections();
    final idx = directions.indexWhere((c) => c.tag == tag);
    if (idx < 0 || !context.mounted) return;
    final direction = directions[idx];
    final label = direction.label.isNotEmpty ? direction.label : direction.tag;

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(getLocalText.s("Apply to %s", label)),
        content: Text(getLocalText.s("Use \"%s\" as…", pattern)),


        actionsAlignment: MainAxisAlignment.end,
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'node'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.primary,
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
            child: Text(getLocalText.s("Filter")),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'default'),
            child: Text(getLocalText.s("Default")),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(getLocalText.s("Cancel")),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;





    final seeded = choice == 'node'
        ? direction.copyWith(nodeFilter: pattern, nodeFilterInvert: invert)
        : direction.copyWith(defaultFilter: pattern);
    final allNodeTags = _allNodeTagsFromState();
    final result = await openDirectionEditor(
      context,
      initial: seeded,
      canDelete: !direction.isRequired,
      allNodeTags: allNodeTags,


      directionsAbove: idx <= 0 ? const [] : directions.sublist(0, idx),
      foldCandidates: foldCandidatesOf([
        for (final e in subController.entries)
          (name: e.displayName, replace: e.list.replace),
      ]),
    );
    if (result == null || result.saved == null || !context.mounted) return;





    final healed = await DirectionMutations.update(result.saved!, subController);
    await controller.refreshDirectionLabels();
    if (!context.mounted) return;
    final config = await subController.generateConfig();
    if (config != null && context.mounted) {
      await controller.saveParsedConfig(config);
    }
    if (!context.mounted) return;





    final healedParts = DirectionMutations.healMessageParts(healed);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(healedParts.isEmpty
              ? getLocalText.s("Saved direction \"%s\"", label)
              : getLocalText.s("Saved direction \"%1\$s\" — %2\$s", label,
                  healedParts.join('; ')))),
    );


    if (state.tunnelUp && !await SettingsStorage.getAutoReloadOnChange()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(getLocalText.s("Restart VPN to apply changes"))),
      );
    }
  }



  List<NodeWarning>? _notificationWarningsForRow({
    required String? outboundType,
    required bool isDirectionAuto,
    required List<NodeWarning>? warnings,
  }) {
    final special = specialNodeDisplayForType(outboundType);
    if (special != null) {
      if (outboundType == 'urltest' && !isDirectionAuto) {
        return warnings ?? const [];
      }
      return null;
    }
    return warnings ?? const [];
  }



  List<String> _allNodeTagsFromState() {
    final groupTags = state.ccGroups.map((g) => g.tag).toSet();
    final seen = <String>{};
    final out = <String>[];
    for (final g in state.ccGroups) {
      for (final item in g.items) {
        if (groupTags.contains(item.tag)) continue;
        if (seen.add(item.tag)) out.add(item.tag);
      }
    }
    return out;
  }
}






String? _autoLabelWithBadges(
  HomeController controller,
  SubscriptionController subs,
  ParsedConfig cache,
  String tag,
) {
  final base = autoGroupLabel(cache.rawOf(tag));
  if (base == null) return null;


  final badge = poolBadgeOf(subs, tag);
  if (badge.isEmpty) return base;
  final slots = controller.poolSlots(tag);
  if (slots == null || slots.isEmpty) return base;
  final badges = poolBadges([for (final s in slots) s.tag], badge);
  return badges.isEmpty ? base : '$base $badges';
}










List<(String, String)> _autoSpecs = const [];
List<List<NodeSpec>>? _autoSpecsSource;




@visibleForTesting
void resetPoolBadgeCache() {
  _autoSpecs = const [];
  _autoSpecsSource = null;
}

List<(String, String)> _autoSpecsOf(SubscriptionController subs) {


  final source = [for (final e in subs.entries) e.list.nodes];
  final cached = _autoSpecsSource;
  if (cached != null &&
      cached.length == source.length &&
      Iterable<int>.generate(source.length)
          .every((i) => identical(cached[i], source[i]))) {
    return _autoSpecs;
  }
  _autoSpecsSource = source;
  _autoSpecs = [
    for (final nodes in source)
      for (final n in nodes)
        if (n is AutoSelectSpec) (n.tag, n.poolBadge),
  ];
  return _autoSpecs;
}



@visibleForTesting
String poolBadgeOf(SubscriptionController subs, String tag) {
  for (final (specTag, badge) in _autoSpecsOf(subs)) {
    if (tag.endsWith(specTag)) return badge;
  }
  return kDefaultPoolBadge;
}






class _NodeListColumns extends StatefulWidget {
  const _NodeListColumns({required this.isManual, required this.builder});

  final bool isManual;
  final Widget Function(
    BuildContext context,
    int columns,
    ScrollController scrollController,
  ) builder;

  @override
  State<_NodeListColumns> createState() => _NodeListColumnsState();
}

class _NodeListColumnsState extends State<_NodeListColumns> {
  ScrollController _scroll = ScrollController();
  int? _columns;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {


    return ValueListenableBuilder<bool>(
      valueListenable: SettingsStorage.nodeListTwoColumns,
      builder: (context, twoColumnsEnabled, _) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = nodeListColumnCount(
            constraints.maxWidth,
            isManual: widget.isManual,
            twoColumnsEnabled: twoColumnsEnabled,
          );
          final prev = _columns;
          if (prev != null && prev != columns) {
            final old = _scroll;
            final offset = old.hasClients && old.positions.length == 1
                ? old.offset * prev / columns
                : 0.0;
            _scroll = ScrollController(initialScrollOffset: offset);


            WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
          }
          _columns = columns;
          return widget.builder(context, columns, _scroll);
        },
      ),
    );
  }
}
