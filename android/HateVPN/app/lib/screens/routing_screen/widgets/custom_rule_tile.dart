import 'package:flutter/material.dart';

import '../../../models/custom_rule.dart';
import '../../../widgets/outbound_picker.dart';
import '../../../widgets/reorder_grab_strip.dart';
import '../routing_screen_helpers.dart';





class CustomRuleTile extends StatelessWidget {
  const CustomRuleTile({
    super.key,
    required this.index,
    required this.rule,
    required this.displayName,
    required this.options,
    required this.subtitle,
    required this.pickerValue,
    required this.pickerDisabled,
    this.showOutbound = true,
    this.touchesDns = false,
    this.locked = false,
    this.sortable = true,
    required this.statusButton,
    required this.onTap,
    required this.onLongPressStart,
    required this.onSwitchChanged,
    required this.onOutboundChanged,
  });

  final int index;
  final CustomRule rule;




  final String displayName;

  final List<RoutingOutboundOption> options;
  final String subtitle;
  final String pickerValue;
  final bool pickerDisabled;




  final bool showOutbound;





  final bool touchesDns;




  final bool locked;




  final bool sortable;






  final Widget? statusButton;


  final VoidCallback? onTap;
  final ValueChanged<Offset> onLongPressStart;
  final ValueChanged<bool> onSwitchChanged;
  final ValueChanged<String> onOutboundChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = rule.enabled;
    final subtitleColor = active ? cs.primary : cs.onSurfaceVariant;

    final content = GestureDetector(
      onTap: onTap,

      onLongPressStart: locked
          ? null
          : (d) => onLongPressStart(d.globalPosition),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Switch(
                  value: rule.enabled,

                  onChanged: locked ? null : onSwitchChanged,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(displayName,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: active ? null : cs.onSurfaceVariant,
                      )),
                ),
                ?statusButton,
                if (!showOutbound)
                  const SizedBox.shrink()
                else if (pickerDisabled)
                  Icon(Icons.warning_amber_outlined,
                      color: cs.error, size: 18)
                else
                  OutboundPicker(
                    value: pickerValue,
                    options: options
                        .map((o) =>
                            OutboundOption(value: o.tag, label: o.label))
                        .toList(),
                    onChanged: onOutboundChanged,
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 64, right: 8, bottom: 4),
              child: Row(
                children: [
                  if (rule.kind == CustomRuleKind.preset) ...[
                    Icon(Icons.lock_outline,
                        size: 12, color: subtitleColor),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(subtitle,
                        style:
                            TextStyle(fontSize: 12, color: subtitleColor),
                        overflow: TextOverflow.ellipsis),
                  ),


                  if (rule.resolveActive) ...[
                    const SizedBox(width: 6),
                    Text('✳',
                        style: TextStyle(
                            fontSize: 12,
                            color: active ? cs.primary : cs.onSurfaceVariant)),
                  ],

                  if (touchesDns) ...[
                    const SizedBox(width: 6),
                    _dnsChip(cs, active),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [


          if (!sortable)
            const SizedBox(width: 30)
          else
            ReorderGrabStrip(index: index),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                content,
                const Divider(height: 1),
              ],
            ),
          ),
        ],
      ),
    );
  }



  Widget _dnsChip(ColorScheme cs, bool enabled) {
    final c = enabled ? cs.primary : cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: c.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.dns_outlined, size: 12, color: c),
          const SizedBox(width: 3),

          Text('DNS',
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600, color: c)),
        ],
      ),
    );
  }
}
