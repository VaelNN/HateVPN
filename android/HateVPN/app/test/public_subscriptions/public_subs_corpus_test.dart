































import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'corpus_report.dart';
import 'corpus_runner.dart';

bool _flag(String name) {
  final v = Platform.environment[name] ?? '';
  return v.isNotEmpty && v != '0';
}

void main() {
  if (!_flag('LX_CORPUS_PUBLIC')) {
    test('корпус публичных подписок', () {},
        skip: 'отдельный шаг: LX_CORPUS_PUBLIC=1 flutter test '
            'test/public_subscriptions');
    return;
  }

  if (!corpusAvailable) {
    test('корпус публичных подписок', () {},
        skip: 'нет $kCorpusRoot/index.json');
    return;
  }

  late List<SubscriptionResult> results;

  setUpAll(() async {
    results = await runCorpus(log: printOnFailure);
    if (_flag('LX_CORPUS_REPORT')) writeReports(results);
    if (_flag('LX_CORPUS_UPDATE_EXPECTED')) writeExpected(results);
  });

  test('каждый снимок с телом разобран без исключений', () {
    expect(results, isNotEmpty, reason: 'индекс корпуса пуст');


    final withBody = readCorpusIndex()
        .where((e) => e.bodyFile != null)
        .where((e) => File('$kCorpusRoot/${e.bodyFile}').existsSync())
        .length;
    expect(results.length, withBody);
  });

  test('узлы нашлись более чем в половине подписок', () {



    final withNodes = results.where((r) => r.nodesTotal > 0).length;
    expect(withNodes, greaterThan(results.length ~/ 2),
        reason: 'узлы нашлись только в $withNodes из ${results.length} — '
            'похоже, реестр или секции не загрузились');
  });

  test('числа совпадают с эталоном', () {
    if (_flag('LX_CORPUS_UPDATE_EXPECTED')) {

      return;
    }
    final f = File('$kCorpusRoot/expected.json');
    expect(f.existsSync(), isTrue,
        reason: 'эталона нет — создайте: LX_CORPUS_PUBLIC=1 '
            'LX_CORPUS_UPDATE_EXPECTED=1 flutter test test/public_subscriptions');
    final expected = (jsonDecode(f.readAsStringSync())
        as Map<String, dynamic>)['subscriptions'] as Map<String, dynamic>;

    final diffs = diffExpected(
        expected, {for (final r in results) r.id: r.toExpected()});
    expect(diffs, isEmpty,
        reason: 'расхождение с эталоном — регрессия ИЛИ прогресс реестра;\n'
            'разберитесь, затем обновите эталон отдельным коммитом:\n'
            '${diffs.join('\n')}');
  });
}
