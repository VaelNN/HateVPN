import 'support_state.dart';
























class ActiveTimeTracker {
  ActiveTimeTracker._();
  static final ActiveTimeTracker I = ActiveTimeTracker._();

  static const _key = 'active_seconds';
  static const _creditedKey = 'session_credited';
  static const _flushEvery = Duration(minutes: 1);



  Future<int> Function()? uptimeMsProvider;

  DateTime? _lastFlush;
  DateTime? _lastCredit;
  Future<void>? _crediting;



  Future<int> totalSeconds() async {
    if (uptimeMsProvider != null) {
      await _credit();
      return SupportState.I.getInt(_key);
    }
    final persisted = await SupportState.I.getInt(_key);
    final from = _lastFlush;
    if (from == null) return persisted;
    final live = DateTime.now().difference(from).inSeconds;
    return persisted + (live > 0 ? live : 0);
  }

  Future<void> onTunnelChanged(bool up) async {
    if (uptimeMsProvider != null) {
      if (up) {
        await _credit();
      } else {



        await SupportState.I.set(_creditedKey, 0);
      }
      return;
    }

    if (up) {
      _lastFlush ??= DateTime.now();
    } else {
      await _flush();
      _lastFlush = null;
    }
  }

  Future<void> tick() async {
    if (uptimeMsProvider != null) {
      final last = _lastCredit;
      if (last != null && DateTime.now().difference(last) < _flushEvery) {
        return;
      }
      await _credit();
      return;
    }

    final from = _lastFlush;
    if (from == null) return;
    if (DateTime.now().difference(from) < _flushEvery) return;
    await _flush();
  }




  Future<void> _credit() {
    final inFlight = _crediting;
    if (inFlight != null) return inFlight;
    final f = _doCredit().whenComplete(() => _crediting = null);
    _crediting = f;
    return f;
  }

  Future<void> _doCredit() async {
    final provider = uptimeMsProvider;
    if (provider == null) return;
    int uptimeMs;
    try {
      uptimeMs = await provider();
    } catch (_) {
      return;
    }
    _lastCredit = DateTime.now();
    if (uptimeMs <= 0) return;
    final uptimeSec = uptimeMs ~/ 1000;
    var credited = await SupportState.I.getInt(_creditedKey);
    if (uptimeSec < credited) credited = 0;
    final delta = uptimeSec - credited;
    if (delta <= 0) return;
    final cur = await SupportState.I.getInt(_key);
    await SupportState.I.setAll({_key: cur + delta, _creditedKey: uptimeSec});
  }

  Future<void> _flush() async {
    final from = _lastFlush;
    if (from == null) return;
    final now = DateTime.now();
    final delta = now.difference(from).inSeconds;
    if (delta > 0) {
      final cur = await SupportState.I.getInt(_key);
      await SupportState.I.set(_key, cur + delta);
    }




    if (delta > 0) _lastFlush = now;
  }


  void resetForTesting() {
    _lastFlush = null;
    _lastCredit = null;
    _crediting = null;
    uptimeMsProvider = null;
  }
}
