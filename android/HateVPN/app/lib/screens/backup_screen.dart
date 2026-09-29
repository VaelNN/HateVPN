import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/backup_service.dart';
import '../services/dns/dns_backup.dart';
import '../services/lx_backup.dart';
import '../services/lx_backup_import.dart';
import '../services/record_vars.dart';
import '../services/warp/warp_backup.dart';
import '../services/settings_storage.dart';
import '../services/error_format.dart';
import '../services/l10n/locale_controller.dart';
import '../services/ui_helpers.dart';
import '../vpn/box_vpn_client.dart';
import '../widgets/export_action_sheet.dart';
import 'backup_screen/export_card.dart';
import 'backup_screen/import_card.dart';
import 'backup_screen/import_preview_dialog.dart';
import 'backup_screen/lx_transfer_card.dart';
import '../services/utf8_decode.dart';
import '../services/file_export.dart';
import '../services/file_import.dart';
import '../services/url_launcher.dart';
import '../widgets/safe_bottom.dart';




class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> with SnackHelper {
  final _service = const BackupService();


  bool _expServerLists = true;
  bool _expRouting = true;
  bool _expAppSettings = true;
  bool _expVpnSettings = true;
  bool _expDebugConfig = false;

  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(getLocalText.s("Backup & restore"))),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8).withSafeBottom(context),
        children: [
          ExportCard(
            serverLists: _expServerLists,
            routing: _expRouting,
            appSettings: _expAppSettings,
            vpnSettings: _expVpnSettings,
            debugConfig: _expDebugConfig,
            busy: _busy,
            onChange: (cat, on) => setState(() {
              switch (cat) {
                case BackupCategory.serverLists:
                  _expServerLists = on;
                case BackupCategory.routing:
                  _expRouting = on;
                case BackupCategory.appSettings:
                  _expAppSettings = on;
                case BackupCategory.vpnSettings:
                  _expVpnSettings = on;
                case BackupCategory.debugConfig:
                  _expDebugConfig = on;
              }
            }),
            onExport: _onExport,
          ),
          const SizedBox(height: 8),
          ImportCard(
            busy: _busy,
            onImport: _onImport,
          ),
          const SizedBox(height: 8),



          LxTransferCard(
            busy: _busy,
            onExport: _onLxExport,
            onImport: _onLxImport,
          ),
        ],
      ),
    );
  }

  Set<BackupCategory> _exportInclude() {
    return {
      if (_expServerLists) BackupCategory.serverLists,
      if (_expRouting) BackupCategory.routing,
      if (_expAppSettings) BackupCategory.appSettings,
      if (_expVpnSettings) BackupCategory.vpnSettings,
      if (_expDebugConfig) BackupCategory.debugConfig,
    };
  }

  Future<void> _onExport() async {
    final include = _exportInclude();
    if (include.isEmpty) {
      showSnack(getLocalText.s("Nothing to export — pick at least one category."));
      return;
    }
    setState(() => _busy = true);
    try {



      final availability = await Future.wait([
        UrlLauncher.hasRealFilePicker(),
        UrlLauncher.canSaveToDownloads(),
      ]);
      if (!mounted) return;
      final action = await showExportActionSheet(
        context,
        canSaveToFile: availability[0],
        canSaveToDownloads: availability[1],
      );
      if (action == null) return;

      final json = await _service.buildExport(include: include);
      final filename = await BackupService.suggestedFilename();


      final bytes = utf8.encode(json).length;

      final SaveOutcome outcome;
      switch (action) {
        case ExportAction.saveToFile:
          outcome = await saveFileSafely(fileName: filename, content: json);
        case ExportAction.saveToDownloads:
          outcome =
              await saveToDownloadsSafely(fileName: filename, content: json);
        case ExportAction.share:


          final tmpDir = await getTemporaryDirectory();
          final path = '${tmpDir.path}/$filename';
          await File(path).writeAsString(json);
          await SharePlus.instance.share(ShareParams(
            files: [XFile(path, mimeType: 'application/json', name: filename)],
            subject: 'LxBox backup',
          ));
          if (!mounted) return;
          showSnack(getLocalText.s("Backup exported (%d bytes)", bytes));
          return;
      }

      if (!mounted) return;
      final problem = saveProblemText(outcome);
      if (problem != null) {
        showSnack(problem);
        return;
      }
      switch (outcome) {
        case SavedToFile(:final name):
          showSnack(getLocalText.s("Saved as %s (%d bytes)", name, bytes));
        case SavedToDownloads(:final name):
          showSnack(
              getLocalText.s("Saved to Downloads: %s (%d bytes)", name, bytes));
        case SaveCancelled():
          break;
        case SaveNoTarget() || SaveFailed():
          break;
      }
    } catch (e) {
      if (!mounted) return;
      showSnack(getLocalText.s("Export failed: %s", formatUserError(e).render()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onImport() async {
    setState(() => _busy = true);
    try {

      final outcome = await pickFileSafely(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (outcome is! PickedFiles) {
        final problem = pickProblemText(outcome);
        if (problem != null && mounted) showSnack(problem);
        return;
      }
      final file = outcome.single;
      final raw = utf8DecodeOrNull(file.bytes);
      if (raw == null) {
        if (!mounted) return;
        showSnack(getLocalText.s("Could not read file."));
        return;
      }

      final BackupContents contents;
      try {
        contents = await _service.parseImport(raw);
      } on FormatException catch (e) {
        if (!mounted) return;
        _showError(getLocalText.s("Invalid backup"), e.message);
        return;
      }

      if (!mounted) return;
      final result = await showImportPreview(context, contents);
      if (result == null) return;

      final apply = await _service.applyImport(
        contents,
        merge: result.merge,
        include: result.include,
      );


      await LocaleController.I.reloadFromStorage();
      if (!mounted) return;
      final summary = StringBuffer('Imported');
      final parts = <String>[];
      if (apply.serverListsApplied > 0) {
        parts.add('${apply.serverListsApplied} server lists');
      }
      if (apply.routingApplied > 0) {
        parts.add('routing (${apply.routingApplied} rules)');
      }
      if (apply.appSettingsApplied > 0) {
        parts.add('${apply.appSettingsApplied} app settings');
      }
      if (apply.debugConfigApplied > 0) {
        parts.add('debug config');
      }
      if (apply.vpnSettingsApplied > 0) {
        parts.add('${apply.vpnSettingsApplied} VPN settings');
      }
      if (parts.isEmpty) {
        summary.write(' nothing (all categories deselected)');
      } else {
        summary.write(': ${parts.join(', ')}');
      }
      if (apply.hasErrors) {
        summary.write(' (${apply.errors.length} errors)');
      }

      if (apply.droppedKeys.isNotEmpty) {
        summary.write(' · ${apply.droppedKeys.length} unknown keys skipped');
      }




      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(summary.toString()),
            duration: const Duration(seconds: 6),
            action: parts.isEmpty
                ? null
                : SnackBarAction(
                    label: getLocalText.s("Restart now"),
                    onPressed: () =>
                        unawaited(BoxVpnClient().quitApp()),
                  ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      showSnack(getLocalText.s("Import failed: %s", formatUserError(e).render()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }









  Future<void> _onLxExport() async {
    setState(() => _busy = true);
    try {
      final availability = await Future.wait([
        UrlLauncher.hasRealFilePicker(),
        UrlLauncher.canSaveToDownloads(),
      ]);
      if (!mounted) return;
      final action = await showExportActionSheet(
        context,
        canSaveToFile: availability[0],
        canSaveToDownloads: availability[1],
      );
      if (action == null) return;

      final lists = await SettingsStorage.getServerLists();
      final rules = await SettingsStorage.getCustomRules();
      final vars = await SettingsStorage.getAllVars();


      final directions = await SettingsStorage.getDirections();


      final chains = await SettingsStorage.getChains();
      final sourceKeys = await SettingsStorage.getSourceKeys();


      final routeFinal = await SettingsStorage.getRouteFinal();



      final exportWarnings = <LxBackupWarning>[];


      final recordVars = await loadRecordVarDecls();


      final dns = dnsToBackup(
        servers: await SettingsStorage.getDnsServers(),
        rules: await SettingsStorage.getDnsRulesList(),
        dnsFinal: vars['dns_final'] ?? '',
        strategy: vars['dns_strategy'] ?? '',
        defaultDomainResolver: vars['dns_default_domain_resolver'] ?? '',
        warnings: exportWarnings,
        recordVars: recordVars,
      );

      final warpAccount = await SettingsStorage.getWarpAccount();
      final masqueAccount = await SettingsStorage.getMasqueAccount();
      final warp = <Map<String, dynamic>>[
        if (warpAccount != null) warpAccountToBackup(warpAccount),
        if (masqueAccount != null) masqueAccountToBackup(masqueAccount),
      ];



      final directionPing = lxDirectionPingFromStorage(
        await SettingsStorage.getPingOptions(),
      );
      final built = await buildLxBackup(
        lists: lists,
        rules: rules,
        vars: vars,
        directions: directions,
        directionPing: directionPing,
        chains: chains,
        sourceKeys: sourceKeys,
        routeFinal: routeFinal,
        dns: dns,
        warp: warp,
        recordVars: recordVars,
      );
      final json = built.json;
      exportWarnings.addAll(built.warnings);
      const filename = 'lx-backup.json';


      final bytes = utf8.encode(json).length;

      final SaveOutcome outcome;
      switch (action) {
        case ExportAction.saveToFile:
          outcome = await saveFileSafely(fileName: filename, content: json);
        case ExportAction.saveToDownloads:
          outcome =
              await saveToDownloadsSafely(fileName: filename, content: json);
        case ExportAction.share:
          final tmpDir = await getTemporaryDirectory();
          final path = '${tmpDir.path}/$filename';
          await File(path).writeAsString(json);
          await SharePlus.instance.share(ShareParams(
            files: [XFile(path, mimeType: 'application/json', name: filename)],
            subject: 'LX Backup',
          ));
          if (!mounted) return;
          showSnack(getLocalText.s("Backup exported (%d bytes)", bytes));
          _showExportLosses(exportWarnings);
          return;
      }

      if (!mounted) return;
      final problem = saveProblemText(outcome);
      if (problem != null) {
        showSnack(problem);
        return;
      }
      switch (outcome) {
        case SavedToFile(:final name):
          showSnack(getLocalText.s("Saved as %s (%d bytes)", name, bytes));
          _showExportLosses(exportWarnings);
        case SavedToDownloads(:final name):
          showSnack(
              getLocalText.s("Saved to Downloads: %s (%d bytes)", name, bytes));
          _showExportLosses(exportWarnings);
        case SaveCancelled():
          break;
        case SaveNoTarget() || SaveFailed():
          break;
      }
    } catch (e) {
      if (!mounted) return;
      showSnack(getLocalText.s("Export failed: %s", formatUserError(e).render()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }





  Future<void> _onLxImport() async {
    setState(() => _busy = true);
    try {
      final outcome = await pickFileSafely(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (outcome is! PickedFiles) {
        final problem = pickProblemText(outcome);
        if (problem != null && mounted) showSnack(problem);
        return;
      }
      final file = outcome.single;
      final raw = utf8DecodeOrNull(file.bytes);
      if (raw == null) {
        if (!mounted) return;
        showSnack(getLocalText.s("Could not read file."));
        return;
      }



      const importer = LxBackupImportService();
      final LxImportPlan plan;
      try {
        plan = await importer.prepare(raw);
      } on FormatException catch (e) {
        if (!mounted) return;
        _showError(getLocalText.s("Invalid backup"), e.message);
        return;
      }

      if (!mounted) return;
      final confirmed = await _confirmLxImport(plan.file);
      if (confirmed != true) return;

      final result = await importer.apply(plan);
      if (!mounted) return;

      final parsed = result.file;
      final appliedDirections = result.appliedDirections;
      final counts = result.appliedSettings;
      final skipped = parsed.warnings.length;











      final String message;
      if (skipped > 0) {
        message = getLocalText.s("Imported %d rule(s), %d items not applied",
            parsed.rules.length, skipped);
      } else if (appliedDirections > 0 && counts > 0) {
        message = getLocalText.s(
            "Imported %1\$d rules, %2\$d directions and %3\$d settings",
            parsed.rules.length,
            appliedDirections,
            counts);
      } else if (appliedDirections > 0) {
        message = getLocalText.s("Imported %1\$d rules and %2\$d directions",
            parsed.rules.length, appliedDirections);
      } else if (counts > 0) {
        message = getLocalText.s("Imported %1\$d rules and %2\$d settings",
            parsed.rules.length, counts);
      } else {
        message = getLocalText.plural("Imported %d rules", parsed.rules.length);
      }






      showSnack(result.appliedChains > 0
          ? '$message; ${getLocalText.s("chains: %d", result.appliedChains)}'
          : message);
    } catch (e) {
      if (!mounted) return;
      showSnack(getLocalText.s("Import failed: %s", formatUserError(e).render()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  Future<bool?> _confirmLxImport(LxBackupFile parsed) {
    final lines = <String>[
      getLocalText.s("From %s %s", parsed.exportedByApp, parsed.exportedByVersion),



      if (parsed.directions.isNotEmpty)
        getLocalText.s("Directions: %d", parsed.directions.length),


      if (parsed.chains.isNotEmpty)
        getLocalText.s("Chains: %d", parsed.chains.length),
      getLocalText.s("Rules: %d", parsed.rules.length),
      getLocalText.s("Subscriptions: %d", parsed.subscriptions.length),


      if (parsed.servers.isNotEmpty)
        getLocalText.s("Servers: %d", parsed.servers.length),
      getLocalText.s("Variables: %d", parsed.vars.length),



      if (parsed.dns != null && !parsed.dns!.isEmpty)
        getLocalText.s("DNS entries: %d",
            parsed.dns!.servers.length + parsed.dns!.rules.length),
      if (parsed.warp.isNotEmpty)
        getLocalText.s("WARP accounts: %d", parsed.warp.length),
    ];
    if (parsed.warnings.isNotEmpty) {
      lines.add('');
      lines.add(getLocalText.s("Not applied as-is:"));
      for (final w in parsed.warnings.take(8)) {
        lines.add('• ${w.detail}');
      }
      if (parsed.warnings.length > 8) {
        lines.add('… +${parsed.warnings.length - 8}');
      }
    }
    lines.add('');
    lines.add(getLocalText.s("Importing replaces the current rules."));

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(getLocalText.s("Import backup")),
        content: SingleChildScrollView(child: Text(lines.join('\n'))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(getLocalText.s("Cancel")),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(getLocalText.s("Import")),
          ),
        ],
      ),
    );
  }




  void _showExportLosses(List<LxBackupWarning> warnings) {
    if (warnings.isEmpty || !mounted) return;
    final lines = <String>[
      getLocalText.s("These settings have no place in the shared format:"),
      '',
      for (final w in warnings.take(12)) '• ${w.detail}',
      if (warnings.length > 12) '… +${warnings.length - 12}',
    ];
    _showError(getLocalText.s("Not included in the file"), lines.join('\n'));
  }

  void _showError(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(getLocalText.s("OK")))
        ],
      ),
    );
  }
}
