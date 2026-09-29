import 'package:flutter_test/flutter_test.dart';

import '../parser/engine_test_setup.dart';
import 'golden_harness.dart';














void main() {


  setUpAll(loadEngineSections);

  for (final name in kStorageFixtures) {
    test('$name: config.json совпадает с эталоном', () async {
      final box = await StorageSandbox.create();
      addTearDown(box.dispose);
      await box.seed(name);

      final first = await buildGoldenConfig(box);
      final second = await buildGoldenConfig(box);
      expect(second.configJson, first.configJson,
          reason: 'две сборки одного хранения разошлись:\n'
              '${jsonDiff(first.config, second.config).join('\n')}');
      expect(second.warnings, first.warnings);

      expectGolden('$name.config.json', first.configJson);
      expectGolden('$name.config_warnings.json', prettyJson(first.warnings));
    });
  }
}
