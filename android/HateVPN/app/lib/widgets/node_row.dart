import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/home/special_node_display.dart';
import '../screens/subscription_detail_screen/widgets/node_warning_row.dart';
import 'node_view_item.dart';
import '../services/networks_direction.dart';
import '../services/l10n/locale_controller.dart';

import '../vpn/cc_channel.dart' show CcEndpointState;









class NodeRow extends StatelessWidget {
  const NodeRow({
    super.key,
    required this.item,
    required this.onHighlight,
    required this.onActivate,
    required this.onPing,
    this.onCopyUri,
    this.onViewJson,
    this.onRunUrltest,
    this.onSelectServer,
    this.onViewPool,
    this.onSickTap,
    this.onToggleEndpoint,
  });

  final NodeViewItem item;
  final VoidCallback onHighlight;
  final VoidCallback onActivate;
  final VoidCallback onPing;


  final VoidCallback? onCopyUri;
  final VoidCallback? onViewJson;



  final VoidCallback? onRunUrltest;




  final VoidCallback? onSelectServer;



  final VoidCallback? onViewPool;



  final VoidCallback? onSickTap;




  final VoidCallback? onToggleEndpoint;








  bool get _isTailnet => item.tailnetState != null;


  String get _tailnetLabel {
    final st = item.tailnetState;
    if (st == null) return '';
    switch (st.kind) {
      case TailnetStateKind.none:
        return '';
      case TailnetStateKind.starting:
        return getLocalText.s("starting");
      case TailnetStateKind.running:
        return getLocalText.s("running");
      case TailnetStateKind.signInNeeded:
        return getLocalText.s("sign-in needed");
      case TailnetStateKind.stopped:
        return getLocalText.s("stopped");
      case TailnetStateKind.other:
        return st.text;
    }
  }

  Color _tailnetColor(ColorScheme cs) {
    final st = item.tailnetState;
    if (st?.kind == TailnetStateKind.running) return Colors.green;
    if (st != null && st.isWarning) return Colors.orange;
    return cs.onSurfaceVariant;
  }

  String get _delayLabel {
    if (_isTailnet) return _tailnetLabel;



    if (_isDisabled) return '—';
    if (item.pingBusy) return 'PING…';
    final delay = item.delay;
    if (delay == null) return '';
    final prefix = item.delayIsForeign ? '~' : '';
    return delay < 0 ? '${prefix}ERR' : '$prefix${delay}MS';
  }






  bool get _isDisabled => item.endpointState == CcEndpointState.disabled;

  String get _endpointStateLabel {
    final st = item.endpointState;

    if (st == CcEndpointState.disabled) return getLocalText.s("off");
    if (st == CcEndpointState.up) return getLocalText.s("up");
    if (st == CcEndpointState.asleep) return getLocalText.s("sleep");
    if (CcEndpointState.isNotBuilt(st) || st == CcEndpointState.down) {
      return getLocalText.s("down");
    }
    return '';
  }

  Widget _endpointStateLabelText(String label, Color color) => Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontStyle: FontStyle.italic,
          color: color,
        ),
      );

  Color? _delayColor(BuildContext context) {
    if (_isDisabled) return null;
    final delay = item.delay;
    if (delay == null || item.pingBusy) return null;
    final Color base;
    if (delay < 0) {
      base = Theme.of(context).colorScheme.error;
    } else if (delay < 200) {
      base = Colors.green;
    } else if (delay < 500) {
      base = Colors.orange;
    } else {
      base = Theme.of(context).colorScheme.error;
    }


    return item.delayIsForeign ? base.withValues(alpha: 0.55) : base;
  }


  Widget _buildSubtitleRow(BuildContext context, ColorScheme cs) {
    final hasActive = item.active;
    final hasArrow = item.urltestNow != null && item.urltestNow!.isNotEmpty;


    final auto = item.autoGroupLabel;
    final hasAuto = auto != null && auto.isNotEmpty;
    final hasProto = !hasAuto &&
        item.protocolLabel != null &&
        item.protocolLabel!.isNotEmpty;
    final notificationWarnings = item.notificationWarnings;
    final hasNotificationBadge = notificationWarnings != null &&
        notificationWarnings.isNotEmpty;

    final dl = _isBlock ? '' : _delayLabel;


    final stateLabel = _isBlock ? '' : _endpointStateLabel;

    if (!hasActive &&
        !hasArrow &&
        !hasProto &&
        !hasAuto &&
        !hasNotificationBadge &&
        stateLabel.isEmpty &&
        dl.isEmpty) {
      return const SizedBox.shrink();
    }

    final Widget? activePill = hasActive
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              getLocalText.s("ACTIVE"),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Colors.green.shade700,
                letterSpacing: 0.5,
              ),
            ),
          )
        : null;

    final Widget? arrow = (hasArrow || hasAuto)
        ? Text(
            [
              if (hasAuto) auto,
              if (hasArrow) '→ ${item.urltestNow}',
            ].join(' '),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontStyle: FontStyle.italic,
              color: cs.onSurfaceVariant,
            ),
          )
        : null;



    final Widget? endpointStateText = stateLabel.isEmpty
        ? null
        : Flexible(
            child: _endpointStateLabelText(
                stateLabel, _isDisabled ? Colors.orange : cs.onSurfaceVariant),
          );

    final Widget? proto = (hasProto || hasNotificationBadge)
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasNotificationBadge)
                NodeInfoBadge(notificationWarnings, showTopSeverity: true),
              if (hasProto)
                Flexible(
                  child: Text(
                    item.protocolLabel!,


                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
            ],
          )
        : null;

    final right = dl.isEmpty
        ? const SizedBox.shrink()
        : Text(
            dl,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: _isTailnet
                  ? _tailnetColor(cs)
                  : _delayColor(context) ?? cs.onSurfaceVariant,
            ),
          );





    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                if (activePill != null) ...[
                  activePill,
                  const SizedBox(width: 6),
                ],




                if (arrow != null)
                  Flexible(
                    flex: 3,
                    fit: FlexFit.loose,
                    child: Padding(
                      padding: EdgeInsets.only(right: proto != null ? 6 : 0),
                      child: arrow,
                    ),
                  ),
                if (proto != null)
                  Flexible(
                    flex: 1,
                    fit: FlexFit.loose,
                    child: proto,
                  ),


                if (endpointStateText != null) ...[
                  if (proto != null || arrow != null)
                    const SizedBox(width: 6),
                  endpointStateText,
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          right,
        ],
      ),
    );
  }





  bool get _isSpecial => _special != null;

  SpecialNodeDisplay? get _special {
    final s = specialNodeDisplayForType(item.outboundType);
    if (s == null) return null;
    if (item.outboundType == 'urltest' && !item.isDirectionAuto) return null;
    return s;
  }



  bool get _isBlock => item.outboundType == 'block';

  Future<void> _openLongPressMenu(BuildContext context) async {

    final canPing = item.tunnelUp && !item.busy && !item.pingBusy && !_isBlock;
    final canActivate = item.tunnelUp && !item.busy && !item.active;




    final showCopy = !_isSpecial && item.outboundType != 'urltest';
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null || !box.hasSize) return;

    final a = box.localToGlobal(Offset.zero);
    final b = box.localToGlobal(box.size.bottomRight(Offset.zero));
    final position = RelativeRect.fromRect(
      Rect.fromPoints(a, b),
      Offset.zero & overlay.size,
    );
    final chosen = await showMenu<String>(
      context: context,
      position: position,
      items: [

        if (!_isTailnet)
        PopupMenuItem<String>(
          value: 'ping',
          enabled: canPing,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.speed_outlined,
              size: 20,
              color: canPing ? null : Theme.of(context).disabledColor,
            ),
            title: Text(getLocalText.s("Ping")),
          ),
        ),
        if (!_isTailnet)
        PopupMenuItem<String>(
          value: 'activate',
          enabled: canActivate,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.play_circle_outline,
              size: 20,
              color: canActivate ? null : Theme.of(context).disabledColor,
            ),
            title: Text(getLocalText.s("Use this node")),
          ),
        ),
        if (onRunUrltest != null)
          PopupMenuItem<String>(
            value: 'run_urltest',
            enabled: item.tunnelUp && !item.busy,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.auto_awesome,
                size: 20,
                color: (item.tunnelUp && !item.busy)
                    ? null
                    : Theme.of(context).disabledColor,
              ),
              title: Text(getLocalText.s("Run URLTest")),
            ),
          ),



        if (onSelectServer != null)
          PopupMenuItem<String>(
            value: 'select_server',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.my_location, size: 20),
              title: Text(getLocalText.s("Select server")),
            ),
          ),


        if (onViewPool != null)
          PopupMenuItem<String>(
            value: 'view_pool',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.hub_outlined, size: 20),
              title: Text(getLocalText.s("View pool")),
            ),
          ),
        if (onToggleEndpoint != null)
          PopupMenuItem<String>(
            value: 'toggle_endpoint',
            enabled: !item.busy,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _isDisabled
                    ? Icons.power_settings_new
                    : Icons.power_off_outlined,
                size: 20,
                color: item.busy ? Theme.of(context).disabledColor : null,
              ),
              title: Text(_isDisabled
                  ? getLocalText.s("Turn on")
                  : getLocalText.s("Turn off")),
            ),
          ),
        if (onViewJson != null) const PopupMenuDivider(),
        if (onViewJson != null)


          PopupMenuItem<String>(
            value: 'view_json',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.info_outline, size: 20),
              title: Text(getLocalText.s("View details")),
            ),
          ),
        if (showCopy) const PopupMenuDivider(),
        if (showCopy && onCopyUri != null)
          PopupMenuItem<String>(
            value: 'copy_uri',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.link, size: 20),
              title: Text(getLocalText.s("Copy URI")),
            ),
          ),

      ],
    );
    if (!context.mounted) return;
    switch (chosen) {
      case 'ping':
        onPing();
      case 'select_server':
        onSelectServer?.call();
      case 'view_pool':
        onViewPool?.call();
      case 'activate':
        onActivate();
      case 'run_urltest':
        if (onRunUrltest != null) onRunUrltest!();
      case 'copy_uri':
        if (onCopyUri != null) onCopyUri!();
      case 'view_json':
        if (onViewJson != null) onViewJson!();
      case 'toggle_endpoint':
        onToggleEndpoint?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canActivate = item.tunnelUp && !item.busy && !item.active;

    final content = Material(
      color: item.highlighted
          ? colorScheme.primaryContainer.withAlpha(55)
          : (_isSpecial ? colorScheme.secondaryContainer.withAlpha(40) : null),
      child: InkWell(
        onTap: onHighlight,
        onLongPress: () => unawaited(_openLongPressMenu(context)),
        child: SizedBox(
          height: 56,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: (item.active || item.highlighted) ? 3 : 0,
                color: (item.active || item.highlighted)
                    ? colorScheme.primary
                    : Colors.transparent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Builder(builder: (context) {



                      final special = _special;
                      final displayText = special?.label ?? item.tag;
                      return Row(
                        children: [
                          if (special != null) ...[
                            Icon(special.icon,
                                size: 18, color: colorScheme.primary),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              displayText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    fontWeight: item.active
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                            ),
                          ),


                          if (item.isSickRoot) ...[
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: onSickTap,
                              child: Icon(Icons.warning_amber_rounded,
                                  size: 18, color: colorScheme.error),
                            ),
                          ],
                        ],
                      );
                    }),
                    _buildSubtitleRow(context, colorScheme),
                  ],
                ),
              ),

              if (!_isTailnet)
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
                tooltip: item.active
                    ? getLocalText.s("Active")
                    : getLocalText.s("Use node"),
                onPressed: canActivate ? onActivate : null,
                icon: Icon(
                  item.active ? Icons.check_circle : Icons.play_circle_outline,
                  size: 22,
                  color: item.active
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );




    return Opacity(
      opacity: item.matches ? 1.0 : 0.4,
      child: content,
    );
  }
}
