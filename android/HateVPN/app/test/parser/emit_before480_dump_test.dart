import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/template_vars.dart';
import 'package:lxbox/services/contract/registry.dart';
import 'package:lxbox/services/parser/engine/section_loader.dart';
import 'package:lxbox/services/parser/mappers/draft_sections.dart';
import 'package:lxbox/services/parser/uri_parsers.dart';















void main() {
  final on = Platform.environment['LX_EMIT_DUMP'] != null;

  test('дамп ссылок рукописного эмита', () async {
    if (!on) return;
    await ContractRegistry.I.loadFromDirectory('assets/contract');
    await MapperSections.I
        .loadDrafts(dir: 'assets/contract_draft', files: kDraftFiles);

    final dir = Directory('test/fixtures');
    for (final scheme in dir.listSync().whereType<Directory>()) {
      final f = File('${scheme.path}/pipeline_identity_before.json');
      if (!f.existsSync()) continue;
      final raw = jsonDecode(f.readAsStringSync()) as Map;
      final cases = (raw['cases'] as Map?)?.cast<String, dynamic>();
      if (cases == null) continue;

      final out = <String, dynamic>{};
      for (final e in cases.entries) {
        final c = (e.value as Map).cast<String, dynamic>();
        final uri = c['uri'] as String?;
        if (uri == null) continue;
        final spec = parseUri(uri);
        if (spec == null) continue;

        final oldUri = spec.toUri();





        final reread = parseUri(oldUri);
        out[e.key] = {
          'body': jsonDecode(jsonEncode(c['body'])),
          'uri_before': oldUri,
          'body_of_old_uri': reread == null
              ? null
              : jsonDecode(jsonEncode(reread.emit(TemplateVars.empty).map)),
        };
      }
      if (out.isEmpty) continue;
      File('${scheme.path}/emit_before480.json').writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({
              '_note': '§480 W7 — ссылки РУКОПИСНОГО `toUri`, снятые до его '
                  'удаления. Проверяется ЧТЕНИЕ: старая ссылка обязана '
                  'разбираться в то же тело (rawSource ручных узлов). Текст '
                  'новой ссылки может отличаться — это не ошибка.',
              'cases': out,
            })}\n',
      );
    }
  });
}
