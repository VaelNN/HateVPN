import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../contract_paths.dart';
import 'package:lxbox/models/auto_select.dart';
import 'package:lxbox/models/custom_rule.dart';
import 'package:lxbox/models/direction.dart';
import 'package:lxbox/models/dns_ref.dart';
import 'package:lxbox/models/node_link.dart';
import 'package:lxbox/models/record_codec.dart';
import 'package:lxbox/models/node_spec.dart';
import 'package:lxbox/models/server_list.dart';
import 'package:lxbox/models/codec/source_replace_record.dart';
import 'package:lxbox/models/source_chain.dart';
import 'package:lxbox/services/json_clone.dart';
import 'package:lxbox/services/lx_backup.dart';
import 'package:lxbox/services/lx_backup_import.dart';
import 'package:lxbox/services/record_vars.dart';

import '../parser/engine_test_setup.dart';
















const Map<String, String> _pendingCases = {
};


void main() {
  if (corpusSuiteUnavailable('test/contract/backup_corpus_test.dart')) return;







  setUpAll(loadEngineSections);

  final root = Directory('$kVendorRoot/corpus/backup');
  if (!root.existsSync()) return;





  final cases = root
      .listSync()
      .whereType<File>()
      .where((f) =>
          f.path.endsWith('.backup.json') && !f.path.endsWith('.pre.backup.json'))
      .map((f) =>
          f.path.substring(0, f.path.length - '.backup.json'.length))
      .toList()
    ..sort();

  group('contract corpus: LX Backup', () {
    for (final base in cases) {
      final name = base.substring(root.path.length + 1);
      test(name, skip: _pendingCases[name], () async {
        final raw = File('$base.backup.json').readAsStringSync();



        final marker = jsonDecode(raw);
        if (marker is Map &&
            marker['lx_backup'] is num &&
            (marker['lx_backup'] as num) > kLxBackupVersion) {
          markTestSkipped('формат lx_backup ${marker['lx_backup']} новее '
              'читаемого $kLxBackupVersion');
          return;
        }





        final overrideFile = File('$base.expected.lxbox.json');
        final baseFile = File('$base.expected.json');
        final expectedFile =
            overrideFile.existsSync() ? overrideFile : baseFile;
        final expected =
            jsonDecode(expectedFile.readAsStringSync()) as Map<String, dynamic>;














        final templateFile = File('$base.template.json');
        final recordVars = templateFile.existsSync()
            ? RecordVarDecls.fromJson(
                jsonDecode(templateFile.readAsStringSync())
                    as Map<String, dynamic>)
            : RecordVarDecls.none;
        final state = _State(recordVars);
        final preFile = File('$base.pre.backup.json');
        if (preFile.existsSync()) {





          state.import(preFile.readAsStringSync(), sceneTargets: const {});
        }
        final file = state.import(raw);




        final gotCodes = file.warnings.map((w) => w.code).toSet().toList()..sort();
        final wantCodes =
            ((expected['warnings'] as List?) ?? const []).cast<String>().toList()
              ..sort();
        expect(gotCodes, wantCodes, reason: 'коды предупреждений');

        _checkWarningReasons(file, expected);
        _checkRules(state, expected);

        final wantVars = (expected['vars'] as Map?)?.cast<String, dynamic>();
        if (wantVars != null) {
          expect(file.vars, wantVars.map((k, v) => MapEntry(k, '$v')));
        }

        if (expected['route_final_applied'] == false) {
          expect(file.routeFinal, isNull);
        }

        _checkDirections(file, expected);
        _checkChains(state, expected);
        _checkDetours(state, expected);
        _checkGroups(state, expected);





        final wantHashes =
            ((expected['disabled_hashes'] as List?) ?? const []).cast<String>();
        if (wantHashes.isNotEmpty) {
          final found = <String>{
            for (final s in file.subscriptions) ...s.disabled.keys,
          };
          for (final want in wantHashes) {
            expect(found, contains(want),
                reason: 'отметка выключенной ноды $want не перенесена');
          }
        }

        _checkFolders(state, expected);
        _checkSubscriptions(state, expected);





        final wantRootServers = (expected['root_servers'] as List?)?.cast<String>();
        if (wantRootServers != null) {
          expect([
            for (final l in state.lists)
              if (l is UserServer) l.name,
          ], wantRootServers, reason: 'корневые одиночные узлы: состав и порядок');
        }

        _checkDns(state, expected);





        _checkOriginRaw(state, expected);





        await _checkReplaces(state, expected);




        if (expected['extensions_dropped'] == true) {
          expect(
              file.warnings.where((w) => w.code == kWarnExtensionsDropped),
              hasLength(1),
              reason: 'карман extensions обязан дать ровно один warning '
                  'на файл с перечнем затронутых записей');
        }
      });
    }
  });
}











class _State {
  _State(this.recordVars);

  final RecordVarDecls recordVars;
  List<ServerList> lists = [];
  List<Direction> directions = [];
  List<SourceChain> chains = [];
  List<CustomRule> rules = [];
  List<DnsServerRef> dnsServers = [];
  List<DnsRuleRef> dnsRules = [];
  String dnsFinal = '';
  String dnsStrategy = '';
  String dnsResolver = '';

  LxBackupFile import(
    String raw, {
    Set<String> sceneTargets = const {'proxy', 'direct'},
  }) {


    final plan = planLxBackupImport(
      raw,
      LxImportReceiver(
        lists: lists,
        directions: directions,
        chains: chains,
        receiverTargets: sceneTargets,
        dns: LxDns(
          servers: dnsServers,
          rules: dnsRules,
          finalServer: dnsFinal,
          strategy: dnsStrategy,
          defaultDomainResolver: dnsResolver,
        ),
        recordVars: recordVars,
      ),
    );
    lists = plan.lists;
    directions = plan.directions;
    chains = plan.chains;

    rules = plan.rules;
    final file = plan.file;
    final applied = plan.dns;
    if (applied != null) {
      dnsServers = applied.servers;
      dnsRules = applied.rules;
      dnsFinal = applied.dnsFinal;
      dnsStrategy = applied.strategy;
      dnsResolver = applied.defaultDomainResolver;
    }
    return file;
  }
}





void _checkWarningReasons(LxBackupFile file, Map<String, dynamic> expected) {
  final want = (expected['warning_reasons'] as Map?)?.cast<String, dynamic>();
  if (want == null) return;
  for (final entry in want.entries) {
    final got = <String>{
      for (final w in file.warnings)
        if (w.code == entry.key) w.reason,
    };
    expect(got, isNot(contains('')),
        reason: '${entry.key}: предупреждение без reason, а перечень причин '
            'нормирован');

    expect(got, (entry.value as List).cast<String>().toSet(),
        reason: '${entry.key}: причины');
  }
}



void _checkRules(_State state, Map<String, dynamic> expected) {
  final wantRules =
      ((expected['rules'] as List?) ?? const []).cast<Map<String, dynamic>>();
  final indexed = <(int, int, CustomRule)>[];
  var seq = 0;
  for (final r in state.rules) {
    indexed.add((r.orderNum ?? 1 << 30, seq++, r));
  }
  indexed.sort((a, b) {
    final byNum = a.$1.compareTo(b.$1);
    return byNum != 0 ? byNum : a.$2.compareTo(b.$2);
  });
  final axis = [for (final e in indexed) e.$3];

  expect(axis, hasLength(wantRules.length), reason: 'число правил на оси');
  for (var i = 0; i < wantRules.length; i++) {
    final want = wantRules[i];
    final got = axis[i];
    expect(got.name, want['name'], reason: 'имя правила #$i');
    expect(got.enabled, want['enabled'],
        reason: 'состояние правила ${want['name']}');


    final wantRefs = want['refs'];
    if (wantRefs is List) {
      expect(got.srsUrls, wantRefs.cast<String>(),
          reason: 'refs правила ${want['name']}');
    }


    final wantOutbound = want['outbound'];
    if (wantOutbound is String && wantOutbound.isNotEmpty) {
      expect(_outboundView(got), wantOutbound,
          reason: 'цель правила ${want['name']}');
    }


    if (want.containsKey('body')) {
      final gotBody = got is CustomRuleJson
          ? jsonDecode(got.json)
          : ruleToRecord(got)['body'];
      expect(gotBody, _deepEqualsJson(want['body']),
          reason: 'тело правила ${want['name']}');
    }

    final wantVars = want['vars'];
    if (wantVars is Map) {
      expect(got is CustomRulePreset ? got.varsValues : null,
          wantVars.map((k, v) => MapEntry('$k', '$v')),
          reason: 'переменные правила ${want['name']}');
    }
  }
}



String _outboundView(CustomRule r) {
  if (r is CustomRuleJson) {
    final body = jsonDecode(r.json);
    if (body is! Map) return '';
    if (body['action'] == 'reject') {
      return body['method'] == 'drop' ? 'drop' : 'reject';
    }
    return body['outbound'] is String ? body['outbound'] as String : '';
  }
  if (r is CustomRulePreset) return '';
  return r.outbound == kOutboundReject ? 'reject' : r.outbound;
}




void _checkDirections(LxBackupFile file, Map<String, dynamic> expected) {
  final wantDirections =
      ((expected['directions'] as List?) ?? const []).cast<Map<String, dynamic>>();
  if (wantDirections.isEmpty) return;
  final byTag = {for (final d in file.directions) d.tag: d};
  for (final want in wantDirections) {
    final tag = want['tag'] as String;
    final got = byTag[tag];
    expect(got, isNotNull, reason: 'направление $tag не создано импортом');



    final wantLabel = want['label'];
    if (wantLabel is String) {
      expect(got!.label, wantLabel, reason: '$tag: имя');
    }


    expect(got!.nodeFilter, want['filter'] ?? '', reason: '$tag: отбор');
    expect(got.nodeFilterInvert, want['invert'] ?? false,
        reason: '$tag: инверсия отбора');
    expect(got.includeDirect, want['include_direct'] ?? false,
        reason: '$tag: опция direct');
    expect(got.includeBlock, want['include_block'] ?? false,
        reason: '$tag: опция block');
    expect(got.auto != null, want['has_auto'] ?? false,
        reason: '$tag: автовыбор');



    final wantInclude = (want['include'] as List?)?.cast<String>();
    if (wantInclude != null) {
      expect(got.include, wantInclude, reason: '$tag: опции include');
    }
    final gotPing = file.directionPing[tag];
    final wantPingUrl = want['ping_url'];
    if (wantPingUrl is String) {
      expect(gotPing?.url, wantPingUrl, reason: '$tag: URL теста');
    }
    final wantPingTimeout = want['ping_timeout_ms'];
    if (wantPingTimeout is num) {
      expect(gotPing?.timeoutMs, wantPingTimeout.toInt(),
          reason: '$tag: таймаут теста');
    }
  }
}












void _checkChains(_State state, Map<String, dynamic> expected) {
  final wantChains =
      ((expected['chains'] as List?) ?? const []).cast<Map<String, dynamic>>();
  if (wantChains.isEmpty) return;
  expect(state.chains, hasLength(wantChains.length),
      reason: 'число цепочек: пропущенная merge\'ем запись не должна '
          'материализоваться второй копией');
  final byTag = {for (final c in state.chains) c.tag: c};
  for (final want in wantChains) {
    final tag = want['tag'] as String;
    final got = byTag[tag];
    expect(got, isNotNull, reason: 'цепочка $tag не создана импортом');

    final wantLabel = want['label'];
    if (wantLabel is String) {
      expect(got!.label, wantLabel, reason: '$tag: имя');
    }


    final wantEnabled = want['enabled'];
    if (wantEnabled is bool) {
      expect(got!.enabled, wantEnabled,
          reason: '$tag: enabled — отсутствие ключа в записи файла обязано '
              'читаться как true, явный false — как false');
    }
    final canon = _canonOf(got!);
    final wantHops = (want['hops'] as List?)?.cast<Map<String, dynamic>>();
    if (wantHops != null) {
      expect(
        [for (final h in got.hops) _resolveHop(h, state.lists).view],
        [for (final w in wantHops) _wantLinkView(w)],
        reason: '$tag: позиции как ссылки (контейнер/тег)',
      );
    }
    canon['hops'] = [for (final h in got.hops) h.tag];
    expect(canon, _deepEqualsJson(want['chain']),
        reason: '$tag: канон цепочки искажён');
  }
}






({String tag, String view}) _resolveHop(NodeLink hop, List<ServerList> lists) {
  if (hop.isRoot) return (tag: hop.tag, view: '/${hop.tag}');
  for (final l in lists) {
    if (l.id != hop.folderId) continue;
    switch (l) {
      case FolderServers():
        return (tag: hop.tag, view: 'folder:${l.name}/${hop.tag}');
      case SubscriptionServers():
        return (tag: hop.tag, view: 'subscription:${l.url}/${hop.tag}');
      case UserServer():
        break;
    }
  }
  return (tag: hop.tag, view: 'folder_id:${hop.folderId}/${hop.tag}');
}




String _wantLinkView(Map<String, dynamic> w) {
  final tag = w['tag'];
  final folder = w['folder'];
  if (folder is String && folder.isNotEmpty) return 'folder:$folder/$tag';
  final subscription = w['subscription'];
  if (subscription is String) return 'subscription:$subscription/$tag';
  final folderId = w['folder_id'];
  if (folderId is String) return 'folder_id:$folderId/$tag';
  return '/$tag';
}




void _checkDetours(_State state, Map<String, dynamic> expected) {
  final want = (expected['detours'] as Map?)?.cast<String, dynamic>();
  if (want == null) return;
  final got = <String, String>{
    for (final l in state.lists)
      if (l is UserServer && l.detourPolicy.overrideDetour.isNotEmpty)
        l.name: _resolveHop(l.detourPolicy.overrideDetour, state.lists).view,
    for (final l in state.lists)
      if (l is FolderServers)
        for (final m in l.members)
          if (m.detour.isNotEmpty && m.node != null)
            m.node!.tag: _resolveHop(m.detour, state.lists).view,
  };
  expect(got, {
    for (final e in want.entries)
      e.key: _wantLinkView((e.value as Map).cast<String, dynamic>()),
  }, reason: 'detour узлов: носители и ссылки');
}






void _checkGroups(_State state, Map<String, dynamic> expected) {
  final want = (expected['groups'] as Map?)?.cast<String, dynamic>();
  if (want == null) return;
  final got = <String, List<String>>{
    for (final l in state.lists)
      if (l is FolderServers)
        for (final m in l.members)
          if (m.node case final AutoSelectSpec g)
            g.tag: switch (g.membership) {
              ExplicitMembers(:final members) => [
                  for (final link in members)
                    _resolveHop(
                            link.isRoot
                                ? NodeLink(folderId: l.id, tag: link.tag)
                                : link,
                            state.lists)
                        .view,
                ],
              RuleMembers() => const <String>[],
            },
  };
  final gotDefault = <String, String?>{
    for (final l in state.lists)
      if (l is FolderServers)
        for (final m in l.members)
          if (m.node case final AutoSelectSpec g)
            g.tag: g.manualDefault.isEmpty
                ? null
                : _resolveHop(NodeLink(folderId: l.id, tag: g.manualDefault),
                        state.lists)
                    .view,
  };
  expect(got.keys.toSet(), want.keys.toSet(), reason: 'набор групп');
  for (final entry in want.entries) {
    final w = (entry.value as Map).cast<String, dynamic>();
    expect(
      got[entry.key],
      [
        for (final m in (w['members'] as List? ?? const []))
          _wantLinkView((m as Map).cast<String, dynamic>()),
      ],
      reason: '${entry.key}: члены группы',
    );


    expect(gotDefault[entry.key], w.containsKey('default')
        ? _wantLinkView((w['default'] as Map).cast<String, dynamic>())
        : null,
        reason: '${entry.key}: default группы');
  }
}








void _checkFolders(_State state, Map<String, dynamic> expected) {
  final wantFolders = (expected['folders'] as Map?)?.cast<String, dynamic>();
  if (wantFolders != null) {
    final gotFolders = <String, List<String>>{
      for (final l in state.lists)
        if (l is FolderServers)
          l.name: [for (final m in l.members) m.node?.tag ?? ''],
    };
    expect(gotFolders.keys.toSet(), wantFolders.keys.toSet(),
        reason: 'состав папок: имена');
    for (final entry in wantFolders.entries) {
      expect(gotFolders[entry.key], (entry.value as List).cast<String>(),
          reason: 'папка ${entry.key}: состав и порядок членов');
    }
  }
  final wantIds = (expected['folder_ids'] as Map?)?.cast<String, dynamic>();
  if (wantIds != null) {
    final gotIds = <String, String>{
      for (final l in state.lists)
        if (l is FolderServers) l.name: l.id,
    };
    for (final entry in wantIds.entries) {
      expect(gotIds[entry.key], entry.value,
          reason: 'папка ${entry.key}: id после импорта (ступень слияния)');
    }
  }
}








void _checkSubscriptions(_State state, Map<String, dynamic> expected) {
  final wantSubs = (expected['subscriptions'] as Map?)?.cast<String, dynamic>();
  if (wantSubs == null) return;
  final gotSubs = <String, SubscriptionServers>{
    for (final l in state.lists)
      if (l is SubscriptionServers) l.url: l,
  };
  expect(gotSubs.keys.toSet(), wantSubs.keys.toSet(),
      reason: 'набор подписок после слияния: ключ — url байт в байт');
  for (final entry in wantSubs.entries) {
    final got = gotSubs[entry.key]!;
    final want = (entry.value as Map).cast<String, dynamic>();
    expect(got.name, want['label'], reason: '${entry.key}: label');
    expect(got.tagPrefix, want['prefix'] ?? '',
        reason: '${entry.key}: префикс тегов');
    expect('', want['postfix'] ?? '',
        reason: '${entry.key}: постфикс тегов — поля у LxBox нет');
    final wantEnabled = want['enabled'];
    if (wantEnabled is bool) {
      expect(got.enabled, wantEnabled, reason: '${entry.key}: enabled');
    }
    final wantNodes = (want['nodes'] as List?)?.cast<String>();
    if (wantNodes != null) {


      expect([for (final n in got.nodes) n.tag], wantNodes,
          reason: '${entry.key}: состав узлов пережил слияние');
    }
    final wantPending = (want['pending_disabled'] as List?)?.cast<String>();
    if (wantPending != null) {

      expect(got.disabledHashes.keys.toList()..sort(),
          wantPending.toList()..sort(),
          reason: '${entry.key}: отметки выключения ОБЪЕДИНЯЮТСЯ, '
              'а не замещаются файлом');
    }
  }
}











void _checkDns(
  _State state,
  Map<String, dynamic> expected,
) {
  final want = (expected['dns'] as Map?)?.cast<String, dynamic>();
  if (want == null) return;
  final wantServers =
      ((want['servers'] as List?) ?? const []).cast<Map<String, dynamic>>();
  expect(state.dnsServers, hasLength(wantServers.length),
      reason: 'число DNS-серверов');
  for (var i = 0; i < wantServers.length; i++) {


    final got = dnsServerToRecord(state.dnsServers[i]);
    final w = wantServers[i];
    expect(got['kind'], w['kind'], reason: 'DNS-сервер #$i: вид');
    expect(got['tag'] ?? '', w['tag'] ?? '', reason: 'DNS-сервер #$i: тег');
    expect(got['ref'] ?? '', w['ref'] ?? '', reason: 'DNS-сервер #$i: ссылка');
    if (w['enabled'] is bool) {
      expect(got['enabled'], w['enabled'], reason: 'DNS-сервер #$i: enabled');
    }
    if (w['body'] != null) {
      expect(got['body'], _deepEqualsJson(w['body']),
          reason: 'DNS-сервер #$i: тело');
    }
    expect(got['vars'] ?? const <String, dynamic>{},
        _deepEqualsJson(w['vars'] ?? const <String, dynamic>{}),
        reason: 'DNS-сервер #$i: vars записи');
  }
  if (want['rules'] is num) {
    expect(state.dnsRules, hasLength((want['rules'] as num).toInt()),
        reason: 'число DNS-правил');
  }
  if (want['strategy'] is String) {
    expect(state.dnsStrategy, want['strategy'], reason: 'dns.strategy');
  }
  if (want['final'] is String) {
    expect(state.dnsFinal, want['final'], reason: 'dns.final');
  }
  if (want['default_domain_resolver'] is String) {
    expect(state.dnsResolver, want['default_domain_resolver'],
        reason: 'dns.default_domain_resolver');
  }
}





Map<String, dynamic> _canonOf(SourceChain c) => c.toCanonJson();




Matcher _deepEqualsJson(Object? want) =>
    predicate<Object?>((got) => deepEqualsJson(got, want), 'deep-equals $want');





Future<void> _checkReplaces(_State state, Map<String, dynamic> expected) async {
  final want = (expected['replaces'] as Map?)?.cast<String, dynamic>();
  if (want == null) return;
  String keyOf(ServerList l) => switch (l) {
        SubscriptionServers s => s.url,
        _ => l.name,
      };
  final got = <String, Map<String, dynamic>>{
    for (final l in state.lists)
      if (l.replace case final r?) keyOf(l): sourceReplaceToRecord(r),
  };
  final out = await buildLxBackup(
      lists: state.lists, rules: const [], vars: const {});
  final exported = <String, Map<String, dynamic>>{
    for (final raw in (jsonDecode(out.json)['sources'] as List))
      if (raw is Map && raw['replace'] is Map)
        (raw['url'] is String ? raw['url'] as String : raw['name'] as String):
            (raw['replace'] as Map).cast<String, dynamic>(),
  };
  void compare(String where, Map<String, Map<String, dynamic>> side) {

    expect(side.keys.toSet(), {
      for (final e in want.entries)
        if (e.value != null) e.key,
    }, reason: '$where: набор свёрнутых источников');
    for (final e in want.entries) {
      if (e.value == null) continue;
      final w = (e.value as Map).cast<String, dynamic>();
      final g = side[e.key]!;
      expect(g['mode'], w['mode'], reason: '$where ${e.key}: mode');
      expect(g['tag'], w['tag'], reason: '$where ${e.key}: tag');
      final wAuto = (w['auto'] as Map?)?.cast<String, dynamic>();
      final gAuto = (g['auto'] as Map?)?.cast<String, dynamic>();
      if (wAuto == null) {
        expect(gAuto, isNull, reason: '$where ${e.key}: auto у manual');
        continue;
      }
      expect(gAuto, isNotNull, reason: '$where ${e.key}: auto');
      for (final a in wAuto.entries) {
        expect(gAuto![a.key], a.value, reason: '$where ${e.key}: auto.${a.key}');
      }
    }
  }

  compare('состояние', got);
  compare('повторный экспорт', exported);
}



void _checkOriginRaw(_State state, Map<String, dynamic> expected) {
  final want = (expected['origin_raw'] as Map?)?.cast<String, dynamic>();
  if (want == null) return;
  want.forEach((key, wantBody) {
    final slash = key.indexOf('/');
    String? raw;
    if (slash < 0) {
      for (final l in state.lists) {
        if (l is UserServer &&
            (l.name == key || (l.nodes.isNotEmpty && l.nodes.first.tag == key))) {
          raw = l.rawBody;
          break;
        }
      }
    } else {
      final folder = key.substring(0, slash);
      final tag = key.substring(slash + 1);
      for (final l in state.lists) {
        if (l is! FolderServers || l.name != folder) continue;
        for (final m in l.members) {
          if (m.node?.tag == tag) raw = m.raw;
        }
      }
    }
    expect(raw, isNotNull, reason: 'origin_raw: нет записи $key');
    final got = (jsonDecode(raw!) as Map).cast<String, dynamic>()
      ..remove('tag');
    expect(got, wantBody, reason: 'origin_raw $key: источник — тело узла');
  });
}
