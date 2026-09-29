import 'package:collection/collection.dart' show mergeSort;

import '../../config/consts.dart';
import '../../models/emit_context.dart';
import '../../models/server_list.dart';
import '../../models/auto_select.dart';
import '../../models/node_link.dart';
import '../../models/node_spec.dart';
import '../../models/node_warning.dart' show RegistryWarning;
import '../../models/singbox_entry.dart';
import '../contract/body_sanitizer.dart' show exitCapableByRegistry;
import '../node_hash.dart';
import '../node_identity.dart';
import '../node_link_address.dart';
import '../safe_regex.dart';
import '../tag_resolver.dart';
import 'node_link_resolve.dart';
import 'source_replace_build.dart';
import 'verbatim_body.dart';





extension ServerListBuild on ServerList {






  void build(EmitContext ctx) {
    if (!enabled) return;



    final plan = switch (this) {
      final FolderServers f => FolderDetourPlan(f),
      _ => null,
    };


    final targets = ctx.linkTargets;
    final addressTags = (targets == null || this is UserServer)
        ? null
        : containerRawTags(this);
    void noteAddress(NodeSpec node, String baseTag, String finalTag,
        {bool group = false}) {
      if (targets == null) return;
      if (this is UserServer) {
        targets.noteRootNode(finalTag);
        return;
      }
      final raw = addressTags?[node] ?? baseTag.trim();
      if (group) {
        targets.noteGroup(
            id, raw, TagResolver.displayTag(tagPrefix, raw), finalTag);
      } else {
        targets.noteMember(id, raw, finalTag);
      }
    }










    final disabledHashes = switch (this) {
      final SubscriptionServers s when s.disabledHashes.isNotEmpty =>
        s.disabledHashes,
      _ => null,
    };
    final identities =
        disabledHashes == null ? null : sourceNodeIdentities(nodes);






    final rep = replace;
    if (rep != null && rep.tag.trim().isEmpty) {
      ctx.warn('Replace group of "$name" has no name — the source was not '
          'replaced, its nodes go to directions one by one.');
    }


    final fold = rep == null || rep.tag.trim().isEmpty || ctx.isReplaceBlocked(id)
        ? null
        : rep;
    final foldSelector = <(int, SingboxEntry)>[];
    final foldAuto = <(int, SingboxEntry)>[];
    void toSelector(int i, SingboxEntry e) => fold == null
        ? ctx.addToSelectorTagList(e)
        : foldSelector.add((i, e));
    void toAuto(int i, SingboxEntry e) =>
        fold == null ? ctx.addToAutoList(e) : foldAuto.add((i, e));




    final autoSelects = <(AutoSelectSpec, int)>[];
    final resolvedTags = <NodeSpec, String>{};

    for (var i = 0; i < nodes.length; i++) {
      final server = nodes[i];


      final identity = identities?[server];
      if (identity != null && disabledHashes!.containsKey(identity)) {
        continue;
      }
      if (server is AutoSelectSpec) {
        autoSelects.add((server, i));
        continue;
      }
      final policy =
          plan == null ? detourPolicy : plan.policyFor(i, detourPolicy);




      final link = policy.overrideDetour;
      final replaceMode = link.isNotEmpty && policy.replaceDetourChain;
      final skipDetour = !policy.useDetourServers || replaceMode;

      final raw = server.getEntries(ctx, skipDetour: skipDetour);
      final main = raw.main;
      final detours = raw.detours;



      final verbatim = switch (this) {
        final UserServer u => verbatimBodyOf(u.rawBody, server),
        final FolderServers f when i < f.memberRaws.length =>
          verbatimBodyOf(f.memberRaws[i], server),
        _ => null,
      };
      if (verbatim != null) {
        main.map
          ..clear()
          ..addAll(verbatim);


        main.authored = true;
      }


      final detourBases = <String>[];
      for (final d in detours) {
        detourBases.add(d.tag);
        d.map['tag'] = ctx.allocateTag(TagResolver.displayTag(tagPrefix, d.tag));

        ctx.noteEmittedAlias(d.map['tag'] as String, server);
      }
      final mainBase = main.tag;
      main.map['tag'] =
          ctx.allocateTag(TagResolver.displayTag(tagPrefix, mainBase));


      resolvedTags[server] = main.map['tag'] as String;

      ctx.noteEmitted(server, main.map['tag'] as String);


      noteAddress(server, mainBase, main.tag);
      for (var k = 0; k < detours.length; k++) {
        if (this is UserServer) {
          targets?.noteRootNode(detours[k].tag);
        } else {
          targets?.noteMember(id, detourBases[k].trim(), detours[k].tag);
        }
      }



      void defer(SingboxEntry holder) => ctx.deferDetour(DeferredDetour(
            holder: holder,
            link: link,
            carrier: main,
            entries: [...raw.all],
            node: server,
          ));



      if (replaceMode) {

        defer(main);
      } else if (!policy.useDetourServers) {
        main.map.remove('detour');
      } else if (link.isNotEmpty) {

        if (detours.isEmpty) {

          defer(main);
        } else {

          main.map['detour'] = detours.first.tag;
          defer(detours.last);
        }
      } else if (detours.isNotEmpty) {
        main.map['detour'] = detours.first.tag;
      }


      for (final e in raw.all) {
        ctx.addEntry(e);
      }










      final isMainAsDetour = main.tag.startsWith(kDetourTagPrefix) ||
          (plan?.isChainLink(i) ?? false);





      final tailnetOnly = !exitCapableByRegistry(main.map);
      if (tailnetOnly) {

      } else if (!isMainAsDetour) {
        toSelector(i, main);
        toAuto(i, main);
      } else {
        if (detourPolicy.registerDetourServers) toSelector(i, main);
        if (detourPolicy.registerDetourInAuto) toAuto(i, main);
      }
      for (final d in detours) {
        if (detourPolicy.registerDetourServers) toSelector(i, d);
        if (detourPolicy.registerDetourInAuto) toAuto(i, d);
      }
    }







    final rawTags = this is FolderServers ||
            !autoSelects.any((a) => a.$1.membership is ExplicitMembers)
        ? null
        : sourceNodeRawTags(nodes);
    for (final (spec, index) in autoSelects) {
      final shown = TagResolver.displayTag(tagPrefix, spec.tag);
      final members = resolveAutoSelectMembers(
        spec,
        resolvedTags,
        containerId: id,
        rawTags: rawTags,
        groupTag: shown,
        warn: ctx.warn,
      );





      if (members.isEmpty) {
        if (spec.membership is ExplicitMembers) {
          ctx.warn('Auto node "$shown" was skipped: none of its members '
              'resolved, an empty group would stop the VPN core');
        }
        continue;
      }


      final entry = spec.coreEntry(spec.emit(ctx.vars));





      if (ctx.passiveCheck && !spec.isManual) {
        entry.map['passive_check'] = true;
      }
      entry.map['tag'] =
          ctx.allocateTag(TagResolver.displayTag(tagPrefix, spec.tag));
      noteAddress(spec, spec.tag, entry.tag, group: true);
      entry.map['outbounds'] = members;




      if (spec.isManual) {
        entry.map.remove('default');
        final def = resolveAutoSelectDefault(
          spec,
          resolvedTags,
          containerId: id,
          rawTags: rawTags,
          members: members,
        );
        if (def != null) {
          entry.map['default'] = def;
        } else if (spec.manualDefault.isNotEmpty &&
            !_isExplicitMember(spec, spec.manualDefault)) {
          ctx.warn(groupMemberDroppedLine(shown, spec.manualDefault));
        }
      }
      ctx.addEntry(entry);


      toSelector(index, entry);


    }

    if (fold != null) {


      int byIndex((int, SingboxEntry) a, (int, SingboxEntry) b) =>
          a.$1.compareTo(b.$1);
      mergeSort(foldSelector, compare: byIndex);
      mergeSort(foldAuto, compare: byIndex);
      final plan = ReplacePlan(
        replace: fold,
        source: name.isNotEmpty ? name : fold.tag,
      );
      plan.selectorMembers.addAll([for (final (_, e) in foldSelector) e]);
      plan.autoMembers.addAll([for (final (_, e) in foldAuto) e]);
      ctx.addReplacePlan(plan);
    }
  }
}













List<String> resolveAutoSelectMembers(
  AutoSelectSpec spec,
  Map<NodeSpec, String> resolved, {
  String containerId = '',
  Map<NodeSpec, String>? rawTags,
  String groupTag = '',
  void Function(String line)? warn,
}) {
  final group = groupTag.isEmpty ? spec.tag : groupTag;
  final out = <String>[];
  switch (spec.membership) {
    case ExplicitMembers(:final members):


      final byRaw = <String, String>{};
      for (final e in resolved.entries) {
        final raw = rawTags == null ? e.key.tag : rawTags[e.key];
        if (raw != null && raw.isNotEmpty) byRaw.putIfAbsent(raw, () => e.value);
      }
      for (final link in members) {
        if (!link.isRoot && link.folderId != containerId) {

          warn?.call(groupMemberDroppedLine(group, link.tag));
          continue;
        }
        final tag = byRaw[link.tag];
        if (tag == null) {

          warn?.call(groupMemberDroppedLine(group, link.tag));
          continue;
        }
        if (!out.contains(tag)) out.add(tag);
      }
    case RuleMembers(:final include, :final exclude):
      final inc = tryCompileRegex(include);
      final exc = tryCompileRegex(exclude);




      final scoped = spec.tagSynonyms.isNotEmpty;
      final ownKeys = spec.tagSynonyms.values.toSet();
      for (final e in resolved.entries) {
        final key = nodeIdentityKey(e.key);
        if (scoped && !ownKeys.contains(key)) continue;


        final names = <String>[
          e.value,
          e.key.tag,
          ...spec.tagSynonyms.entries
              .where((s) => s.value == key)
              .map((s) => s.key),
        ];
        if (ruleAccepts(names, inc, exc)) out.add(e.value);
      }
  }
  return out;
}




String? resolveAutoSelectDefault(
  AutoSelectSpec spec,
  Map<NodeSpec, String> resolved, {
  String containerId = '',
  Map<NodeSpec, String>? rawTags,
  required List<String> members,
}) {
  final want = spec.manualDefault;
  if (want.isEmpty) return null;
  for (final e in resolved.entries) {
    final raw = rawTags == null ? e.key.tag : rawTags[e.key];
    if (raw == want && members.contains(e.value)) return e.value;
  }
  return members.contains(want) ? want : null;
}

bool _isExplicitMember(AutoSelectSpec spec, String rawTag) {
  final m = spec.membership;
  return m is ExplicitMembers && m.members.any((l) => l.tag == rawTag);
}



const kGroupMemberDroppedCode = 'group_member_dropped';




String groupMemberDroppedLine(String group, String member) {
  final w = RegistryWarning(
    code: kGroupMemberDroppedCode,
    params: {'tag': group, 'member': member},
  );
  return '${w.renderEn()} [$kGroupMemberDroppedCode]';
}















class FolderDetourPlan {
  FolderDetourPlan(FolderServers folder) : _personal = folder.nodeDetours {
    final n = folder.nodes.length;
    final raw = containerRawTags(folder);
    final rawIndex = <String, int>{};
    for (var i = 0; i < n; i++) {
      final t = raw[folder.nodes[i]];
      if (t != null) rawIndex.putIfAbsent(t, () => i);
    }
    int? intraIndex(NodeLink l) =>
        l.folderId == folder.id ? rawIndex[l.tag] : null;


    _edge = List<int?>.filled(n, null);
    for (var i = 0; i < n; i++) {
      final j = intraIndex(_personal[i]);
      if (j != null && j != i) _edge[i] = j;
    }


    final color = List<int>.filled(n, 0);
    void dfs(int u) {
      color[u] = 1;
      final v = _edge[u];
      if (v != null) {
        if (color[v] == 1) {
          _edge[u] = null;
        } else if (color[v] == 0) {
          dfs(v);
        }
      }
      color[u] = 2;
    }

    for (var i = 0; i < n; i++) {
      if (color[i] == 0) dfs(i);
    }

    _chainLinks = {
      for (final v in _edge) ?v,
    };


    final ovIdx = intraIndex(folder.detourPolicy.overrideDetour);
    if (ovIdx != null) {
      final exempt = <int>{};
      int? cur = ovIdx;
      while (cur != null && exempt.add(cur)) {
        cur = _edge[cur];
      }
      _exempt = exempt;
    } else {
      _exempt = const <int>{};
    }
  }

  final List<NodeLink> _personal;
  late final List<int?> _edge;
  late final Set<int> _chainLinks;
  late final Set<int> _exempt;


  bool isChainLink(int i) => _chainLinks.contains(i);



  DetourPolicy policyFor(int i, DetourPolicy base) {
    final personal = _personal[i];

    if (_exempt.contains(i)) {


      return base.copyWith(
          overrideDetour: personal, replaceDetourChain: false);
    }

    final folderReplaces =
        base.overrideDetour.isNotEmpty && base.replaceDetourChain;
    if (personal.isNotEmpty && base.useDetourServers && !folderReplaces) {
      return base.copyWith(
          overrideDetour: personal, replaceDetourChain: false);
    }
    return base;
  }
}
