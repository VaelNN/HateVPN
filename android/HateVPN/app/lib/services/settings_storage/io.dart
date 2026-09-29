part of '../settings_storage.dart';








Future<File> _file() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/${SettingsStorage._fileName}');
}

Future<File> _bakFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/${SettingsStorage._fileName}${SettingsStorage._bakSuffix}');
}




Future<File> _tmpFile() async {
  final dir = await getApplicationDocumentsDirectory();
  final seq = SettingsStorage._tmpSeq++;
  return File(
      '${dir.path}/${SettingsStorage._fileName}.$seq${SettingsStorage._tmpSuffix}');
}


const _orphanTmpPrefix = '${SettingsStorage._fileName}.';




Future<void> _sweepOrphanTmp() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name.startsWith(_orphanTmpPrefix) &&
          name.endsWith(SettingsStorage._tmpSuffix)) {
        try {
          await entity.delete();
        } catch (_) {

        }
      }
    }
  } catch (_) {

  }
}



const _v0BakSuffix = '.v0.bak';

Future<File> _v0BakFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/${SettingsStorage._fileName}$_v0BakSuffix');
}



Future<Map<String, dynamic>?> _readV0Backup() async {
  try {
    return (await _tryReadFile(await _v0BakFile()))?.doc;
  } catch (_) {
    return null;
  }
}





Future<Map<String, dynamic>?> _tryParseFile(File f) async =>
    (await _tryReadFile(f))?.doc;


typedef _SettingsFileRead = ({List<int> bytes, Map<String, dynamic> doc});



Future<_SettingsFileRead?> _tryReadFile(File f) async {
  if (!await f.exists()) return null;
  try {
    final bytes = await f.readAsBytes();
    if (bytes.isEmpty) return null;
    final parsed = jsonDecode(utf8.decode(bytes));
    if (parsed is Map<String, dynamic>) return (bytes: bytes, doc: parsed);
    return null;
  } catch (_) {
    return null;
  }
}



Future<Map<String, dynamic>>? _loadInFlight;












Future<Map<String, dynamic>> _load() {
  final cached = SettingsStorage._cache;
  if (cached != null) return Future.value(cached);
  return _loadInFlight ??=
      _loadFromDisk().whenComplete(() => _loadInFlight = null);
}

Future<Map<String, dynamic>> _loadFromDisk() async {

  if (SettingsStorage._pendingSave != null) await SettingsStorage._pendingSave;




  try {
    final main = await _file();
    final bak = await _bakFile();







    await _sweepOrphanTmp();




    if (!await main.exists()) {
      SettingsStorage._cache = _freshDoc();
      return SettingsStorage._cache!;
    }


    final mainRead = await _tryReadFile(main);
    if (mainRead != null) {
      SettingsStorage._cache =
          await _migrateOnLoad(mainRead, main: main, bak: bak);
      return SettingsStorage._cache!;
    }


    final bakRead = await _tryReadFile(bak);
    if (bakRead != null) {
      AppLog.I.warning(
        'SettingsStorage: main file corrupted, recovered from .bak '
        '(${main.path})',
      );





      SettingsStorage._cache =
          await _migrateOnLoad(bakRead, main: main, bak: bak);
      return SettingsStorage._cache!;
    }


    SettingsStorage._mainIsCorrupted = true;
    if (!SettingsStorage._corruptionLogged) {
      SettingsStorage._corruptionLogged = true;
      AppLog.I.error(
        'SettingsStorage: main file corrupted, no recoverable .bak. '
        'Settings reset to defaults; main file left on disk for diagnostics '
        '(${main.path})',
      );
    }
    SettingsStorage._cache = _freshDoc();
    return SettingsStorage._cache!;
  } catch (_) {



    SettingsStorage._cache = _freshDoc();
    return SettingsStorage._cache!;
  }
}


Map<String, dynamic> _freshDoc() =>
    {kStorageVersionKey: kStorageVersion};














Future<Map<String, dynamic>> _migrateOnLoad(
  _SettingsFileRead read, {
  required File main,
  required File bak,
}) async {
  final doc = read.doc;
  if (!storageDocNeedsMigration(doc)) {
    final version = storageDocVersion(doc);
    if (version != null && version > kStorageVersion) {
      AppLog.I.error(
        'SettingsStorage: storage_version $version is newer than this build '
        'knows ($kStorageVersion); the document is read as the current form, '
        'unknown top-level keys are kept',
      );
    }
    return doc;
  }

  final StorageMigrationResult result;
  try {
    result = migrateStorageDoc(
      doc,
      presetIdByDnsServerTag: await _presetIdsForMigration(),
      subscriptionBodies: await _subscriptionBodiesForMigration(doc),
      recordVars: await loadRecordVarDecls(),
    );
  } catch (e, st) {
    AppLog.I.error(
        'SettingsStorage: storage migration failed, the file is left as is: '
        '$e\n$st');
    return doc;
  }

  var configWasDirty = true;
  try {
    configWasDirty = await ConfigDirtyCheck.isDirty();
  } catch (_) {

  }

  try {
    await _writeV0BakOnce(read.bytes);
  } catch (e) {
    AppLog.I.error('SettingsStorage: $_v0BakSuffix copy before the storage '
        'migration failed: $e');
  }

  try {
    await _atomicSave(result.doc, main: main, bak: bak, tmp: await _tmpFile());
    if (!configWasDirty && !SettingsStorage.configDirty) {
      await ConfigDirtyCheck.touchConfig();
    }
  } catch (e) {
    AppLog.I.error('SettingsStorage: migrated storage not written, the next '
        'start migrates again: $e');
  }

  AppLog.I.info('SettingsStorage: storage migrated to storage_version '
      '${storageDocVersion(result.doc)}'
      '${result.summary.isEmpty ? '' : ' — ${result.summary}'}');
  if (result.warnings.isNotEmpty) {
    AppLog.I.warning(
        'SettingsStorage: storage migration losses: ${result.warnings.join('; ')}');
  }
  return result.doc;
}






Future<Map<String, String>> _subscriptionBodiesForMigration(
    Map<String, dynamic> doc) async {
  final lists = doc['server_lists'];
  if (lists is! List) return const {};
  final out = <String, String>{};
  for (final l in lists) {
    if (l is! Map || l['type'] != 'subscription') continue;
    final url = l['url'];
    if (url is! String || url.isEmpty || out.containsKey(url)) continue;
    final body = await HttpCache.loadBody(url);
    if (body != null && body.isNotEmpty) out[url] = body;
  }
  return out;
}




Future<Map<String, String>> _presetIdsForMigration() async {
  try {
    final template = await TemplateLoader.load();
    return presetIdsByDnsServerTag(template.selectableRules);
  } catch (e) {
    AppLog.I.warning('SettingsStorage: template not loaded for the storage '
        'migration ($e); preset DNS servers keep ref = tag');
    return const {};
  }
}



Future<void> _writeV0BakOnce(List<int> bytes) async {
  final copy = await _v0BakFile();
  if (await copy.exists()) return;
  final tmp = File(
      '${copy.path}.${SettingsStorage._tmpSeq++}${SettingsStorage._tmpSuffix}');
  await tmp.writeAsBytes(bytes, flush: true);
  await tmp.rename(copy.path);
}













Future<void> _save() async {





  final data = Map<String, dynamic>.from(SettingsStorage._cache ?? {});

  final main = await _file();
  final bak = await _bakFile();
  final tmp = await _tmpFile();

  SettingsStorage._pendingSave =
      _atomicSave(data, main: main, bak: bak, tmp: tmp);
  await SettingsStorage._pendingSave;
  SettingsStorage._pendingSave = null;





  if (!SettingsStorage.configDirty) {
    await ConfigDirtyCheck.touchConfig();
  }
}

Future<void> _atomicSave(
  Map<String, dynamic> data, {
  required File main,
  required File bak,
  required File tmp,
}) async {
  final encoded = const JsonEncoder.withIndent('  ').convert(data);




  if (await main.exists()) {
    final mainParsed = await _tryParseFile(main);
    if (mainParsed != null) {
      try {
        await main.copy(bak.path);
      } catch (_) {


      }
    }
  }




  await tmp.writeAsString(encoded, flush: true);


  await tmp.rename(main.path);




  SettingsStorage._mainIsCorrupted = false;
  SettingsStorage._corruptionLogged = false;
}
