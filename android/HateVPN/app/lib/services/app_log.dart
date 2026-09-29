import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/debug_entry.dart';





















class AppLog extends ChangeNotifier {
  AppLog._();
  static final AppLog I = AppLog._();




  static const Map<DebugSource, int> _maxEntriesPerSource = {
    DebugSource.app: 300,
    DebugSource.core: 500,
  };


  static const Map<DebugSource, String> _persistFileNames = {
    DebugSource.app: 'applog.txt',
    DebugSource.core: 'corelog.txt',
  };


  static const Map<DebugSource, int> _persistMaxLinesPerSource = {
    DebugSource.app: 200,
    DebugSource.core: 200,
  };


  static const int _persistMaxBytesPerFile = 64 * 1024;










  final Map<DebugSource, ListQueue<DebugEntry>> _entriesBySource = {
    for (final s in DebugSource.values) s: ListQueue<DebugEntry>(),
  };

  bool _persistInitialized = false;


  final Set<DebugSource> _persistDirty = <DebugSource>{};
  bool _persistWriting = false;






  List<DebugEntry> get entries {

    final lists = _entriesBySource.values
        .map((q) => q.toList(growable: false))
        .where((l) => l.isNotEmpty)
        .toList(growable: false);
    return _mergeByTime(lists);
  }



  List<DebugEntry> entriesForSource(DebugSource source) =>
      List.unmodifiable(_entriesBySource[source] ?? const <DebugEntry>[]);








  Future<void> initPersistent() async {
    if (_persistInitialized) return;
    _persistInitialized = true;
    for (final source in DebugSource.values) {
      try {
        await _loadPersistFile(source);
      } catch (_) { }
    }
    notifyListeners();
  }

  Future<void> _loadPersistFile(DebugSource source) async {
    final f = await _persistFile(source);
    if (!await f.exists()) return;
    final raw = await f.readAsString();
    final loaded = <DebugEntry>[];
    for (final line in const LineSplitter().convert(raw)) {
      if (line.isEmpty) continue;
      try {
        final j = jsonDecode(line) as Map<String, dynamic>;



        loaded.add(DebugEntry(
          time: DateTime.parse(j['time'] as String),
          source: DebugSource.values.byName(j['source'] as String),
          level: DebugLevel.values.byName(j['level'] as String),
          message: j['message'] as String,
          fromPreviousSession: true,
        ));
      } catch (_) { }
    }

    final queue = _entriesBySource[source]!;
    queue.addAll(loaded.reversed);
    final cap = _maxEntriesPerSource[source]!;
    while (queue.length > cap) {
      queue.removeLast();
    }
  }



  void log(
    DebugLevel level,
    String message, {
    DebugSource source = DebugSource.app,
  }) {
    final line = message.trim();
    if (line.isEmpty) return;
    final queue = _entriesBySource[source];
    if (queue == null) return;
    _appendOne(queue, source, level, line);
    _scheduleNotify();
  }






  void logBatch(
    List<String> messages,
    DebugLevel Function(String) levelOf, {
    DebugSource source = DebugSource.app,
  }) {
    if (messages.isEmpty) return;
    final queue = _entriesBySource[source];
    if (queue == null) return;
    for (final raw in messages) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      _appendOne(queue, source, levelOf(line), line);
    }
    _scheduleNotify();
  }



  void _appendOne(
    ListQueue<DebugEntry> queue,
    DebugSource source,
    DebugLevel level,
    String line,
  ) {
    queue.addFirst(DebugEntry(
      time: DateTime.now(),
      source: source,
      level: level,
      message: line,
    ));
    final cap = _maxEntriesPerSource[source]!;
    while (queue.length > cap) {
      queue.removeLast();
    }
    if (kDebugMode) {

      print('[${source.name}/${level.name}] $line');
    }
    if (level == DebugLevel.warning || level == DebugLevel.error) {
      _persistDirty.add(source);
      _schedulePersistWrite();
    }
  }




  static const _notifyWindow = Duration(milliseconds: 16);

  Timer? _notifyThrottleTimer;
  bool _notifyPending = false;





  void _scheduleNotify() {
    if (_notifyThrottleTimer != null) {
      _notifyPending = true;
      return;
    }
    notifyListeners();
    _notifyThrottleTimer = Timer(_notifyWindow, () {
      _notifyThrottleTimer = null;
      if (_notifyPending) {
        _notifyPending = false;
        _scheduleNotify();
      }
    });
  }

  void debug(String message, {DebugSource source = DebugSource.app}) =>
      log(DebugLevel.debug, message, source: source);
  void info(String message, {DebugSource source = DebugSource.app}) =>
      log(DebugLevel.info, message, source: source);
  void warning(String message, {DebugSource source = DebugSource.app}) =>
      log(DebugLevel.warning, message, source: source);
  void error(String message, {DebugSource source = DebugSource.app}) =>
      log(DebugLevel.error, message, source: source);



  void clear() {
    for (final list in _entriesBySource.values) {
      list.clear();
    }
    _persistDirty.addAll(DebugSource.values);
    _schedulePersistWrite();
    notifyListeners();
  }



  void clearSource(DebugSource source) {
    final list = _entriesBySource[source];
    if (list == null) return;
    list.clear();
    _persistDirty.add(source);
    _schedulePersistWrite();
    notifyListeners();
  }



  Future<File> _persistFile(DebugSource source) async {
    final dir = await getApplicationDocumentsDirectory();
    final name = _persistFileNames[source]!;
    return File('${dir.path}/$name');
  }

  void _schedulePersistWrite() {
    if (_persistWriting) return;
    _persistWriting = true;
    Future.microtask(() async {
      try {
        while (_persistDirty.isNotEmpty) {

          final pending = _persistDirty.toList(growable: false);
          _persistDirty.clear();
          for (final source in pending) {
            await _writePersistent(source);
          }
        }
      } finally {
        _persistWriting = false;
      }
    });
  }

  Future<void> _writePersistent(DebugSource source) async {
    try {
      final f = await _persistFile(source);
      final list = _entriesBySource[source]!;


      final out = <String>[];
      var bytes = 0;
      final lineCap = _persistMaxLinesPerSource[source]!;
      for (final e in list) {
        if (e.fromPreviousSession) continue;
        if (e.level != DebugLevel.warning && e.level != DebugLevel.error) {
          continue;
        }
        final encoded = jsonEncode({
          'time': e.time.toIso8601String(),
          'source': e.source.name,
          'level': e.level.name,
          'message': e.message,
        });
        final lineBytes = utf8.encode(encoded).length + 1;





        if (bytes + lineBytes > _persistMaxBytesPerFile && out.isNotEmpty) {
          break;
        }
        out.add(encoded);
        bytes += lineBytes;
        if (out.length >= lineCap) break;
      }
      final sb = StringBuffer();
      for (final line in out.reversed) {
        sb.writeln(line);
      }
      await f.writeAsString(sb.toString(), flush: true);
    } catch (_) { }
  }







  static List<DebugEntry> _mergeByTime(Iterable<List<DebugEntry>> lists) {

    final cursors = <_Cursor>[];
    for (final l in lists) {
      if (l.isNotEmpty) cursors.add(_Cursor(l));
    }
    if (cursors.isEmpty) return const <DebugEntry>[];
    if (cursors.length == 1) {

      return List.unmodifiable(cursors.first.list);
    }
    final out = <DebugEntry>[];
    while (cursors.isNotEmpty) {

      var newestIdx = 0;
      for (var i = 1; i < cursors.length; i++) {
        if (cursors[i].current.time.isAfter(cursors[newestIdx].current.time)) {
          newestIdx = i;
        }
      }
      out.add(cursors[newestIdx].current);
      cursors[newestIdx].advance();
      if (cursors[newestIdx].done) cursors.removeAt(newestIdx);
    }
    return out;
  }





  @visibleForTesting
  void resetForTesting() {
    for (final list in _entriesBySource.values) {
      list.clear();
    }
    _persistDirty.clear();
    _persistInitialized = false;
  }
}


class _Cursor {
  _Cursor(this.list);
  final List<DebugEntry> list;
  int _idx = 0;

  bool get done => _idx >= list.length;
  DebugEntry get current => list[_idx];
  void advance() => _idx++;
}
