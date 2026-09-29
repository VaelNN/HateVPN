import 'package:flutter/material.dart';

import '../../../controllers/home_controller.dart';
import '../../../controllers/subscription_controller.dart';
import '../../../models/home_state.dart';
import '../../routing_screen.dart';
import '../node_filter_view_model.dart';
import '../../../services/l10n/locale_controller.dart';








class NodesHeader extends StatelessWidget {
  const NodesHeader({
    super.key,
    required this.controller,
    required this.subController,
    required this.filter,
    required this.onSortLongPress,
  });

  final HomeController controller;
  final SubscriptionController subController;
  final NodeFilterViewModel filter;
  final VoidCallback onSortLongPress;

  static bool _isSortNonDefault(HomeState s) =>
      !s.pinDirect || !s.pinAuto || !s.resortOnManualPing;



  static int listCount(HomeState s) =>
      s.showingNetworks ? s.networksNodes.length : s.nodes.length;



  static bool showsListTools(HomeState s) => !s.showingNetworks;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => RoutingScreen(
                subController: subController,
                homeController: controller,
              ),
            ),
          );
        },
        child: Row(
          children: [
            Text(
              getLocalText.s("Nodes"),
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (listCount(state) > 0) ...[
              const SizedBox(width: 4),
              Text(
                '(${listCount(state)})',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const Spacer(),
            if (showsListTools(state)) ...[


              Tooltip(
                message: state.sortMode.label(),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    InkWell(
                      onTap: state.nodes.isEmpty
                          ? null
                          : controller.cycleSortMode,
                      onLongPress: state.nodes.isEmpty ? null : onSortLongPress,
                      borderRadius: BorderRadius.circular(18),
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: Center(
                          child: Icon(
                            state.sortMode.icon,
                            size: 20,
                            color: state.nodes.isEmpty
                                ? Theme.of(context).disabledColor
                                : null,
                          ),
                        ),
                      ),
                    ),
                    if (_isSortNonDefault(state))
                      Positioned(
                        right: 4,
                        top: 4,
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



              IconButton(
                tooltip: filter.panelExpanded
                    ? getLocalText.s("Hide filters")
                    : getLocalText.s("Show filters"),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: filter.togglePanel,
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      Icons.filter_list,
                      size: 20,
                      color: filter.hasActiveFilters
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    if (filter.hasActiveFilters)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: IgnorePointer(
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors
                                  .amber,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
