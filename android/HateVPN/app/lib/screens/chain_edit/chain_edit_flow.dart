import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/home_controller.dart';
import '../../controllers/subscription_controller.dart';
import '../../models/source_chain.dart';
import '../../services/builder/node_link_pool.dart';
import '../../services/settings_storage.dart';
import '../chain_edit_screen.dart';


class ChainEditOutcome {
  const ChainEditOutcome({required this.deleted, this.positionsRemoved = 0});

  final bool deleted;


  final int positionsRemoved;
}







Future<ChainEditOutcome?> editChainAndPersist(
  BuildContext context,
  SourceChain chain, {
  required SubscriptionController subController,
  required HomeController homeController,
}) async {
  final directions = await SettingsStorage.getDirections();
  final chains = await SettingsStorage.getChains();
  if (!context.mounted) return null;
  final lists = [for (final e in subController.entries) e.list];
  final result = await openChainEditor(
    context,
    initial: chain,


    config: homeController.state.configModel,
    directions: directions,
    chains: chains,

    pool: computeNodeLinkPool(lists, directions: directions),
    lists: lists,
  );
  if (result == null) return null;
  if (result.wasDeleted) {


    final healed = await SettingsStorage.deleteChain(chain.tag);
    return ChainEditOutcome(deleted: true, positionsRemoved: healed.positions);
  }
  if (result.saved == null) return null;
  await SettingsStorage.updateChain(result.saved!);
  return const ChainEditOutcome(deleted: false);
}










Future<bool?> regenerateSourcesConfig(
  SubscriptionController subController,
  HomeController homeController,
) async {
  final config = await subController.generateConfig();
  if (config == null) return null;
  await homeController.saveParsedConfig(config);
  final applied = homeController.canReload;
  if (applied) unawaited(homeController.reloadVpn());
  return applied;
}
