import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../contract_paths.dart';





void main() {
  test('corpus skip guard — сводка пропусков', () {
    if (hasContractCorpus) return;

    printCorpusSkipSummary();

    final fromRun = readCorpusSkippedSuites();
    final suites = (fromRun.isNotEmpty ? fromRun : kKnownCorpusGatedSuites)
        .toList()
      ..sort();
    if (Platform.environment['CI'] == 'true' && suites.isNotEmpty) {


      print('corpus skipped suites (${suites.length}):');
      for (final s in suites) {

        print('  - $s');
      }
    }


    expect(hasRegistryMirror, isTrue,
        reason: 'зеркало реестра assets/contract обязано быть в git');
  });
}
