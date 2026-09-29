import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/template_vars.dart';
import 'package:lxbox/services/contract/registry.dart';
import 'package:lxbox/services/node_hash.dart';
import 'package:lxbox/services/parser/engine/section_loader.dart';
import 'package:lxbox/services/parser/mappers/draft_sections.dart';
import 'package:lxbox/services/parser/uri_parsers.dart';


















const _registryRoot = 'assets/contract';



const Map<String, int> _switched = {
  'vless': 99,
  'socks': 17,
  'ssh': 13,
  'anytls': 13,
  'shadowsocks': 27,
  'http': 12,
  'naive': 19,


  'vmess': 21,
};




















const Set<String> _awaitingContractSync = <String>{};

Map<String, Map<String, dynamic>> _cases(String scheme) {
  final raw = jsonDecode(
    File('test/fixtures/$scheme/pipeline_identity_before.json')
        .readAsStringSync(),
  ) as Map;
  return (raw['cases'] as Map).map(
    (k, v) => MapEntry(k as String, (v as Map).cast<String, dynamic>()),
  );
}

void main() {
  final mirrored = Directory('$_registryRoot/registry').existsSync();
  final skip = mirrored ? null : 'зеркало реестра не найдено';

  setUpAll(() async {
    if (!mirrored) return;
    await ContractRegistry.I.loadFromDirectory(_registryRoot);
    await MapperSections.I
        .loadDrafts(dir: 'assets/contract_draft', files: kDraftFiles);
  });

  group('§480 W4 — схема на движке даёт прежние identity, тег и тело', () {
    for (final entry in _switched.entries) {
      final scheme = entry.key;
      test(scheme, () {
        final cases = _cases(scheme);
        expect(cases, hasLength(entry.value),
            reason: 'снимок $scheme изменился в размере: было ${entry.value}, '
                'стало ${cases.length}');

        final red = <String>[];
        for (final e in cases.entries) {
          final uri = e.value['uri'] as String;
          final want = e.value['identity'] as String?;
          final spec = parseUri(uri);

          if (want == null) {
            if (spec != null) red.add('${e.key}: СТАЛ разбираться');
            continue;
          }
          if (spec == null) {
            red.add('${e.key}: перестал разбираться');
            continue;
          }
          final got = legacyNodeIdentityHash(spec);
          if (got != want) {
            red.add('${e.key}: identity $got != $want');
          }


          if (e.value.containsKey('tag') && spec.tag != e.value['tag']) {
            red.add('${e.key}: тег "${spec.tag}" != "${e.value['tag']}"');
          }
          if (e.value.containsKey('body')) {
            final body = jsonEncode(spec.emit(TemplateVars.empty).map);
            final wantBody = jsonEncode(e.value['body']);
            if (body != wantBody) {
              red.add('${e.key}: тело\n  наше: $body\n  эталон: $wantBody');
            }






            final delta = e.value['_delta480'] as String?;
            if (delta != null) {
              final before = e.value['_before480'] as Map?;
              if (before == null) {
                red.add('${e.key}: помечен дельтой, но прежних значений рядом '
                    'нет — «было → стало» обязано быть записано ($delta)');
              } else if (jsonEncode(before['body']) == body) {
                red.add('${e.key}: помечен дельтой, но тело не изменилось — '
                    'пометка протухла ($delta)');
              }
            }
          }
        }
        expect(red, isEmpty, reason: 'красные кейсы:\n${red.join('\n')}');
      },
          skip: skip ??
              (_awaitingContractSync.contains(scheme)
                  ? 'ждёт синка контракта: секция в зеркале отстала от '
                      'develop лаунчера (см. _awaitingContractSync)'
                  : null));
    }
  });
}
