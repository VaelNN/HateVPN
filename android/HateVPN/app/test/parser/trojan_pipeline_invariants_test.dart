import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../contract_paths.dart';

import 'engine_test_setup.dart';
import 'package:lxbox/models/node_spec.dart';
import 'package:lxbox/models/node_warning.dart';
import 'package:lxbox/models/template_vars.dart';
import 'package:lxbox/services/contract/parse_warnings.dart';
import 'package:lxbox/services/contract/warning_codes.dart';
import 'package:lxbox/services/node_hash.dart';
import 'package:lxbox/services/parser/uri_parsers.dart';


















void main() {
  final corpusSkip = corpusTestSkip('test/parser/trojan_pipeline_invariants_test.dart');
  setUpAll(loadEngineSections);


  setUpAll(() async {
    await loadTestRegistry();
  });

  group('§472 инвариант 4 — identity trojan не меняется', () {
    test('identity всего корпуса trojan считается и не пуста', () {
      final nodes = <NodeSpec>[];
      for (final f in Directory('$kVendorRoot/corpus/uri/trojan')
          .listSync()
          .whereType<File>()) {
        if (!f.path.endsWith('.uri')) continue;
        for (final line in f.readAsLinesSync()) {
          final t = line.trim();
          if (t.isEmpty || t.startsWith('#')) continue;
          final spec = parseUri(t);
          if (spec != null) nodes.add(spec);
        }
      }
      expect(nodes, isNotEmpty);
      final ids = sourceNodeIdentities(nodes);

      expect(ids.length, nodes.length);
    }, skip: corpusSkip);
  });

  group('§472 инвариант 3 — parseUri(toUri()) ≈ spec', () {




















    const notIdempotent = {'triple-enc', 'tr'};

    test('весь корпус trojan переживает круг', () {
      var checked = 0;
      for (final f in Directory('$kVendorRoot/corpus/uri/trojan')
          .listSync()
          .whereType<File>()) {
        if (!f.path.endsWith('.uri')) continue;
        for (final line in f.readAsLinesSync()) {
          final t = line.trim();
          if (t.isEmpty || t.startsWith('#')) continue;
          final a = parseUri(t);
          if (a == null) continue;
          if (notIdempotent.contains(a.tag)) continue;
          final b = parseUri(a.toUri());
          expect(b, isNotNull, reason: 'круг потерял узел: $t');


          expect(
            b!.emit(TemplateVars.empty).map,
            a.emit(TemplateVars.empty).map,
            reason: 'круг изменил тело: $t',
          );
          expect(legacyNodeIdentityHash(b), legacyNodeIdentityHash(a),
              reason: 'круг изменил identity: $t');
          checked++;
        }
      }

      expect(checked, greaterThan(25));
    }, skip: corpusSkip);
  });

  group('§472 инвариант 5 — цена разбора', () {




















    test('2000 trojan-узлов разбираются за разумное время', () {
      const n = 2000;
      final nodes = <NodeSpec>[];
      final uris = [
        for (var i = 0; i < n; i++)
          'trojan://pass123@example-$i.com:443?type=ws'
              '&path=%2Fx%3Fed%3D2560&security=tls&sni=example-$i.com'
              '&fp=chrome&alpn=h2,http/1.1#node$i',
      ];


      for (var i = 0; i < 200; i++) {
        parseUri(uris[i]);
      }

      var best = 1 << 30;
      for (var rep = 0; rep < 3; rep++) {
        nodes.clear();
        final sw = Stopwatch()..start();
        for (final u in uris) {
          final s = parseUri(u);
          if (s != null) nodes.add(s);
        }
        sw.stop();
        if (sw.elapsedMilliseconds < best) best = sw.elapsedMilliseconds;
      }
      expect(nodes, hasLength(n));
      expect(
        best,
        lessThan(3000),
        reason: 'разбор $n trojan-узлов конвейером: $best мс (лучший из трёх)',
      );
    });
  });

  group('§472 — второй проход по emit() узла конвейера не дублирует коды', () {
    test('annotateAllWithRegistry на разобранном узле ничего не добавляет', () {


      final spec = parseUri(
          'trojan://p@h.example:443?security=tls&fp=bogus&sni=x.com#n')!;
      final before = spec.warnings.length;
      final codes = spec.warnings.map(warningCodeOf).whereType<String>();
      expect(codes, contains('utls_fp_unknown'));

      annotateAllWithRegistry([spec]);
      expect(spec.warnings, hasLength(before),
          reason: 'второй проход задвоил коды узла конвейера');


      final w = spec.warnings
          .whereType<RegistryWarning>()
          .firstWhere((w) => w.code == 'utls_fp_unknown');
      expect(w.value, 'bogus');
    });
  });
}
