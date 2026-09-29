import 'package:flutter/material.dart';



class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
}
