import 'dart:io';

import 'package:flutter_test/flutter_test.dart';












void main() {
  test('vertical scrollables with literal padding add the safe bottom inset', () {
    final scrollable = RegExp(
        r'\b(ListView|ListView\.builder|ListView\.separated|SingleChildScrollView|'
        r'GridView|GridView\.builder|GridView\.count|ReorderableListView|'
        r'ReorderableListView\.builder)\(\s*$');
    final literal = RegExp(r'padding:\s*(const\s+)?EdgeInsets\.');
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();

      final isSheetFile = lines.any((l) => l.contains('showAppBottomSheet'));
      for (var i = 0; i < lines.length; i++) {
        if (!scrollable.hasMatch(lines[i])) continue;
        final indent = lines[i].length - lines[i].trimLeft().length;
        final argIndent = ' ' * (indent + 2);
        final window = lines.sublist(i + 1, (i + 12).clamp(0, lines.length));
        final block = window.join('\n');
        if (block.contains('Axis.horizontal') ||
            block.contains('shrinkWrap: true') ||
            isSheetFile) {
          continue;
        }
        for (var k = 0; k < window.length; k++) {
          final l = window[k];


          if (!l.startsWith(argIndent) || l.startsWith('$argIndent ')) continue;
          if (!literal.hasMatch(l)) continue;
          final tail = window.sublist(k, (k + 4).clamp(0, window.length));
          final ok = tail.any((x) =>
              x.contains('withSafeBottom') ||
              x.contains('padding.bottom') ||
              x.contains('paddingOf') ||
              x.contains('bottomPad') ||
              x.contains('bottom-inset: handled'));
          if (!ok) offenders.add('${f.path}:${i + 2 + k}: ${l.trim()}');
          break;
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'add .withSafeBottom(context) (lib/widgets/safe_bottom.dart) '
            'or mark the line `// bottom-inset: handled — <why>`');
  });
}
