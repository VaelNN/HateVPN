import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../contract_paths.dart';
import 'package:lxbox/config/consts.dart';
import 'package:lxbox/models/auto_select.dart';
import 'package:lxbox/models/codec/node_link_record.dart';
import 'package:lxbox/models/direction.dart';
import 'package:lxbox/models/node_spec.dart';
import 'package:lxbox/models/parser_config.dart';
import 'package:lxbox/models/source_chain.dart';
import 'package:lxbox/models/codec/source_replace_record.dart';
import 'package:lxbox/models/server_list.dart';
import 'package:lxbox/models/source_replace.dart';
import 'package:lxbox/services/builder/build_config.dart';
import 'package:lxbox/services/parser/uri_parsers.dart';

import '../parser/engine_test_setup.dart';
























const _templateOnlyKeys = {'interrupt_exist_connections', 'passive_check'};












const _autoDefaultKeys = {'url', 'interval', 'tolerance', 'idle_timeout'};







const Map<String, String> _skipFold = {};













const _warningProbes = <String, bool Function(String)>{
  'direction_filter_matched_nothing': _isFilterMatchedNothing,



  'chain_unsupported_by_core': _isChainUnsupported,
  'chain_hop_missing': _isChainHopMissing,
  'chain_cycle_through_direction': _isChainCycleThroughDirection,
};

bool _isFilterMatchedNothing(String line) =>
    line.contains('node filter matched no nodes');

bool _isChainUnsupported(String line) =>
    line.contains('does not know the "chain" outbound type');

bool _isChainHopMissing(String line) =>
    line.contains('A route without a hop is a different route') ||
    line.contains('a route without a hop would be a different route');

bool _isChainCycleThroughDirection(String line) =>
    line.contains('was left out of it') || line.contains('were left out of it');




const _unsupportedCodes = <String>{};










const _groupsNotComparable = <String, String>{
  'empty_pool_no_warning':
      'ожидание groups:[] описывает АВАРИЮ СБОРКИ лаунчера, а не модель: при '
          'нулевом пуле GenerateOutboundsFromParserConfig возвращает ошибку '
          '«no nodes parsed from any source» (outbound_generator.go:1050), '
          'Go-раннер получает res==nil и печатает пустой список. У LxBox '
          'такого обрыва нет и быть не должно: buildConfig обязан отдать '
          'РАБОЧИЙ конфиг, а Направление — цель route.rules[].outbound, и его '
          'исчезновение сделало бы ссылку висячей. Мобила применяет ту же '
          'политику, которую корпус объявляет верной в empty_direction_blocks '
          '(§201/§274): [block, direct-out] с default=block. Сверяется то, '
          'ради чего кейс заведён (README корпуса:52) — отсутствие '
          'предупреждения.',
};

void main() {
  if (corpusSuiteUnavailable('test/contract/direction_corpus_test.dart')) return;

  final root = Directory('$kVendorRoot/corpus/direction');
  if (!root.existsSync()) {

    test('корпус Направлений не синхронизирован', () {},
        skip: 'нет ${root.path} — запустите tool/sync_contract.sh');
    return;
  }

  final cases = root
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.direction.json'))
      .map((f) => f.path.substring(0, f.path.length - '.direction.json'.length))
      .toList()
    ..sort();

  if (cases.isEmpty) {

    test('корпус Направлений пуст', () {
      fail('нет .direction.json в ${root.path}');
    });
    return;
  }

  group('contract corpus: Directions', () {




    setUpAll(loadEngineSections);

    for (final base in cases) {
      final name = base.substring(root.path.length + 1);


      final skip = _skipFold[name];

      test(name, () async {
        final input = jsonDecode(File('$base.direction.json').readAsStringSync())
            as Map<String, dynamic>;
        final expected =
            jsonDecode(File('$base.expected.json').readAsStringSync())
                as Map<String, dynamic>;
        await _runCase(name, input, expected);
      }, skip: skip);
    }
  });
}

Future<void> _runCase(
  String name,
  Map<String, dynamic> input,
  Map<String, dynamic> expected,
) async {
  final doc = input['_'] as String? ?? '';
  final magic = (input['magic'] as Map?)?.cast<String, dynamic>() ?? const {};




  final tagMap = <String, String>{
    if (magic['direct'] is String) magic['direct'] as String: kDirectOutboundTag,
    if (magic['block'] is String) magic['block'] as String: kBlockOutboundTag,
  };
  String local(String tag) => tagMap[tag] ?? tag;

  final nodeTags =
      ((input['node_tags'] as List?) ?? const []).cast<String>().toList();
  final groupTags =
      ((input['group_tags'] as List?) ?? const []).cast<String>().toSet();

  final directions = [
    for (final raw in ((input['directions'] as List?) ?? const []))
      _toDirection((raw as Map).cast<String, dynamic>()),
  ];



  final chains = [
    for (final raw in ((input['chains'] as List?) ?? const []))
      _toChain((raw as Map).cast<String, dynamic>()),
  ];



  final coreSupportsChain = input['core_supports_chain'] as bool? ?? true;

  final result = await buildConfig(
    lists: nodeTags.isEmpty
        ? const []
        : [
            _sourceFor(nodeTags, groupTags,
                replace: sourceReplaceFromRecord(input['replace'])),
          ],
    template: _template(),
    settings: BuildSettings(
      directions: directions,
      chains: chains,
      coreVersion:
          coreSupportsChain ? '1.14.0-lx.27-rc.6' : '1.14.0-lx.27-rc.4',
    ),
  );
  expect(result.validation.isOk, isTrue,
      reason: '$doc\nконфиг не проходит валидацию:\n'
          '${result.validation.issues.join('\n')}');


  final why = _groupsNotComparable[name];
  if (why == null) {
    final gotGroups = _groupsOf(result, nodeTags, groupTags);
    final wantGroups = [
      for (final g in ((expected['groups'] as List?) ?? const []))
        _localizeGroup((g as Map).cast<String, dynamic>(), local),
    ];





    expect(_fmt(_stripUnnamedAutoDefaults(gotGroups, wantGroups)),
        _fmt(wantGroups),
        reason: doc);
  } else {



    final gotGroups = _groupsOf(result, nodeTags, groupTags);
    expect(_fmt(gotGroups), _fmt([
      for (final d in directions)
        if (d.enabled)
          {
            'tag': d.tag,
            'type': 'selector',
            'outbounds': [kBlockOutboundTag, kDirectOutboundTag],
            'default': kBlockOutboundTag,
          },
    ]), reason: '$doc\n\nсписок групп сверяется по правилу LxBox, не по '
        'ожиданию корпуса — $why');
  }


  final wantCodes =
      ((expected['warnings'] as List?) ?? const []).cast<String>().toSet();



  final gotCodes = {for (final w in result.buildCodes) w.code};
  for (final code in wantCodes) {
    expect(_unsupportedCodes.contains(code), isFalse,
        reason: '$doc\nкод "$code" объявлен неподдерживаемым, но кейс не '
            'скипнут — либо реализуйте, либо скипните кейс явно');
    if (gotCodes.contains(code)) continue;
    final probe = _warningProbes[code];
    expect(probe, isNotNull,
        reason: '$doc\nкод "$code" не получен сборкой и не описан в '
            '_warningProbes раннера; коды сборки: $gotCodes');
    expect(result.emitWarnings.any(probe!), isTrue,
        reason: '$doc\nожидалось предупреждение "$code", получено:\n'
            '${result.emitWarnings.join('\n')}');
  }


  for (final code in gotCodes) {
    expect(wantCodes.contains(code), isTrue,
        reason: '$doc\nлишний код сборки "$code"');
  }
  for (final entry in _warningProbes.entries) {
    if (wantCodes.contains(entry.key)) continue;
    expect(result.emitWarnings.any(entry.value), isFalse,
        reason: '$doc\nлишнее предупреждение "${entry.key}":\n'
            '${result.emitWarnings.join('\n')}');
  }
}






Direction _toDirection(Map<String, dynamic> c) {
  final auto = c['auto'];
  return Direction(
    tag: c['tag'] as String? ?? '',
    label: c['label'] as String? ?? '',
    enabled: c['enabled'] as bool? ?? true,
    includeDirect: c['include_direct'] as bool? ?? false,
    includeBlock: c['include_block'] as bool? ?? false,
    include: ((c['include'] as List?) ?? const []).cast<String>().toList(),
    nodeFilter: c['filter'] as String? ?? '',
    nodeFilterInvert: c['invert'] as bool? ?? false,
    defaultFilter: c['default'] as String? ?? '',
    interruptExistConnections:
        c['interrupt_exist_connections'] as bool? ?? true,
    auto: auto is Map ? _toAuto(auto.cast<String, dynamic>()) : null,
  );
}


SourceChain _toChain(Map<String, dynamic> c) => SourceChain(
      tag: c['tag'] as String? ?? '',
      label: c['label'] as String? ?? '',
      hops: [
        for (final h in (c['hops'] as List?) ?? const []) ?nodeLinkFromRecord(h),
      ],
      idleTimeout: c['idle_timeout'] as String? ?? '',
      stripEvasion:
          c['strip_evasion'] is bool ? c['strip_evasion'] as bool : null,
      strip: {
        for (final e in ((c['strip'] as Map?) ?? const {}).entries)
          if (e.value is bool) e.key.toString(): e.value as bool,
      },
      rewrite: ((c['rewrite'] as Map?) ?? const {}).cast<String, dynamic>(),
    );

DirectionAuto _toAuto(Map<String, dynamic> a) {
  const d = DirectionAuto();
  final sticky = a['sticky_hash'] as List?;
  return DirectionAuto(
    url: a['url'] as String? ?? d.url,
    interval: a['interval'] as String? ?? d.interval,
    tolerance: (a['tolerance'] as num?)?.toInt() ?? d.tolerance,
    idleTimeout: a['idle_timeout'] as String? ?? d.idleTimeout,
    interruptExistConnections:
        a['interrupt_exist_connections'] as bool? ?? d.interruptExistConnections,
    mode: UrltestMode.fromWire(a['mode'] as String?),
    pool: (a['pool'] as num?)?.toInt() ?? d.pool,
    poolTolerance: (a['pool_tolerance'] as num?)?.toInt() ?? 0,
    stickyHash: sticky == null
        ? d.stickyHash
        : [
            for (final s in sticky.cast<String>())
              if (StickyHashKey.fromWire(s) != null) StickyHashKey.fromWire(s)!,
          ],
  );
}











WizardTemplate _template() => WizardTemplate(
      parserConfig: ParserConfigBlock(),
      groupTemplates: GroupTemplates(),



      vars: [
        WizardVar(
            name: 'urltest_url',
            type: 'text',
            defaultValue: 'https://cp.cloudflare.com/generate_204'),
        WizardVar(name: 'urltest_interval', type: 'text', defaultValue: '5m'),
      ],
      varSections: const [],
      config: {
        'outbounds': [
          {'tag': kDirectOutboundTag, 'type': 'direct'},
          {'tag': kBlockOutboundTag, 'type': 'block'},
        ],
        'route': {'rules': <dynamic>[]},
      },
      selectableRules: const [],
      dnsOptions: const {},
      pingOptions: const {},
      speedTestOptions: const {},
    );










ServerList _sourceFor(
  List<String> nodeTags,
  Set<String> groupTags, {
  SourceReplace? replace,
}) {
  final nodes = <NodeSpec>[];
  for (var i = 0; i < nodeTags.length; i++) {
    final tag = nodeTags[i];
    if (groupTags.contains(tag)) {



      nodes.add(AutoSelectSpec(
        id: 'g$i',
        tag: tag,
        label: tag,
        membership: const RuleMembers(include: '.'),
      ));
      continue;
    }
    final spec = parseUri('vless://u$i@h$i.example:443'
        '?type=ws&security=tls#${Uri.encodeComponent(tag)}');
    expect(spec, isNotNull, reason: 'не разобрался узел корпуса "$tag"');
    nodes.add(spec!);
  }
  if (replace != null) {
    return SubscriptionServers(
      id: 'corpus',
      name: 'corpus',
      enabled: true,
      tagPrefix: '',
      detourPolicy: DetourPolicy.defaults,
      url: 'https://example-1.com/corpus',
      replace: replace,
      nodes: nodes,
    );
  }
  return UserServer(
    id: 'corpus',
    name: 'corpus',
    enabled: true,
    tagPrefix: '',
    detourPolicy: DetourPolicy.defaults,
    origin: UserSource.paste,
    nodes: nodes,
  );
}






List<Map<String, dynamic>> _groupsOf(
  BuildResult r,
  List<String> nodeTags,
  Set<String> groupTags,
) {
  final nodeTagSet = nodeTags.toSet();
  final out = <Map<String, dynamic>>[];
  for (final raw in (r.config['outbounds'] as List)) {
    final m = (raw as Map).cast<String, dynamic>();
    final tag = m['tag'] as String? ?? '';
    final type = m['type'] as String? ?? '';
    if (tag.isEmpty || nodeTagSet.contains(tag)) continue;


    if (type != 'selector' && type != 'urltest' && type != kChainOutboundType) {
      continue;
    }


    out.add({
      for (final e in m.entries)
        if (!_templateOnlyKeys.contains(e.key)) e.key: e.value,
    });
  }
  return out;
}



Map<String, dynamic> _localizeGroup(
  Map<String, dynamic> g,
  String Function(String) local,
) {
  final out = <String, dynamic>{};
  g.forEach((k, v) {
    if (_templateOnlyKeys.contains(k)) return;
    if (k == 'default' && v is String) {
      out[k] = local(v);
    } else if (k == 'outbounds' && v is List) {
      out[k] = [for (final t in v.cast<String>()) local(t)];
    } else {
      out[k] = v;
    }
  });
  return out;
}



List<Map<String, dynamic>> _stripUnnamedAutoDefaults(
  List<Map<String, dynamic>> got,
  List<Map<String, dynamic>> want,
) {
  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < got.length; i++) {
    final g = got[i];
    if (g['type'] != 'urltest' || i >= want.length) {
      out.add(g);
      continue;
    }
    final w = want[i];
    out.add({
      for (final e in g.entries)
        if (!(_autoDefaultKeys.contains(e.key) && !w.containsKey(e.key)))
          e.key: e.value,
    });
  }
  return out;
}












String _fmt(List<Map<String, dynamic>> groups) =>
    const JsonEncoder.withIndent('  ').convert(_sortKeys(groups));

Object? _sortKeys(Object? v) {
  if (v is Map) {
    final keys = v.keys.cast<String>().toList()..sort();
    return {for (final k in keys) k: _sortKeys(v[k])};
  }
  if (v is List) return [for (final e in v) _sortKeys(e)];
  return v;
}
