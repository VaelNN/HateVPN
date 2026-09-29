part of '../home_controller.dart';






mixin _ConfigIoMixin on ChangeNotifier {

  HomeState get _state;
  BoxVpnClient get _vpn;
  void _emit(HomeState next);
  void _addDebug(DebugSource source, String message);

  Future<void> _loadSavedConfig() async {
    try {
      final config = await _vpn.getConfig();
      if (config.isNotEmpty && config != '{}') {

        _emit(_state.copyWith(configRaw: config, configLoadError: false));
      }
    } catch (e) {
      _addDebug(DebugSource.app, 'Load config: $e');
    }

    try {
      final saved = await SettingsStorage.getNodeSort();
      if (saved.mode.isNotEmpty) {
        final mode = NodeSortMode.values.firstWhere(
          (m) => m.name == saved.mode,
          orElse: () => _state.sortMode,
        );
        _emit(_state.copyWith(sortMode: mode, manualOrder: saved.order));
      }
    } catch (e) {
      _addDebug(DebugSource.app, 'Load sort: $e');
    }
  }




  void markConfigLoadError() {
    if (_state.configLoadError) return;
    _emit(_state.copyWith(configLoadError: true));
  }

  Future<bool> saveParsedConfig(String canonicalJson, {String? displayRaw}) async {
    if (kDebugMode) {



      final callerFrames = StackTrace.current.toString().split('\n').take(4).join(' | ');
      _addDebug(DebugSource.app,
          '[vpn] saveParsedConfig ENTER tunnelUp=${_state.tunnelUp} need_restart_before=${_state.configChangedNeedRestart} caller=$callerFrames');
    } else {
      _addDebug(DebugSource.app,
          '[vpn] saveParsedConfig ENTER tunnelUp=${_state.tunnelUp} need_restart_before=${_state.configChangedNeedRestart}');
    }
    final ok = await _vpn.saveConfig(canonicalJson);
    if (!ok) {
      _emit(_state.copyWith(lastError: const ErrMsg(ErrKey.failedToSaveConfig)));
      _addDebug(DebugSource.app, 'Save config failed');
      return false;
    }
    final raw = displayRaw ?? canonicalJson;






    bool changed;
    try {


      changed = _state.configRaw.isEmpty ||
          await canonicalJsonForSingboxAsync(canonicalJson) !=
              await canonicalJsonForSingboxAsync(_state.configRaw);
    } catch (_) {
      changed = true;
    }












    var needRestart =
        changed && (_state.tunnelUp || _state.configChangedNeedRestart);










    if (needRestart && _state.tunnelUp) {
      final verdict = await _checkStaleness(canonicalJson);
      if (verdict == StalenessVerdict.fresh) {
        needRestart = false;
      }
      _addDebug(DebugSource.app,
          '[vpn] §324 staleness=${verdict.name} → need_restart=$needRestart');
    }

    _addDebug(DebugSource.app,
        '[vpn] saveParsedConfig EXIT changed=$changed need_restart_after=$needRestart (tunnelUp=${_state.tunnelUp} prev=${_state.configChangedNeedRestart})');
    _emit(_state.copyWith(
      configRaw: raw,
      lastError: null,
      configChangedNeedRestart: needRestart,

      configLoadError: false,













      pingBatchGen: changed && !_state.tunnelUp
          ? _state.pingBatchGen + 1
          : _state.pingBatchGen,
    ));
    _addDebug(DebugSource.app, 'Config saved (${canonicalJson.length} bytes)');
    return true;
  }









  Future<StalenessVerdict> _checkStaleness(String canonicalJson) async {




    final running = _state.runningConfigRaw;
    if (running == null || running.isEmpty) {


      return StalenessVerdict.unknown;
    }




    bool autoRedirect;
    try {
      autoRedirect = await _vpn.getAutoRedirect();
    } catch (_) {
      return StalenessVerdict.unknown;
    }

    final withOverrides = applyOverrides(
      canonicalJson,
      OverrideSnapshot(



        includeSelfPackage: true,
        autoRedirect: autoRedirect,
      ),
    );

    final canonicalSaved = await _vpn.formatConfig(withOverrides);
    return compareCanonical(
      canonicalSaved: canonicalSaved,
      runningSnapshot: running,
    );
  }

  Future<bool> saveConfigRaw(String raw) async {
    if (raw.trim().isEmpty) {
      _emit(_state.copyWith(lastError: const ErrMsg(ErrKey.configIsEmpty)));
      _addDebug(DebugSource.app, 'Save rejected: empty config');
      return false;
    }
    try {
      final canonical = await canonicalJsonForSingboxAsync(raw);



      return await saveParsedConfig(canonical, displayRaw: raw);
    } on FormatException catch (e) {
      _emit(_state.copyWith(lastError: PrefixedMsg(ErrPrefix.parseConfigFailed, RawMsg(e.message))));
      _addDebug(DebugSource.app, 'Config parse error: ${e.message}');
      return false;
    }
  }





  Future<bool> readFromClipboard() async {
    _emit(_state.copyWith(busy: true, lastError: null));
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      if (text.trim().isEmpty) {
        _emit(_state.copyWith(lastError: const ErrMsg(ErrKey.clipboardIsEmpty), busy: false));
        _addDebug(DebugSource.app, 'Clipboard is empty');
        return false;
      }
      final canonical = await canonicalJsonForSingboxAsync(text);
      final ok = await saveParsedConfig(canonical, displayRaw: text);
      _emit(_state.copyWith(busy: false));
      return ok;
    } on FormatException catch (e) {
      _emit(_state.copyWith(lastError: PrefixedMsg(ErrPrefix.parseConfigFailed, RawMsg(e.message)), busy: false));
      _addDebug(DebugSource.app, 'Clipboard parse error: ${e.message}');
      return false;
    } catch (_) {
      _emit(_state.copyWith(lastError: const ErrMsg(ErrKey.failedToParseConfig), busy: false));
      _addDebug(DebugSource.app, 'Clipboard parse failed');
      return false;
    }
  }

  Future<bool> readFromFile() async {
    _emit(_state.copyWith(busy: true, lastError: null));
    try {



      final outcome = await pickFileSafely();
      if (outcome is! PickedFiles) {
        switch (outcome) {
          case PickCancelled():
            _emit(_state.copyWith(busy: false));
          case PickNoPicker():
            _emit(_state.copyWith(
                lastError: const ErrMsg(ErrKey.noFileManager), busy: false));
            _addDebug(DebugSource.app, 'File pick: no file manager on device');
          case PickFailed(:final error):
            _emit(_state.copyWith(
                lastError:
                    PrefixedMsg(ErrPrefix.fileError, formatUserError(error)),
                busy: false));
            _addDebug(DebugSource.app, 'File pick failed: $error');
          case PickedFiles():
            break;
        }
        return false;
      }
      final file = outcome.single;
      final text = file.text;
      if (text.isEmpty) {
        _emit(_state.copyWith(lastError: const ErrMsg(ErrKey.failedToReadFile), busy: false));
        _addDebug(DebugSource.app, 'File pick failed: no bytes and no path');
        return false;
      }

      if (text.trim().isEmpty) {
        _emit(_state.copyWith(lastError: const ErrMsg(ErrKey.fileIsEmpty), busy: false));
        _addDebug(DebugSource.app, 'Selected file is empty');
        return false;
      }

      final canonical = await canonicalJsonForSingboxAsync(text);
      final ok = await saveParsedConfig(canonical, displayRaw: text);
      _emit(_state.copyWith(busy: false));
      return ok;
    } on FormatException catch (e) {
      _emit(_state.copyWith(lastError: PrefixedMsg(ErrPrefix.parseConfigFailed, RawMsg(e.message)), busy: false));
      _addDebug(DebugSource.app, 'File parse error: ${e.message}');
      return false;
    } catch (e) {
      _emit(_state.copyWith(
          lastError: PrefixedMsg(ErrPrefix.fileError, formatUserError(e)), busy: false));
      _addDebug(DebugSource.app, 'File read error: $e');
      return false;
    }
  }
}
