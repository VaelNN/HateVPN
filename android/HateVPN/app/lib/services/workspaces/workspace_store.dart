import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

import '../app_log.dart';
import '../settings_storage_keys.dart' show kStorageVersionKey;
import '../tailscale_state/state_store.dart';






















class WorkspaceStore {
  WorkspaceStore._();

  static final WorkspaceStore I = WorkspaceStore._();

  static const manifestFileName = 'workspaces.json';
  static const slotsDirName = 'workspaces';
  static const defaultName = 'Default';
  static const manifestVersion = 1;
  static const nameMaxLength = 64;















  static const List<SlotEntry> kSlotEntries = [
    SlotEntry(SlotRoot.documents, 'lxbox_settings.json', isDir: false),
    SlotEntry(SlotRoot.documents, 'rule_sets', isDir: true),
    SlotEntry(SlotRoot.support, 'sub_cache', isDir: true),
  ];


  static const _settingsFileName = 'lxbox_settings.json';
  static const _settingsBakName = 'lxbox_settings.json.bak';
  static const _v0BakSuffix = '.v0.bak';
  static const _tmpSuffix = '.tmp';

  Future<void> _lock = Future<void>.value();
  int _tmpSeq = 0;







  static WorkspaceNameError? validateName(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return WorkspaceNameError.empty;
    if (name.length > nameMaxLength) return WorkspaceNameError.tooLong;
    if (name == '.' || name == '..' || name.startsWith('.')) {
      return WorkspaceNameError.leadingDot;
    }
    for (final cu in name.codeUnits) {
      if (cu < 0x20 || cu == 0x2F   || cu == 0x5C   || cu == 0x7F) {
        return WorkspaceNameError.forbiddenChars;
      }
    }
    return null;
  }

  static String _requireValid(String raw) {
    final err = validateName(raw);
    if (err != null) {
      throw WorkspaceError(WorkspaceErrorKind.invalidName, raw, nameError: err);
    }
    return raw.trim();
  }







  Future<WorkspaceManifest> readManifest() async {
    final f = await _manifestFile();
    if (!await f.exists()) return WorkspaceManifest.initial();
    try {
      final raw = jsonDecode(await f.readAsString());
      if (raw is Map<String, dynamic>) return WorkspaceManifest.fromJson(raw);
    } catch (e) {
      AppLog.I.error('workspaces: manifest unreadable, treating as absent: $e');
    }
    return WorkspaceManifest.initial();
  }

  Future<bool> manifestExists() async => (await _manifestFile()).exists();

  Future<List<WorkspaceSlot>> listSlots() async =>
      (await readManifest()).slots;

  Future<String> currentName() async => (await readManifest()).current;

  Future<void> _writeManifest(WorkspaceManifest m) async {
    final f = await _manifestFile();
    await _writeStringAtomic(
        f, const JsonEncoder.withIndent('  ').convert(m.toJson()));
  }







  Future<void> saveAs(String rawName) => _locked(() async {
        final name = _requireValid(rawName);
        var m = await readManifest();
        await _copySceneToSlot(name);
        final next =
            m.withSlotSaved(name, DateTime.now()).copyWith(current: name);


        await _tailscale('save as', (root) => TailscaleStateStore.I.forkSlot(
            root: root, from: m.current, to: name, slotNames: next.names));
        m = next;
        await _writeManifest(m);
        AppLog.I.info('workspaces: saved scene as "$name"');
      });









  Future<bool> load(String rawName) => _locked(() async {
        final name = rawName.trim();
        var m = await readManifest();
        if (name == m.current) return false;
        if (!await _slotExists(name)) {
          throw WorkspaceError(WorkspaceErrorKind.notFound, name);
        }

        m = m.copyWith(pending: WorkspacePending.load(name));
        await _writeManifest(m);
        await _performLoad(m);
        return true;
      });




  Future<bool> recover() => _locked(() async {
        final f = await _manifestFile();
        if (!await f.exists()) return false;
        final m = await readManifest();
        final p = m.pending;
        if (p == null) return false;
        if (p.op == WorkspacePending.opLoad && await _slotExists(p.target)) {
          AppLog.I.warning(
              'workspaces: unfinished load of "${p.target}" — redoing');
          await _performLoad(m);
          return true;
        }


        AppLog.I.warning(
            'workspaces: dropping stale pending ${p.op} → "${p.target}"');
        await _writeManifest(m.copyWith(clearPending: true));
        return false;
      });




  Future<void> _performLoad(WorkspaceManifest m) async {
    final target = m.pending!.target;
    final now = DateTime.now();
    await _copySceneToSlot(m.current);
    var next = m.withSlotSaved(m.current, now);
    await _keepLegacySettingsCopy(target);
    await _copySlotToScene(target);
    await _touchSettings();
    next = next.copyWith(current: target, clearPending: true);
    await _writeManifest(next);
    AppLog.I.info('workspaces: loaded "$target" (previous "${m.current}" saved)');
  }


  Future<void> rename(String rawOld, String rawNew) => _locked(() async {
        final oldName = rawOld.trim();
        final newName = _requireValid(rawNew);
        if (oldName == newName) return;
        var m = await readManifest();
        if (!m.hasSlot(oldName)) {
          throw WorkspaceError(WorkspaceErrorKind.notFound, oldName);
        }
        if (m.hasSlot(newName) || await _slotExists(newName)) {
          throw WorkspaceError(WorkspaceErrorKind.exists, newName);
        }
        final dir = await _slotDir(oldName);
        if (await dir.exists()) {
          await dir.rename((await _slotDir(newName)).path);
        }
        m = m.withSlotRenamed(oldName, newName);
        if (m.current == oldName) m = m.copyWith(current: newName);
        await _tailscale('rename', (root) => TailscaleStateStore.I
            .renameSlot(root: root, from: oldName, to: newName));
        await _writeManifest(m);
      });


  Future<void> delete(String rawName) => _locked(() async {
        final name = rawName.trim();
        final m = await readManifest();
        if (name == m.current) {
          throw WorkspaceError(WorkspaceErrorKind.isCurrent, name);
        }
        if (!m.hasSlot(name)) {
          throw WorkspaceError(WorkspaceErrorKind.notFound, name);
        }
        final dir = await _slotDir(name);
        if (await dir.exists()) await dir.delete(recursive: true);
        final next = m.withSlotRemoved(name);
        await _writeManifest(next);

        await _tailscale('delete', (root) => TailscaleStateStore.I
            .dropSlot(root: root, name: name, slotNames: next.names));
      });



  Future<void> _tailscale(
      String what, Future<void> Function(String root) op) async {
    try {
      await op((await _support()).path);
    } catch (e) {
      AppLog.I.warning('workspaces: tailscale state on $what failed: $e');
    }
  }


  Future<int> slotSizeBytes(String name) async {
    final dir = await _slotDir(name.trim());
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) total += await e.length();
    }
    return total;
  }







  Future<void> _copySceneToSlot(String name) async {
    final slot = await _slotDir(name);
    await slot.create(recursive: true);
    for (final e in kSlotEntries) {
      final src = await _scenePath(e);
      final dst = '${slot.path}/${e.name}';
      if (e.isDir) {
        await _replaceDir(Directory(src), Directory(dst));
      } else {
        await _replaceFile(File(src), File(dst));
      }
    }
  }




  Future<void> _copySlotToScene(String name) async {
    final slot = await _slotDir(name);
    for (final e in kSlotEntries) {
      final src = '${slot.path}/${e.name}';
      final dst = await _scenePath(e);
      if (e.isDir) {
        await _replaceDir(Directory(src), Directory(dst));
      } else {
        await _replaceFile(File(src), File(dst));
      }
    }
    final bak = File('${(await _docs()).path}/$_settingsBakName');
    if (await bak.exists()) await bak.delete();
  }









  Future<void> _keepLegacySettingsCopy(String name) async {
    try {
      final slot = await _slotDir(name);
      final src = File('${slot.path}/$_settingsFileName');
      if (!await src.exists()) return;
      final copy = File('${slot.path}/$_settingsFileName$_v0BakSuffix');
      if (await copy.exists()) return;
      final bytes = await src.readAsBytes();
      final doc = jsonDecode(utf8.decode(bytes));
      if (doc is! Map || doc.containsKey(kStorageVersionKey)) return;
      final tmp = File('${copy.path}.${_tmpSeq++}$_tmpSuffix');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(copy.path);
    } catch (e) {
      AppLog.I.warning('workspaces: legacy settings copy of "$name" failed: $e');
    }
  }




  Future<void> _touchSettings() async {
    final f = File('${(await _docs()).path}/$_settingsFileName');
    if (await f.exists()) await f.setLastModified(DateTime.now());
  }



  Future<void> _replaceFile(File src, File dst) async {
    if (!await src.exists()) {
      if (await dst.exists()) await dst.delete();
      return;
    }
    await dst.parent.create(recursive: true);
    final tmp = File('${dst.path}.${_tmpSeq++}$_tmpSuffix');
    await tmp.writeAsBytes(await src.readAsBytes(), flush: true);
    await tmp.rename(dst.path);
  }




  Future<void> _replaceDir(Directory src, Directory dst) async {
    if (await dst.exists()) await dst.delete(recursive: true);
    if (!await src.exists()) return;
    await dst.create(recursive: true);
    await for (final e in src.list(recursive: true, followLinks: false)) {
      final rel = e.path.substring(src.path.length + 1);
      if (e is Directory) {
        await Directory('${dst.path}/$rel').create(recursive: true);
      } else if (e is File) {
        if (rel.endsWith(_tmpSuffix)) continue;
        final out = File('${dst.path}/$rel');
        await out.parent.create(recursive: true);
        await out.writeAsBytes(await e.readAsBytes(), flush: true);
      }
    }
  }

  Future<void> _writeStringAtomic(File f, String content) async {
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.${_tmpSeq++}$_tmpSuffix');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(f.path);
  }





  Future<Directory> _docs() => getApplicationDocumentsDirectory();
  Future<Directory> _support() => getApplicationSupportDirectory();

  Future<File> _manifestFile() async =>
      File('${(await _docs()).path}/$manifestFileName');

  Future<Directory> _slotDir(String name) async =>
      Directory('${(await _docs()).path}/$slotsDirName/$name');

  Future<bool> _slotExists(String name) async => (await _slotDir(name)).exists();

  Future<String> _scenePath(SlotEntry e) async {
    final root = switch (e.root) {
      SlotRoot.documents => await _docs(),
      SlotRoot.support => await _support(),
    };
    return '${root.path}/${e.name}';
  }


  @visibleForTesting
  Future<Directory> slotDirForTesting(String name) => _slotDir(name);

  Future<T> _locked<T>(Future<T> Function() body) {
    final prev = _lock;
    final completer = Completer<void>();
    _lock = completer.future;
    return prev.then((_) => body()).whenComplete(completer.complete);
  }
}

enum SlotRoot { documents, support }

class SlotEntry {
  const SlotEntry(this.root, this.name, {required this.isDir});
  final SlotRoot root;
  final String name;
  final bool isDir;
}

enum WorkspaceNameError { empty, tooLong, forbiddenChars, leadingDot }

enum WorkspaceErrorKind { notFound, exists, isCurrent, invalidName }

class WorkspaceError implements Exception {
  const WorkspaceError(this.kind, this.name, {this.nameError});
  final WorkspaceErrorKind kind;
  final String name;
  final WorkspaceNameError? nameError;

  @override
  String toString() => 'WorkspaceError(${kind.name}, "$name"'
      '${nameError == null ? '' : ', ${nameError!.name}'})';
}

class WorkspaceSlot {
  const WorkspaceSlot({required this.name, required this.savedAt});
  final String name;
  final DateTime savedAt;

  Map<String, dynamic> toJson() =>
      {'name': name, 'saved_at': savedAt.toIso8601String()};

  static WorkspaceSlot? fromJson(dynamic j) {
    if (j is! Map) return null;
    final name = j['name'];
    if (name is! String || name.isEmpty) return null;
    final savedAt =
        DateTime.tryParse((j['saved_at'] as String?) ?? '') ?? DateTime(1970);
    return WorkspaceSlot(name: name, savedAt: savedAt);
  }
}


class WorkspacePending {
  const WorkspacePending(this.op, this.target);
  const WorkspacePending.load(String target) : this(opLoad, target);

  static const opLoad = 'load';

  final String op;
  final String target;

  Map<String, dynamic> toJson() => {'op': op, 'target': target};

  static WorkspacePending? fromJson(dynamic j) {
    if (j is! Map) return null;
    final op = j['op'];
    final target = j['target'];
    if (op is! String || target is! String || target.isEmpty) return null;
    return WorkspacePending(op, target);
  }
}

class WorkspaceManifest {
  const WorkspaceManifest({
    required this.version,
    required this.current,
    required this.slots,
    this.pending,
  });

  factory WorkspaceManifest.initial() => const WorkspaceManifest(
        version: WorkspaceStore.manifestVersion,
        current: WorkspaceStore.defaultName,
        slots: [],
      );

  final int version;
  final String current;
  final List<WorkspaceSlot> slots;
  final WorkspacePending? pending;

  bool hasSlot(String name) => slots.any((s) => s.name == name);


  Set<String> get names => {current, for (final s in slots) s.name};

  Map<String, dynamic> toJson() => {
        'version': version,
        'current': current,
        'slots': slots.map((s) => s.toJson()).toList(),
        'pending': pending?.toJson(),
      };

  factory WorkspaceManifest.fromJson(Map<String, dynamic> j) {
    final rawSlots = j['slots'];
    final slots = <WorkspaceSlot>[];
    if (rawSlots is List) {
      for (final s in rawSlots) {
        final slot = WorkspaceSlot.fromJson(s);
        if (slot != null) slots.add(slot);
      }
    }
    final current = j['current'];
    return WorkspaceManifest(
      version: (j['version'] as num?)?.toInt() ?? WorkspaceStore.manifestVersion,
      current: current is String && current.isNotEmpty
          ? current
          : WorkspaceStore.defaultName,
      slots: slots,
      pending: WorkspacePending.fromJson(j['pending']),
    );
  }

  WorkspaceManifest copyWith({
    String? current,
    List<WorkspaceSlot>? slots,
    WorkspacePending? pending,
    bool clearPending = false,
  }) =>
      WorkspaceManifest(
        version: version,
        current: current ?? this.current,
        slots: slots ?? this.slots,
        pending: clearPending ? null : (pending ?? this.pending),
      );

  WorkspaceManifest withSlotSaved(String name, DateTime at) {
    final next = slots.where((s) => s.name != name).toList()
      ..add(WorkspaceSlot(name: name, savedAt: at));
    return copyWith(slots: next);
  }

  WorkspaceManifest withSlotRenamed(String oldName, String newName) =>
      copyWith(
        slots: slots
            .map((s) => s.name == oldName
                ? WorkspaceSlot(name: newName, savedAt: s.savedAt)
                : s)
            .toList(),
      );

  WorkspaceManifest withSlotRemoved(String name) =>
      copyWith(slots: slots.where((s) => s.name != name).toList());
}
