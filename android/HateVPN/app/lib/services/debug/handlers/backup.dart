import 'package:package_info_plus/package_info_plus.dart';

import '../../l10n/locale_controller.dart';
import '../../record_vars.dart';
import '../../settings_storage.dart';
import '../../storage_migration/migrate_storage.dart';
import '../../template_loader.dart';
import '../context.dart';
import '../contract/errors.dart';
import '../transport/request.dart';
import '../transport/response.dart';












Future<DebugResponse> backupHandler(DebugRequest req, DebugContext ctx) async {
  return switch ('${req.method} ${req.path}') {
    'GET /backup/export' => _export(req),
    'POST /backup/import' => _import(req, ctx),
    _ => throw NotFound('backup: ${req.method} ${req.path}'),
  };
}

const _allParts = {'storage', 'vpn_settings'};









Future<DebugResponse> _export(DebugRequest req) async {
  final from = req.query['from'];
  if (from != null && from != 'v0_bak') {
    throw BadRequest('from must be "v0_bak", got "$from"');
  }
  final raw = (req.query['include'] ?? 'storage,vpn_settings');
  final include = raw
      .split(',')
      .map((s) => s.trim().toLowerCase())
      .where(_allParts.contains)
      .toSet();
  final out = <String, dynamic>{
    'app': 'lxbox',
    'kind': 'backup',
    'created_at': DateTime.now().toUtc().toIso8601String(),
  };
  try {
    final info = await PackageInfo.fromPlatform();
    out['source_app_version'] = '${info.version}+${info.buildNumber}';
  } catch (_) {}

  if (include.contains('storage')) {
    if (from == 'v0_bak') {
      final v0 = await SettingsStorage.exportV0Backup();
      if (v0 == null) {
        throw const NotFound('backup: no lxbox_settings.json.v0.bak on this '
            'device (storage was never migrated from the 2.23.2 form)');
      }
      out['storage'] = v0;
    } else {
      out['storage'] = await SettingsStorage.exportRaw();
    }
  }
  if (include.contains('vpn_settings')) {

    out['vpn_settings'] = await SettingsStorage.exportNativePrefsBackup();
  }
  return JsonResponse(out, pretty: true);
}










Future<DebugResponse> _import(DebugRequest req, DebugContext ctx) async {
  final body = req.jsonBodyAsMap();
  final merge = req.qBool('merge');
  final rebuild = req.qBool('rebuild');
  final applied = <String, dynamic>{};

  final storage = body['storage'];
  if (storage is Map<String, dynamic>) {


    final template = await TemplateLoader.load();
    final legacy = storageDocNeedsMigration(storage);
    final migration = migrateStorageDoc(
      storage,
      presetIdByDnsServerTag: legacy
          ? presetIdsByDnsServerTag(template.selectableRules)
          : const {},

      subscriptionBodies: legacy
          ? await SettingsStorage.subscriptionBodiesForMigration(storage)
          : const {},

      recordVars: legacy
          ? RecordVarDecls.fromTemplate(template)
          : RecordVarDecls.none,
    );
    applied['migrated'] = migration.migrated;
    if (migration.migrated || migration.warnings.isNotEmpty) {
      applied['migration'] = migration.toReportJson();
    }


    final dropped =
        await SettingsStorage.replaceRaw(migration.doc, merge: merge);
    applied['storage_keys'] = storage.length;
    if (dropped.isNotEmpty) applied['dropped_keys'] = dropped;


    await LocaleController.I.reloadFromStorage();




    await SettingsStorage.migrateDirectionsIfNeeded(
      template.groupTemplates,
      varDefaults: {
        for (final v in template.vars) v.name: v.defaultValue,
      },
    );
  } else if (storage != null) {
    throw const BadRequest('storage must be a JSON object');
  }

  final vpn = body['vpn_settings'];
  if (vpn is Map<String, dynamic>) {

    applied['vpn_settings'] = await SettingsStorage.applyNativePrefsBackup(vpn);
  } else if (vpn != null) {
    throw const BadRequest('vpn_settings must be a JSON object');
  }

  if (rebuild) {
    final sub = ctx.sub;
    final home = ctx.home;
    if (sub != null && home != null) {
      final json = await sub.generateConfig();
      if (json != null) {
        await home.saveParsedConfig(json);
        applied['rebuilt'] = true;
      } else {
        applied['rebuilt'] = false;
        applied['rebuild_error'] = sub.lastError?.renderEn() ?? '';
      }
    }
  }

  return JsonResponse({'applied': applied}, pretty: true);
}
