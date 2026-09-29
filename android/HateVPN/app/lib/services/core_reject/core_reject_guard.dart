



































library;

import '../../models/core_reject_verdict.dart';
import 'core_error_parse.dart';




const kCoreRejectRoundLimit = 10;


enum CoreRejectPrompt {

  stop,


  keepChecking,
}


enum CoreRejectPhase {

  idle,


  signalStart,


  checking,


  awaitingPrompt,


  finalStart,


  done,
}


enum CoreRejectOutcome {

  startedClean,



  startedWithDisabled,



  failed,


  stoppedByUser,
}


final class DisabledNode {
  const DisabledNode({
    required this.tag,
    required this.reason,
    this.ref,
  });


  final String tag;


  final String reason;


  final CoreRejectNodeRef? ref;

  Map<String, dynamic> toJson() => {
        'tag': tag,
        'reason': reason,
        if (ref != null) ...ref!.toParams(),
      };

  @override
  String toString() => 'DisabledNode($tag: $reason)';
}


final class CoreRejectRun {
  const CoreRejectRun({
    required this.outcome,
    this.disabled = const [],
    this.error = '',
    this.rounds = 0,
  });

  final CoreRejectOutcome outcome;


  final List<DisabledNode> disabled;


  final String error;


  final int rounds;

  bool get started =>
      outcome == CoreRejectOutcome.startedClean ||
      outcome == CoreRejectOutcome.startedWithDisabled;
}


final class CoreAttempt {
  const CoreAttempt.accepted()
      : ok = true,
        error = '',
        bridgeDown = false;

  const CoreAttempt.rejected(this.error)
      : ok = false,
        bridgeDown = false;



  const CoreAttempt.unavailable()
      : ok = false,
        error = '',
        bridgeDown = true;

  final bool ok;
  final String error;
  final bool bridgeDown;
}


final class RebuiltConfig {
  const RebuiltConfig({required this.configJson, required this.tags});

  final String configJson;



  final Set<String> tags;
}



abstract interface class CoreRejectHost {

  Future<CoreAttempt> realStart();



  Future<RebuiltConfig?> rebuild();


  Future<CoreAttempt> check(String configJson);




  Future<CoreRejectNodeRef?> disableNode(String tag, String reason);




  Future<CoreRejectPrompt> askKeepChecking(int disabledCount);




  void onProgress(
    CoreRejectPhase phase,
    int round, {
    List<DisabledNode> disabledNodes,
  });
}


final class CoreRejectGuard {
  CoreRejectGuard(this._host, {this.roundLimit = kCoreRejectRoundLimit});

  final CoreRejectHost _host;
  final int roundLimit;

  final _disabled = <DisabledNode>[];


  final _seenRefs = <CoreRejectNodeRef>{};
  var _phase = CoreRejectPhase.idle;
  var _round = 0;
  var _unlimited = false;
  var _cancelled = false;

  CoreRejectPhase get phase => _phase;
  int get round => _round;
  List<DisabledNode> get disabled => List.unmodifiable(_disabled);



  void cancel() => _cancelled = true;

  void _to(CoreRejectPhase p) {
    _phase = p;
    _host.onProgress(p, _round, disabledNodes: List.unmodifiable(_disabled));
  }

  CoreRejectRun _finish(CoreRejectOutcome outcome, {String error = ''}) {
    _to(CoreRejectPhase.done);
    return CoreRejectRun(
      outcome: outcome,
      disabled: List.unmodifiable(_disabled),
      error: error,
      rounds: _round,
    );
  }

  Future<CoreRejectRun> run() async {

    _to(CoreRejectPhase.signalStart);
    final first = await _host.realStart();
    if (first.ok) return _finish(CoreRejectOutcome.startedClean);
    if (first.bridgeDown) return _finish(CoreRejectOutcome.failed);


    final hit = await _consume(first.error);
    if (hit == null) {
      return _finish(CoreRejectOutcome.failed, error: first.error);
    }


    _to(CoreRejectPhase.checking);
    while (true) {
      if (_cancelled) return _finish(CoreRejectOutcome.stoppedByUser);



      if (!_unlimited && _round >= roundLimit) {
        _to(CoreRejectPhase.awaitingPrompt);



        final answer = await _host.askKeepChecking(roundLimit);
        if (answer == CoreRejectPrompt.stop) {
          return _finish(CoreRejectOutcome.stoppedByUser);
        }
        _unlimited = true;
        _to(CoreRejectPhase.checking);
      }

      final built = await _host.rebuild();
      if (built == null) {

        return _finish(CoreRejectOutcome.failed);
      }

      _round++;
      final verdict = await _host.check(built.configJson);
      _host.onProgress(CoreRejectPhase.checking, _round,
          disabledNodes: List.unmodifiable(_disabled));

      if (_cancelled) return _finish(CoreRejectOutcome.stoppedByUser);

      if (verdict.ok) break;

      if (verdict.bridgeDown) {


        break;
      }

      final next = await _consume(verdict.error, tags: built.tags);
      if (next == null) {
        return _finish(CoreRejectOutcome.failed, error: verdict.error);
      }
    }


    if (_cancelled) return _finish(CoreRejectOutcome.stoppedByUser);
    _to(CoreRejectPhase.finalStart);
    final last = await _host.realStart();
    if (last.ok) {
      return _finish(_disabled.isEmpty
          ? CoreRejectOutcome.startedClean
          : CoreRejectOutcome.startedWithDisabled);
    }



    if (!last.bridgeDown) await _consume(last.error);
    return _finish(CoreRejectOutcome.failed, error: last.error);
  }











  Future<DisabledNode?> _consume(String error, {Set<String>? tags}) async {
    final built = tags ?? await _tagsOfCurrentConfig();
    if (built == null) return null;
    final hit = parseCoreRejection(error, built);
    if (hit == null) return null;
    final ref = await _host.disableNode(hit.tag, hit.reason);
    if (ref == null) return null;
    if (!_seenRefs.add(ref)) return null;
    final d = DisabledNode(tag: hit.tag, reason: hit.reason, ref: ref);
    _disabled.add(d);
    _host.onProgress(_phase, _round,
        disabledNodes: List.unmodifiable(_disabled));
    return d;
  }




  Future<Set<String>?> _tagsOfCurrentConfig() async =>
      (await _host.rebuild())?.tags;
}
