







import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/services/contract/registry.dart';


const kRegistryRoot = 'assets/contract';


const kVendorRoot = 'contract';


const kContractRoot = kRegistryRoot;

bool get hasRegistryMirror =>
    Directory('$kRegistryRoot/registry').existsSync();

bool get hasVendorContract => Directory(kVendorRoot).existsSync();

bool get hasContractCorpus =>
    Directory('$kVendorRoot/corpus').existsSync();


Future<void> loadTestRegistry() async {
  if (!ContractRegistry.I.isLoaded) {
    await ContractRegistry.I.loadFromDirectory(kRegistryRoot);
  }
}



const _skipRegistryPath = '.dart_tool/corpus_skip_registry.txt';

void _appendCorpusSkipRecord(String record) {
  if (hasContractCorpus) return;
  final f = File(_skipRegistryPath);
  f.parent.createSync(recursive: true);
  f.writeAsStringSync('$record\n', mode: FileMode.append, flush: true);
}


String? corpusTestSkip(String suite, {String subpath = 'corpus'}) {
  if (hasContractCorpus) return null;
  _appendCorpusSkipRecord('test:$suite');
  return 'нет $kVendorRoot/$subpath — синхронизируйте: bash app/tool/sync_contract.sh';
}


bool corpusSuiteUnavailable(String suite) {
  if (hasContractCorpus) return false;
  _appendCorpusSkipRecord('suite:$suite');
  printCorpusSkipSummary();
  return true;
}


Set<String> readCorpusSkippedSuites() {
  final f = File(_skipRegistryPath);
  if (!f.existsSync()) return {};
  final suites = <String>{};
  for (final line in f.readAsLinesSync()) {
    final parts = line.split(':');
    if (parts.length < 2) continue;
    suites.add(parts.sublist(1).join(':'));
  }
  return suites;
}

int readCorpusSkippedTestCount() {
  final f = File(_skipRegistryPath);
  if (!f.existsSync()) return 0;
  return f
      .readAsLinesSync()
      .where((l) => l.startsWith('test:'))
      .length;
}


void printCorpusSkipSummary() {
  if (hasContractCorpus) return;
  final n = readCorpusSkippedTestCount();
  final suites = readCorpusSkippedSuites();

  final effective = n > 0 ? n : suites.length;

  print(
      'corpus skipped: app/contract отсутствует, $effective тестов');
}



const kKnownCorpusGatedSuites = <String>[
  'test/contract/backup_corpus_test.dart',
  'test/contract/body_contract_test.dart',
  'test/contract/contract_test.dart',
  'test/contract/direction_corpus_test.dart',
  'test/contract/lx_backup_group_links_test.dart',
  'test/contract/lx_backup_roundtrip_test.dart',
  'test/contract/node_edit_corpus_test.dart',
  'test/contract/registry_invariant_test.dart',
  'test/contract/template_contract_test.dart',
  'test/contract/template_for_each_corpus_test.dart',
  'test/contract/template_load_reject_test.dart',
  'test/parser/anytls_pipeline_invariants_test.dart',
  'test/parser/http_pipeline_invariants_test.dart',
  'test/parser/naive_pipeline_invariants_test.dart',
  'test/parser/shadowsocks_pipeline_invariants_test.dart',
  'test/parser/socks_pipeline_invariants_test.dart',
  'test/parser/ssh_pipeline_invariants_test.dart',
  'test/parser/trojan_pipeline_invariants_test.dart',
  'test/parser/vmess_pipeline_invariants_test.dart',
  'test/parser/hysteria2_pipeline_invariants_test.dart',
  'test/parser/masque_pipeline_invariants_test.dart',
  'test/parser/tuic_pipeline_invariants_test.dart',
  'test/parser/vless_pipeline_invariants_test.dart',
  'test/parser/wireguard_pipeline_invariants_test.dart',
];
