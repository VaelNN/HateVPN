import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/dns_ref.dart';
import 'package:lxbox/services/config_dirty_check.dart';
import 'package:lxbox/services/platform_channels.dart';
import 'package:lxbox/services/settings_storage.dart';








void main() {
  late Directory tmp;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  String configPath() => '${tmp.path}/singbox_config.json';

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = await Directory.systemTemp.createTemp('lxbox_dirty_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory' ||
          call.method == 'getApplicationDocumentsPath') {
        return tmp.path;
      }
      return null;
    });
    SettingsStorage.resetCacheForTesting();
    ConfigDirtyCheck.resetForTesting();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    try {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    } on FileSystemException {

    }
  });

  group('§414 — конфиг живёт в native filesDir, не в Documents', () {



    late Directory filesDir;
    const vpnChannel = MethodChannel(PlatformChannels.methods);

    String nativeConfigPath() => '${filesDir.path}/singbox_config.json';

    setUp(() async {
      filesDir = await Directory.systemTemp.createTemp('lxbox_dirty_files_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(vpnChannel, (call) async {
        if (call.method == 'getFilesDir') return filesDir.path;
        return null;
      });
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(vpnChannel, null);
      try {
        if (filesDir.existsSync()) await filesDir.delete(recursive: true);
      } on FileSystemException {

      }
    });

    test('свежий конфиг в filesDir → isDirty=false', () async {
      await SettingsStorage.setNodeSort('latency', const []);
      final cfg = File(nativeConfigPath());
      await cfg.writeAsString('{}');
      await cfg.setLastModified(DateTime.now().add(const Duration(minutes: 1)));

      expect(await ConfigDirtyCheck.isDirty(), isFalse,
          reason: 'конфиг новее настроек — пересобирать нечего');
    });

    test('конфиг только в Documents (старое место) → не считается', () async {
      await SettingsStorage.setNodeSort('latency', const []);
      final stale = File(configPath());
      await stale.writeAsString('{}');
      await stale.setLastModified(DateTime.now().add(const Duration(minutes: 1)));

      expect(await ConfigDirtyCheck.isDirty(), isTrue,
          reason: 'в filesDir конфига нет — честно грязно');
    });

    test('touchConfig выравнивает mtime конфига в filesDir', () async {
      final cfg = File(nativeConfigPath());
      await cfg.writeAsString('{}');
      await cfg.setLastModified(DateTime(2020));


      await SettingsStorage.setNodeSort('latency', const []);

      expect(SettingsStorage.configDirty, isFalse);
      expect(cfg.lastModifiedSync().year, greaterThan(2020),
          reason: 'touch дотянулся до файла в filesDir');
      expect(await ConfigDirtyCheck.isDirty(), isFalse);
    });
  });

  group('§113 — авто-dirty на config-значимых сейверах', () {
    test('config-значимые сейверы поднимают configDirty', () async {
      expect(SettingsStorage.configDirty, isFalse);

      await SettingsStorage.saveRouteFinal('vpn-1');
      expect(SettingsStorage.configDirty, isTrue);

      SettingsStorage.configDirty = false;
      await SettingsStorage.saveEnabledGroups({'g1'});
      expect(SettingsStorage.configDirty, isTrue);

      SettingsStorage.configDirty = false;
      await SettingsStorage.saveDnsServers([
        const DnsServerInline(
            enabled: true, tag: 'local', body: {'type': 'udp', 'server': '1.1.1.1'}),
      ]);
      expect(SettingsStorage.configDirty, isTrue);

      SettingsStorage.configDirty = false;
      await SettingsStorage.setTunApps(
        const TunAppsConfig(mode: 'allow', packages: ['com.x']),
      );
      expect(SettingsStorage.configDirty, isTrue);
    });

    test('не-config сейверы (sort/ping/timestamp) НЕ поднимают флаг',
        () async {
      await SettingsStorage.setNodeSort('latency', const ['a', 'b']);
      expect(SettingsStorage.configDirty, isFalse);

      await SettingsStorage.savePingOptions({'url': 'https://x'});
      expect(SettingsStorage.configDirty, isFalse);

      await SettingsStorage.setLastGlobalUpdate(
          DateTime.utc(2026, 1, 1));
      expect(SettingsStorage.configDirty, isFalse);
    });

    test('setVar: config-var → dirty, прочий var → нет', () async {
      await SettingsStorage.setVar('log_level', 'debug');
      expect(SettingsStorage.configDirty, isTrue);

      SettingsStorage.configDirty = false;
      await SettingsStorage.setVar('sort_mode', 'latency');
      expect(SettingsStorage.configDirty, isFalse);


      await SettingsStorage.setVar('clash_secret', 'abc');
      expect(SettingsStorage.configDirty, isFalse);
    });
  });

  group('§113 — touch конфига при записи настроек', () {
    test('!dirty при _save → config-файл выровнен (isDirty=false)', () async {


      final cfg = File(configPath());
      await cfg.writeAsString('{}');
      await cfg.setLastModified(DateTime(2020));


      await SettingsStorage.setNodeSort('latency', const []);

      expect(SettingsStorage.configDirty, isFalse);
      expect(await ConfigDirtyCheck.isDirty(), isFalse,
          reason: 'touch выровнял mtime конфига → ложного dirty нет');
    });

    test('dirty при _save → config НЕ тронут (честно грязно)', () async {
      final cfg = File(configPath());
      await cfg.writeAsString('{}');
      await cfg.setLastModified(DateTime(2020));
      final before = cfg.lastModifiedSync();



      await SettingsStorage.saveRouteFinal('vpn-1');

      expect(SettingsStorage.configDirty, isTrue);
      expect(cfg.lastModifiedSync(), before,
          reason: 'dirty=true → config не тронут');
      expect(await ConfigDirtyCheck.isDirty(), isTrue,
          reason: 'настройки новее конфига и флаг грязный → пересобрать');
    });

    test('репро-сценарий: правка → снятие флага пересборкой → flush → чисто',
        () async {
      final cfg = File(configPath());
      await cfg.writeAsString('{}');
      await cfg.setLastModified(DateTime(2020));


      await SettingsStorage.setTunApps(
        const TunAppsConfig(mode: 'allow', packages: ['com.x']),
        flush: false,
      );
      expect(SettingsStorage.configDirty, isTrue);



      await cfg.writeAsString('{"rebuilt":true}');
      SettingsStorage.configDirty = false;


      await SettingsStorage.flushToDisk();


      expect(await ConfigDirtyCheck.isDirty(), isFalse,
          reason: 'после чистой правки kill не должен дать ложный баннер');
    });
  });
}
