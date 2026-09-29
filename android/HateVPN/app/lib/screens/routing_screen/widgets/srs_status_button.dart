import 'package:flutter/material.dart';

import '../../../models/custom_rule.dart';
import '../../../models/parser_config.dart';







class SrsStatusButton extends StatelessWidget {
  const SrsStatusButton({
    super.key,
    required this.rule,
    required this.downloading,
    required this.cached,
    required this.onPressed,
  });

  final CustomRule rule;
  final bool downloading;
  final bool cached;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (downloading) {
      return const SizedBox(
        width: 32,
        height: 32,
        child: Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
        ),
      );
    }


    return IconButton(
      iconSize: 18,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: Icon(
        cached ? Icons.cloud_done_outlined : Icons.cloud_download_outlined,
        color: cached ? Colors.green : cs.onSurfaceVariant,
      ),
      onPressed: onPressed,
    );
  }
}




class PresetSrsStatusButton extends StatelessWidget {
  const PresetSrsStatusButton({
    super.key,
    required this.rule,
    required this.preset,
    required this.downloading,
    required this.cached,
    required this.onTap,
    required this.onLongPress,
  });

  final CustomRulePreset rule;
  final SelectableRule preset;
  final bool downloading;
  final bool cached;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (downloading) {
      return const SizedBox(
        width: 32,
        height: 32,
        child: Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
        ),
      );
    }



    return SizedBox(
      width: 32,
      height: 32,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Icon(
          cached ? Icons.cloud_done_outlined : Icons.cloud_download_outlined,
          size: 18,
          color: cached ? Colors.green : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
