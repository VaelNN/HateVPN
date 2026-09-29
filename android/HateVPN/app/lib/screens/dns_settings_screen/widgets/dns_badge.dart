import 'package:flutter/material.dart';


class DnsBadge extends StatelessWidget {
  const DnsBadge(this.text, this.color, {super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {


    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        style: TextStyle(
          fontSize: 10,
          height: 1.2,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
