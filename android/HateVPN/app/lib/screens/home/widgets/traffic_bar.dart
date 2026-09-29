import 'package:flutter/material.dart';

import '../../../controllers/home_controller.dart';
import '../../../controllers/subscription_controller.dart';
import '../../../models/home_state.dart';
import '../../../services/format_utils.dart';
import '../../../services/traffic_profiler.dart';
import '../../stats_screen.dart';
import '../../../services/l10n/locale_controller.dart';







class TrafficBar extends StatelessWidget {
  const TrafficBar({
    super.key,
    required this.state,
    required this.controller,
    this.subController,
  });

  final HomeState state;
  final HomeController controller;



  final SubscriptionController? subController;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uptime = state.connectedSince != null
        ? formatDuration(
            DateTime.now().difference(state.connectedSince!),
            daysRollup: true,
          )
        : '';
    return GestureDetector(
      onTap: () {

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StatsScreen(
              configRaw: controller.state.activeConfigRaw,
              initialTab: StatsTab.overview,
              subController: subController,
              homeController: controller,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: AnimatedBuilder(
          animation: TrafficProfiler.I,
          builder: (_, _) {
            final profiler = TrafficProfiler.I;
            return Row(
              children: [
                _chip(
                  context,
                  Icons.arrow_upward,
                  state.traffic.uploadFormatted,
                  cs.primary,
                ),
                const SizedBox(width: 8),
                _chip(
                  context,
                  Icons.arrow_downward,
                  state.traffic.downloadFormatted,
                  cs.tertiary,
                ),
                if (state.traffic.activeConnections > 0) ...[
                  const SizedBox(width: 8),





                  _chip(
                    context,
                    Icons.link,
                    '${state.traffic.connectionsIn}',
                    cs.secondary,
                    tooltip: getLocalText.s("App connections"),
                  ),
                  const SizedBox(width: 8),
                  _chip(
                    context,
                    Icons.dns_outlined,
                    '${state.traffic.connectionsOut}',
                    cs.secondary,
                    tooltip: getLocalText.s("Outbound connections to servers"),
                  ),
                ],
                if (profiler.isGlobalRecording) ...[
                  const SizedBox(width: 8),
                  _chip(context, Icons.podcasts, 'Live', cs.error),
                ],
                const Spacer(),
                if (uptime.isNotEmpty)
                  Text(
                    uptime,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  static Widget _chip(
    BuildContext context,
    IconData icon,
    String label,
    Color color, {
    String? tooltip,
  }) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );



    if (tooltip == null) return row;
    return Tooltip(
      message: tooltip,
      triggerMode: TooltipTriggerMode.longPress,
      child: row,
    );
  }
}
