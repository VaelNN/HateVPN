import 'package:flutter/material.dart';

import '../models/custom_rule.dart' show kOutboundReject;
import '../services/l10n/locale_controller.dart';


class OutboundOption {
  const OutboundOption({required this.value, required this.label});
  final String value;
  final String label;

  static const reject =
      OutboundOption(value: kOutboundReject, label: 'Reject');
}








class OutboundPicker extends StatelessWidget {
  const OutboundPicker({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.allowReject = true,
    this.dense = true,
    this.label = 'Action',
    this.width,
  });

  final String value;
  final List<OutboundOption> options;
  final ValueChanged<String> onChanged;
  final bool allowReject;




  final bool dense;


  final String label;


  final double? width;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fontSize = dense ? 13.0 : 15.0;
    final iconSize = dense ? 14.0 : 18.0;

    final items = <DropdownMenuItem<String>>[];
    for (final o in options) {
      items.add(DropdownMenuItem(
        value: o.value,
        child: Text(o.label, style: TextStyle(fontSize: fontSize)),
      ));
    }
    if (allowReject) {
      items.add(DropdownMenuItem(
        value: kOutboundReject,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block, size: iconSize, color: cs.error),
            const SizedBox(width: 6),
            Text(getLocalText.s("Reject"),
                style: TextStyle(fontSize: fontSize, color: cs.error)),
          ],
        ),
      ));
    }








    final effectiveValue = items.any((i) => i.value == value)
        ? value
        : (options.isNotEmpty ? options.first.value : kOutboundReject);

    if (!dense) {
      return DropdownButtonFormField<String>(
        initialValue: effectiveValue,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: false,
        ),
        items: items,
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      );
    }

    final widget = DropdownButton<String>(
      value: effectiveValue,
      isDense: true,
      isExpanded: width != null,
      items: items,
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
    return width != null ? SizedBox(width: width, child: widget) : widget;
  }
}
