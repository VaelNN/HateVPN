import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/services/contract/registry.dart';
import 'package:lxbox/services/parser/engine/engine_mapper.dart';
import 'package:lxbox/services/parser/engine/section_loader.dart';
import 'package:lxbox/services/parser/mappers/draft_sections.dart';
import 'package:lxbox/services/parser/uri_parsers.dart';










void main() {
  final on = Platform.environment['LX_PERF'] == '1';

  test('2000 ссылок: конвейер не дороже потолка', () async {
    if (!on) return;
    await ContractRegistry.I.loadFromDirectory('assets/contract');
    await MapperSections.I
        .loadDrafts(dir: 'assets/contract_draft', files: kDraftFiles);




    const shapes = [
      'trojan://pass123@example-1.com:443?security=tls&sni=example-1.com#n',
      'trojan://pass123@example-1.com:443?type=ws&security=tls&host=example-1.com&path=%2Fws&sni=example-1.com#n',
      'trojan://pass123@example-1.com:443?type=ws&path=%2Fx%3Fed%3D2560&security=tls&sni=example-1.com#n',
      'trojan://pass123@example-1.com:443?type=grpc&security=tls&serviceName=gsvc&sni=example-1.com#n',
      'trojan://pass123@example-1.com:443?security=tls&alpn=h2%2Chttp%2F1.1&fp=hellochrome_auto&sni=example-1.com#n',
    ];
    final links = [
      for (var i = 0; i < 2000; i++) shapes[i % shapes.length],
    ];



    for (final l in links) {
      parseUri(l);
    }





    var bestLayer = const Duration(days: 1);
    var best = const Duration(days: 1);
    for (var run = 0; run < 3; run++) {
      var sw = Stopwatch()..start();
      for (final l in links) {
        mapViaEngine(l, 'trojan');
      }
      sw.stop();
      if (sw.elapsed < bestLayer) bestLayer = sw.elapsed;

      sw = Stopwatch()..start();
      for (final l in links) {
        parseUri(l);
      }
      sw.stop();
      if (sw.elapsed < best) best = sw.elapsed;
    }


    print('§480 перф: 2000 ссылок — слой ${bestLayer.inMilliseconds} мс, '
        'воронка ${best.inMilliseconds} мс (лучший из трёх)');
  });
}
