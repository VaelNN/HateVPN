
























import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

void main(List<String> args) {
  final lockFile = File('contract.lock');
  final dir = Directory('contract');

  if (!dir.existsSync()) {
    stdout.writeln('contract/: копии нет — контрактные тесты пропускаются '
        '(синхронизируйте локально: bash tool/sync_contract.sh)');
    return;
  }
  if (!lockFile.existsSync()) {
    stderr.writeln('contract/ есть, а contract.lock нет: непонятно, какая '
        'версия контракта в дереве. Запустите tool/sync_contract.sh');
    exitCode = 1;
    return;
  }

  final expected = _lockHash(lockFile.readAsStringSync());
  if (expected == null) {
    stderr.writeln('contract.lock без поля sha256');
    exitCode = 1;
    return;
  }

  final actual = _treeHash(dir);
  if (actual != expected) {
    stderr.writeln('Копия контракта не совпадает с contract.lock:\n'
        '  в дереве: $actual\n'
        '  в lock:   $expected\n'
        'Копию не правят руками — источник живёт в репозитории лаунчера. '
        'Запустите tool/sync_contract.sh, чтобы обновить копию и lock.');
    exitCode = 1;
    return;
  }

  stdout.writeln('contract/: совпадает с contract.lock ($actual)');

  final mirrorDiff = _mirrorDiff(dir);
  if (mirrorDiff.isNotEmpty) {
    stderr.writeln('§460 — зеркало реестра assets/contract/ разошлось с '
        'копией контракта:\n${mirrorDiff.map((l) => '  $l').join('\n')}\n'
        'Зеркало не правят руками — оно кладётся tool/sync_contract.sh. '
        'Запустите скрипт, чтобы пересобрать зеркало.');
    exitCode = 1;
    return;
  }
  stdout.writeln('assets/contract/: зеркало реестра совпадает с копией');

  final docsDiff = _docsMirrorDiff(dir);
  if (docsDiff.isNotEmpty) {
    stderr.writeln('§460 W2b — зеркало документации ../docs/contract/ '
        'разошлось с copy contract/docs/generated/:\n'
        '${docsDiff.map((l) => '  $l').join('\n')}\n'
        'Зеркало не правят руками — оно кладётся tool/sync_contract.sh. '
        'Запустите скрипт, чтобы пересобрать зеркало.');
    exitCode = 1;
    return;
  }
  stdout.writeln('../docs/contract/: зеркало документации совпадает с копией');
}






List<String> _docsMirrorDiff(Directory contractDir) {
  final src = Directory('${contractDir.path}/docs/generated');
  final mirror = Directory('../docs/contract');
  if (!src.existsSync()) return const [];
  if (!mirror.existsSync()) {
    return ['../docs/contract/: зеркала нет вовсе'];
  }

  Set<String> relFiles(Directory d) => d
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path.substring(d.path.length + 1))
      .toSet();

  final diff = <String>[];
  final srcFiles = relFiles(src);
  final mirrorFiles = relFiles(mirror)..remove('README.md');

  for (final rel in srcFiles.toList()..sort()) {
    if (!mirrorFiles.contains(rel)) {
      diff.add('$rel: в зеркале нет');
      continue;
    }
    final a = File('${src.path}/$rel').readAsBytesSync();
    final b = File('${mirror.path}/$rel').readAsBytesSync();
    if (a.length != b.length || !_bytesEqual(a, b)) {
      diff.add('$rel: содержимое отличается');
    }
  }
  for (final rel in mirrorFiles.difference(srcFiles).toList()..sort()) {
    diff.add('$rel: в копии контракта нет, а в зеркале есть');
  }
  return diff;
}




List<String> _mirrorDiff(Directory contractDir) {
  final diff = <String>[];

  void compare(String rel) {
    final src = File('${contractDir.path}/$rel');
    final mirror = File('assets/contract/$rel');
    if (!mirror.existsSync()) {
      diff.add('$rel: в зеркале нет');
      return;
    }
    if (!src.existsSync()) {
      diff.add('$rel: в копии контракта нет, а в зеркале есть');
      return;
    }
    final a = src.readAsBytesSync();
    final b = mirror.readAsBytesSync();
    if (a.length != b.length || !_bytesEqual(a, b)) {
      diff.add('$rel: содержимое отличается');
    }
  }

  compare('VERSION');
  for (final sub in const ['registry', 'registry/protocols']) {
    final srcDir = Directory('${contractDir.path}/$sub');
    if (!srcDir.existsSync()) continue;
    for (final f in srcDir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      compare('$sub/${f.uri.pathSegments.last}');
    }
  }



  for (final sub in const ['registry', 'registry/protocols']) {
    final mirrorDir = Directory('assets/contract/$sub');
    if (!mirrorDir.existsSync()) continue;
    for (final f in mirrorDir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      final rel = '$sub/${f.uri.pathSegments.last}';
      if (!File('${contractDir.path}/$rel').existsSync()) {
        diff.add('$rel: в копии контракта нет, а в зеркале есть');
      }
    }
  }

  return diff;
}

bool _bytesEqual(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String? _lockHash(String content) {
  for (final line in const LineSplitter().convert(content)) {
    if (line.startsWith('sha256=')) return line.substring('sha256='.length).trim();
  }
  return null;
}





String _treeHash(Directory dir) {
  final paths = dir
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path)
      .toList()
    ..sort();





  final bytes = <int>[];
  for (final path in paths) {
    bytes.addAll(File(path).readAsBytesSync());
  }
  return sha256.convert(bytes).toString();
}
