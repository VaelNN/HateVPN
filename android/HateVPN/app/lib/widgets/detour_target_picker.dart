import 'package:flutter/material.dart';

import '../controllers/subscription_controller.dart';
import '../models/direction.dart';
import '../models/node_link.dart';
import '../models/node_spec.dart';
import '../models/server_list.dart';
import '../services/node_link_address.dart';
import '../services/selector_info.dart';
import '../services/tag_resolver.dart';
import '../services/l10n/locale_controller.dart';
import 'app_bottom_sheet.dart';


class DetourTarget {
  const DetourTarget({required this.link, required this.display});





  final NodeLink link;


  final String display;


  static const none = DetourTarget(link: NodeLink.none, display: '');
}



String detourNodeSubline(NodeSpec n) {
  final type = n.protocol.toUpperCase();
  return n.isAddressless ? type : '$type · ${n.server}:${n.port}';
}








String detourDirectionDisplay(String stored, List<Direction> directions) {
  if (stored.isEmpty) return stored;
  for (final c in directions) {
    if (stored == c.tag || stored == c.autoTag) {
      final selected = SelectorInfo.I.selectedOf(stored);
      final pick = (selected != null && selected.isNotEmpty)
          ? ' ($selected)'
          : '';
      return '${c.displayLabel}$pick';
    }
  }
  return stored;
}






String detourLinkDisplay(
  NodeLink link, {
  required List<Direction> directions,
  SubscriptionController? controller,
  FolderServers? folder,
}) {
  if (link.isEmpty) return '';
  if (link.isRoot) return detourDirectionDisplay(link.tag, directions);
  if (folder != null && folder.id == link.folderId) return link.tag;
  for (final e in controller?.entries ?? const <SubscriptionEntry>[]) {
    if (e.list.id == link.folderId) {
      return containerFinalForm(e.list, link.tag);
    }
  }
  return link.tag;
}
















List<String> detourPathHops(
  NodeLink stored, {
  required SubscriptionController controller,
  required List<Direction> directions,
  FolderServers? folder,
}) {
  final hops = <String>[];
  final visited = <NodeLink>{};
  var current = stored;
  var folderCtx = folder;
  while (current.isNotEmpty && hops.length < 6 && visited.add(current)) {

    if (!current.isRoot) {
      FolderServers? owner =
          folderCtx != null && folderCtx.id == current.folderId ? folderCtx : null;
      if (owner == null) {
        for (final e in controller.entries) {
          final l = e.list;
          if (l is FolderServers && l.id == current.folderId) {
            owner = l;
            break;
          }
        }
      }
      FolderMember? member;
      if (owner != null) {
        for (var k = 0; k < owner.members.length; k++) {
          if (folderMemberAddress(owner, k) == current) {
            member = owner.members[k];
            break;
          }
        }
      }
      hops.add(detourLinkDisplay(current,
          directions: directions, controller: controller, folder: folder));
      if (member == null) break;
      current = member.detour;
      folderCtx = owner;
      continue;
    }

    final directionText = detourDirectionDisplay(current.tag, directions);
    if (directionText != current.tag) {
      hops.add(directionText);
      break;
    }

    UserServer? owner;
    for (final e in controller.entries) {
      final l = e.list;
      if (l is! UserServer || !l.enabled) continue;
      for (final n in l.nodes) {
        if (TagResolver.displayTag(l.tagPrefix, n.tag) == current.tag) {
          owner = l;
          break;
        }
      }
      if (owner != null) break;
    }
    hops.add(current.tag);
    if (owner == null) break;
    current = owner.detourPolicy.overrideDetour;
    folderCtx = null;
  }


  return hops.reversed.toList();
}



String _directionTitle(Direction c) {
  final selected = SelectorInfo.I.selectedOf(c.tag);
  final pick =
      (selected != null && selected.isNotEmpty) ? ' ($selected)' : '';
  return '${c.displayLabel}$pick';
}







List<Direction> visibleDetourDirections(
    List<Direction> directions, FolderServers? currentFolder) {
  final memberBareTags = <String>{
    if (currentFolder != null)
      for (final m in currentFolder.members)
        if (m.node != null) m.node!.tag,
  };
  return [
    for (final c in directions)
      if (c.enabled && c.isDetour && !memberBareTags.contains(c.tag)) c,
  ];
}














Future<DetourTarget?> showDetourTargetPicker(
  BuildContext context, {
  required SubscriptionController controller,
  List<Direction> directions = const [],
  FolderServers? currentFolder,
  String selfBareTag = '',
  String selfDisplayTag = '',
}) {

  final free = <(String display, NodeSpec node)>[];
  for (final e in controller.entries) {
    final list = e.list;
    if (list is! UserServer) continue;
    if (!list.enabled) continue;
    for (final n in list.nodes) {
      if (n.tag.isEmpty) continue;


      if (n.isGroup) continue;
      final display = TagResolver.displayTag(list.tagPrefix, n.tag);
      if (selfDisplayTag.isNotEmpty && display == selfDisplayTag) continue;
      free.add((display, n));
    }
  }



  final members = <(String bare, NodeLink link, NodeSpec node)>[];
  final folder = currentFolder;
  if (folder != null) {
    final raw = containerRawTags(folder);
    for (final m in folder.members) {
      final n = m.node;
      if (n == null || n.tag.isEmpty) continue;
      if (n.isGroup) continue;
      if (selfBareTag.isNotEmpty && n.tag == selfBareTag) continue;
      final rawTag = raw[n];
      if (rawTag == null) continue;
      members.add((n.tag, NodeLink(folderId: folder.id, tag: rawTag), n));
    }
  }


  final detourDirections = visibleDetourDirections(directions, folder);

  return showAppBottomSheet<DetourTarget>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final muted = theme.colorScheme.onSurfaceVariant;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(getLocalText.s("Detour server"),
                    style: theme.textTheme.titleMedium),
              ),
              ListTile(
                leading: const Icon(Icons.block_flipped, size: 20),
                title: Text(getLocalText.s("None (direct)")),
                onTap: () => Navigator.pop(ctx, DetourTarget.none),
              ),
              if (folder != null)
                ExpansionTile(
                  leading: const Icon(Icons.folder_outlined, size: 20),
                  title: Text(getLocalText.s("This folder (%d)", members.length)),
                  subtitle: Text(
                    getLocalText.s("Chains inside the folder get the folder detour appended"),
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  children: members.isEmpty
                      ? [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(getLocalText.s("No other servers in this folder"),
                                style: TextStyle(color: muted)),
                          ),
                        ]
                      : [
                          for (final (bare, link, n) in members)
                            ListTile(
                              contentPadding:
                                  const EdgeInsets.only(left: 32, right: 16),
                              title: Text(bare,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                detourNodeSubline(n),
                                style:
                                    TextStyle(fontSize: 12, color: muted),
                              ),
                              onTap: () => Navigator.pop(
                                  ctx,
                                  DetourTarget(link: link, display: bare)),
                            ),
                        ],
                ),


              if (detourDirections.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(getLocalText.s("Directions"),
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: theme.colorScheme.primary)),
                ),
                for (final c in detourDirections)
                  ListTile(


                    title: Text(_directionTitle(c),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      getLocalText.s("Switchable detour direction"),
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    onTap: () => Navigator.pop(
                        ctx,
                        DetourTarget(
                            link: NodeLink(tag: c.tag),
                            display: c.displayLabel)),
                  ),
              ],
              if (free.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(getLocalText.s("Standalone servers"),
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: theme.colorScheme.primary)),
                ),
                for (final (display, n) in free)
                  ListTile(
                    title: Text(display,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      detourNodeSubline(n),
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    onTap: () => Navigator.pop(ctx,
                        DetourTarget(
                            link: NodeLink(tag: display), display: display)),
                  ),
              ] else
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(getLocalText.s("No standalone servers available"),
                      style: TextStyle(color: muted)),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}
