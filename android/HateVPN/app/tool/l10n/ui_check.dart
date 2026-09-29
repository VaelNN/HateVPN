import 'dart:convert';
import 'dart:io';

import 'src/check_common.dart';
import 'src/ui_scan.dart';















const String _l10nDir = 'assets/l10n';

void main(List<String> args) {
  ensureAppCwd();
  final strict = parseStrict(args);
  final r = CheckReporter('ui_check', strict: strict);



  final dir = Directory(_l10nDir);
  if (!dir.existsSync()) {
    r.fail('$_l10nDir missing');
    exit(r.finish());
  }
  final tags = dir
      .listSync(followLinks: false)
      .whereType<Directory>()
      .map((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last)
      .where((t) => File('$_l10nDir/$t/ui.json').existsSync())
      .toList()
    ..sort();
  if (tags.isEmpty) {
    r.fail('$_l10nDir: no <tag>/ui.json found');
    exit(r.finish());
  }


  final files = dartFilesUnder('lib');
  final uses = <UiKeyUse>[];
  var dynamicCount = 0;
  for (final path in files) {
    final res =
        scanForUiKeys(path: path, content: File(path).readAsStringSync());
    uses.addAll(res.uses);
    dynamicCount += res.dynamicKeys.length;
  }

  final rows = <MapEntry<String, String>>[];
  for (final tag in tags) {
    final dictPath = '$_l10nDir/$tag/ui.json';
    Map<String, dynamic> dict;
    try {
      dict =
          jsonDecode(File(dictPath).readAsStringSync()) as Map<String, dynamic>;
    } catch (e) {
      r.fail('$dictPath: invalid JSON: $e');
      continue;
    }

    final v = validateUiKeys(
      uses: uses,
      dynamicCount: dynamicCount,
      dict: dict,
      forms: formsForTag(tag),
    );



    for (final f in v.findings) {
      switch (f.kind) {
        case UiFindingKind.usageConflict:
        case UiFindingKind.shape:
        case UiFindingKind.arity:
          r.fail('$tag: ${f.message}');
        case UiFindingKind.missing:
        case UiFindingKind.orphan:
        case UiFindingKind.orphanSpecial:
          r.warn('$tag: ${f.message}');
      }
    }

    stdout.writeln('[ui_check] $tag: dict ${dict.length}, keys: ${v.keys}, '
        'missing: ${v.missing}, orphan: ${v.orphan}, '
        'arity-errors: ${v.arityErrors}, dynamic-skipped: ${v.dynamicSkipped}');

    rows.addAll([
      MapEntry('$tag dict keys', '${dict.length}'),
      MapEntry('$tag missing', '${v.missing}'),
      MapEntry('$tag orphan', '${v.orphan}'),
      MapEntry('$tag arity errors', '${v.arityErrors}'),
    ]);
  }

  exit(r.finish(extraRows: [
    MapEntry('locales', tags.join(', ')),
    ...rows,
    MapEntry('dart files scanned', '${files.length}'),
  ]));
}
