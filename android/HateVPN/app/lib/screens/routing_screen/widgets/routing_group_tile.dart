import 'package:flutter/material.dart';

import '../../../models/direction.dart';



class RoutingDirectionTile extends StatelessWidget {
  const RoutingDirectionTile({
    super.key,
    required this.direction,
    required this.nodeCount,
    required this.onToggle,
    required this.onTap,
  });

  final Direction direction;


  final int nodeCount;


  final ValueChanged<bool>? onToggle;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isRequired = direction.isRequired;
    final nodesStr = nodeCount < 0
        ? (direction.nodeFilter.isEmpty ? 'all nodes' : 'filtered')
        : '$nodeCount node${nodeCount == 1 ? '' : 's'}';
    final autoStr = direction.auto != null ? ' · auto' : '';
    final reqStr = isRequired ? ' · required' : '';
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 8, right: 8),
      leading: Switch(
        value: isRequired ? true : direction.enabled,
        onChanged: isRequired ? null : onToggle,
      ),

      title: Text(direction.displayLabel),
      subtitle: Text(
        '${direction.tag} · $nodesStr$autoStr$reqStr',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
