import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app_log.dart';
import '../automation/event_emitter.dart';
import '../l10n/locale_controller.dart';
import '../settings_storage.dart';
import '../template_loader.dart';
import 'workspace_store.dart';














class WorkspaceController extends ChangeNotifier {
  WorkspaceController._();

  static final WorkspaceController I = WorkspaceController._();

  WorkspaceStore get _store => WorkspaceStore.I;

  WorkspaceManifest _manifest = WorkspaceManifest.initial();



  WorkspaceManifest get manifest => _manifest;
  String get current => _manifest.current;
  List<WorkspaceSlot> get slots => _manifest.slots;

  int _generation = 0;



  int get generation => _generation;

  bool _busy = false;
  bool get busy => _busy;

  String? _loadingName;


  String? get loadingName => _loadingName;

  bool _pendingAutoConnect = false;



  bool takePendingAutoConnect() {
    final v = _pendingAutoConnect;
    _pendingAutoConnect = false;
    return v;
  }

  Future<void> refresh() async {
    _manifest = await _store.readManifest();
    notifyListeners();
  }



  Future<WorkspaceLoadOutcome> load(
    String name, {
    required Future<bool> Function() stopVpn,
  }) async {
    if (_busy) return WorkspaceLoadOutcome.busy;
    final target = name.trim();
    _busy = true;
    _loadingName = target;
    notifyListeners();
    try {
      final before = await _store.readManifest();
      if (before.current == target) return WorkspaceLoadOutcome.alreadyCurrent;
      final wasUp = await stopVpn();
      await SettingsStorage.flushToDisk();
      final changed = await _store.load(target);
      if (!changed) return WorkspaceLoadOutcome.alreadyCurrent;





      SettingsStorage.markConfigDirty();
      await _reloadStateFromDisk();
      _manifest = await _store.readManifest();
      _pendingAutoConnect = wasUp;
      _generation++;
      return WorkspaceLoadOutcome.loaded;
    } finally {
      _busy = false;
      _loadingName = null;


      notifyListeners();
    }
  }


  Future<void> saveAs(String name) async {
    await SettingsStorage.flushToDisk();
    await _store.saveAs(name);
    await refresh();
  }

  Future<void> rename(String oldName, String newName) async {
    await _store.rename(oldName, newName);
    await refresh();
  }

  Future<void> delete(String name) async {
    await _store.delete(name);
    await refresh();
  }




  static Future<void> _reloadStateFromDisk() async {


    SettingsStorage.clearCache();
    await _step('native prefs', SettingsStorage.bootstrapAndSyncNativePrefs);
    await _step('locale', LocaleController.I.reloadFromStorage);
    await _step('directions migration', () async {
      final t = await TemplateLoader.load();
      await SettingsStorage.migrateDirectionsIfNeeded(
        t.groupTemplates,
        varDefaults: {for (final v in t.vars) v.name: v.defaultValue},
      );
    });
    await _step('automation gates', AutomationEventEmitter.I.reload);
  }

  static Future<void> _step(String what, Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      AppLog.I.error('workspaces: reload step "$what" failed: $e');
    }
  }
}

enum WorkspaceLoadOutcome { loaded, alreadyCurrent, busy }
