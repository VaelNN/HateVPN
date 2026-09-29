import 'dart:convert';
import 'dart:io';

import 'package:lxbox/services/l10n/template_overlay.dart';

import 'src/check_common.dart';

















const String _templatePath = 'assets/wizard_template.json';
const String _l10nDir = 'assets/l10n';

void main(List<String> args) {
  ensureAppCwd();
  final strict = parseStrict(args);
  final r = CheckReporter('template_check', strict: strict);

  final Map<String, String> extracted;
  try {
    final template = jsonDecode(File(_templatePath).readAsStringSync())
        as Map<String, dynamic>;
    extracted = TemplateOverlay.extract(template);
  } catch (e) {
    r.fail('extraction from $_templatePath failed: $e');
    exit(r.finish());
  }



  var localeCount = 0, missingTotal = 0;
  final l10nDir = Directory(_l10nDir);
  final overlayFiles = !l10nDir.existsSync()
      ? <File>[]
      : (l10nDir
          .listSync()
          .whereType<Directory>()
          .where((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last != 'en')
          .map((d) => File('${d.path}/template.json'))
          .where((f) => f.existsSync())
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path)));

  for (final f in overlayFiles) {
    localeCount++;
    final tag = f.parent.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final Map<String, dynamic> raw;
    try {
      raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    } catch (e) {
      r.fail('$tag/template.json: invalid JSON: $e');
      continue;
    }
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (!extracted.containsKey(key)) {
        r.fail('$tag/template.json: unknown key "$key" '
            '(not extractable from template)');
        continue;
      }
      if (value is! Map || value['value'] is! String) {
        r.fail('$tag/template.json: "$key": entry must be {"value": "..."}');
        continue;
      }
      final text = value['value'] as String;
      if (text.isEmpty) {
        r.fail('$tag/template.json: "$key": empty value');
      }
      if (text.startsWith('@')) {
        r.fail('$tag/template.json: "$key": value must not start with "@" '
            '(would be read as a template var reference)');
      }
      if (text.contains('{')) {
        r.fail('$tag/template.json: "$key": value must not contain "{"');
      }
    }
    final missing = extracted.keys.where((k) => !raw.containsKey(k)).length;
    if (missing > 0) {
      missingTotal += missing;
      r.warn('$tag/template.json: $missing key(s) untranslated '
          '(silent en fallback)');
    }
  }

  exit(r.finish(extraRows: [
    MapEntry('en keys', '${extracted.length}'),
    MapEntry('locale files', '$localeCount'),
    MapEntry('missing keys', '$missingTotal'),
  ]));
}
