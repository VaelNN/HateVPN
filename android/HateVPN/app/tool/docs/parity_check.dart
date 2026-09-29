import 'dart:io';

import '../l10n/src/check_common.dart';

































const _pairs = <({String en, String ru})>[
  (en: 'README.md', ru: 'README.ru.md'),
  (en: 'docs/USER_GUIDE.md', ru: 'docs/USER_GUIDE.ru.md'),
  (en: 'docs/DONATE.md', ru: 'docs/DONATE.ru.md'),
  (en: 'docs/PRIVACY_POLICY.md', ru: 'docs/PRIVACY_POLICY.ru.md'),
  (en: 'docs/SECURITY.md', ru: 'docs/SECURITY.ru.md'),
  (en: 'docs/AUTOMATION.md', ru: 'docs/AUTOMATION.ru.md'),
];

void main(List<String> args) {
  ensureAppCwd();
  final strict = parseStrict(args);
  final r = CheckReporter('docs_parity', strict: strict);


  final root = Directory.current.parent.path;
  var pairsChecked = 0;

  for (final pair in _pairs) {
    final enFile = File('$root/${pair.en}');
    final ruFile = File('$root/${pair.ru}');

    if (!enFile.existsSync() || !ruFile.existsSync()) {
      final missing = !enFile.existsSync() ? pair.en : pair.ru;
      r.fail('$missing: файл не найден (пара ${pair.en} ↔ ${pair.ru})');
      continue;
    }

    pairsChecked++;
    final en = _Doc.parse(enFile.readAsStringSync(), pair.en);
    final ru = _Doc.parse(ruFile.readAsStringSync(), pair.ru);

    _compareHeadings(r, en, ru);
    _compareFences(r, en, ru);
  }

  exit(r.finish(extraRows: [MapEntry('pairs', '$pairsChecked')]));
}


class _Doc {
  _Doc(this.path, this.headings, this.fenceCount);

  final String path;



  final List<int> headings;

  final int fenceCount;

  static final _headingRe = RegExp(r'^(#{2,6})\s+\S');

  static _Doc parse(String content, String path) {
    final headings = <int>[];
    var fences = 0;
    var inFence = false;

    for (final line in content.split('\n')) {


      if (line.trimLeft().startsWith('```')) {
        fences++;
        inFence = !inFence;
        continue;
      }
      if (inFence) continue;

      final h = _headingRe.firstMatch(line);
      if (h != null) headings.add(h.group(1)!.length);
    }

    if (inFence) {


      stdout.writeln('warn: $path: незакрытый блок ``` (нечётное число заборов)');
    }
    return _Doc(path, headings, fences ~/ 2);
  }
}

void _compareHeadings(CheckReporter r, _Doc en, _Doc ru) {
  if (en.headings.length != ru.headings.length) {
    final more = en.headings.length > ru.headings.length ? en.path : ru.path;
    final diff = (en.headings.length - ru.headings.length).abs();
    r.fail('${en.path} ↔ ${ru.path}: разное число разделов '
        '(${en.path}: ${en.headings.length}, ${ru.path}: ${ru.headings.length}) — '
        'в $more на $diff больше. Раздел добавлен в один язык и не перенесён '
        'во второй.');
    return;
  }


  for (var i = 0; i < en.headings.length; i++) {
    if (en.headings[i] != ru.headings[i]) {
      r.fail('${en.path} ↔ ${ru.path}: структура разделов разошлась на '
          'позиции ${i + 1} (${en.path}: H${en.headings[i]}, '
          '${ru.path}: H${ru.headings[i]}) — раздел вставлен на другом уровне '
          'вложенности.');
      return;
    }
  }
}

void _compareFences(CheckReporter r, _Doc en, _Doc ru) {
  if (en.fenceCount != ru.fenceCount) {
    r.fail('${en.path} ↔ ${ru.path}: разное число блоков кода '
        '(${en.path}: ${en.fenceCount}, ${ru.path}: ${ru.fenceCount}) — '
        'пример/схема потеряна при переводе.');
  }
}
