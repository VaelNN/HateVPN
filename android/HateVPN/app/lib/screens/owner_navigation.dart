import 'package:flutter/material.dart';

import '../controllers/home_controller.dart';
import '../controllers/subscription_controller.dart';
import '../models/direction.dart';
import '../models/server_list.dart';
import '../models/source_chain.dart';
import '../services/l10n/locale_controller.dart';
import '../services/runtime_chain.dart';
import '../services/settings_storage.dart';
import 'chain_edit/chain_edit_flow.dart';
import 'folder_detail_screen.dart';
import 'home/source_lookup.dart';
import 'node_settings_screen.dart';
import 'routing_screen.dart';
import 'subscription_detail_screen.dart';


















Future<void> openTagOwner(
  BuildContext context,
  String tag, {
  required SubscriptionController subController,
  required HomeController homeController,
  List<Direction>? directions,
  List<SourceChain>? chains,
  required VoidCallback onOwnerNotFound,
}) async {
  final chs = directions ?? await SettingsStorage.getDirections();
  if (!context.mounted) return;

  final direction = directionForTag(tag, chs);
  if (direction != null) {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoutingScreen(
          subController: subController,
          homeController: homeController,
          focusDirectionTag: direction.tag,
        ),
      ),
    );
    return;
  }



  final allChains = chains ?? await SettingsStorage.getChains();
  if (!context.mounted) return;
  final chain = allChains.where((c) => c.tag == tag).firstOrNull;
  if (chain != null) {
    await _editChainFromOwnerLink(context, chain,
        subController: subController, homeController: homeController);
    return;
  }

  final owner = ownerOfTag(tag, subController.entries);
  if (owner == null) {
    onOwnerNotFound();
    return;
  }
  final entry = subController.entries[owner.entryIndex];
  final list = entry.list;
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) {
        if (list is FolderServers) {
          return FolderDetailScreen(
            entry: entry,
            controller: subController,
            focusMemberIndex: owner.memberIndex,
          );
        }
        if (list is UserServer) {
          return NodeSettingsScreen(
            entry: entry,
            index: owner.entryIndex,
            subController: subController,
          );
        }
        return SubscriptionDetailScreen(
          entry: entry,
          controller: subController,
        );
      },
    ),
  );
}



Future<void> _editChainFromOwnerLink(
  BuildContext context,
  SourceChain chain, {
  required SubscriptionController subController,
  required HomeController homeController,
}) async {
  final outcome = await editChainAndPersist(context, chain,
      subController: subController, homeController: homeController);
  if (outcome == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  if (outcome.positionsRemoved > 0) {
    messenger.showSnackBar(SnackBar(
      content: Text(getLocalText.s(
          '%s chain position(s) removed', '${outcome.positionsRemoved}')),
    ));
  }
  await regenerateSourcesConfig(subController, homeController);
}
