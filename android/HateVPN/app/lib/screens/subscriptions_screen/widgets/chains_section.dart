

















import 'package:flutter/material.dart';

import '../../../models/source_chain.dart';
import '../../../services/l10n/locale_controller.dart';
import '../../../widgets/reorder_grab_strip.dart';

class ChainEntryTile extends StatelessWidget {
  const ChainEntryTile({
    super.key,
    required this.chain,
    required this.dragIndex,
    required this.onTap,
    required this.onToggle,
  });

  final SourceChain chain;



  final int dragIndex;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tile = ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 40,
        child: Switch(
          value: chain.enabled,
          onChanged: (_) => onToggle(),
        ),
      ),
      title: Text(
        chain.displayLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: chain.enabled ? null : cs.onSurfaceVariant,
        ),
      ),



      subtitle: Text(
        '${chain.tag} · ${getLocalText.plural("%d hops", chain.hops.length)}',
        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
      ),
      trailing: Icon(Icons.route, size: 20, color: cs.onSurfaceVariant),
      onTap: onTap,
    );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReorderGrabStrip(index: dragIndex),
          Expanded(
            child: Column(
              children: [
                tile,
                const Divider(height: 1),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
