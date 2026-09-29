import 'package:flutter/material.dart';








class ReorderGrabStrip extends StatelessWidget {
  const ReorderGrabStrip({super.key, required this.index});


  final int index;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ReorderableDragStartListener(
      index: index,
      child: Container(
        width: 18,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(Icons.drag_indicator, size: 16, color: cs.onSurfaceVariant),
      ),
    );
  }
}
