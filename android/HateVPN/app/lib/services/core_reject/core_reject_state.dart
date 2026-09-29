













library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'core_reject_guard.dart';

class CoreRejectState extends ChangeNotifier {
  CoreRejectState._();

  static final CoreRejectState I = CoreRejectState._();


  CoreRejectPhase _phase = CoreRejectPhase.idle;
  int _round = 0;
  List<DisabledNode> _disabled = const [];
  CoreRejectOutcome? _lastOutcome;
  String _lastError = '';


  CoreRejectPhase get phase => _phase;


  int get round => _round;


  List<DisabledNode> get disabled => List.unmodifiable(_disabled);


  CoreRejectOutcome? get lastOutcome => _lastOutcome;


  String get lastError => _lastError;


  bool _bannerVisible = false;
  List<DisabledNode> _bannerNodes = const [];




  bool get bannerVisible => _bannerVisible;




  List<DisabledNode> get bannerNodes => List.unmodifiable(_bannerNodes);



  void dismissBanner() {
    if (!_bannerVisible) return;
    _bannerVisible = false;
    _bannerNodes = const [];
    notifyListeners();
  }


  VoidCallback? _cancel;




  bool get cancellable => _cancel != null;




  void bindCancel(VoidCallback cancel) {
    _cancel = cancel;
    notifyListeners();
  }









  bool cancelRun() {
    final c = _cancel;
    if (c == null) return false;
    c();
    if (_promptPending) answerPrompt(CoreRejectPrompt.stop);
    notifyListeners();
    return true;
  }


  bool _promptPending = false;
  int _promptCount = 0;
  Completer<CoreRejectPrompt>? _promptCompleter;
  CoreRejectPrompt? _queuedPromptAnswer;


  bool get promptPending => _promptPending;



  int get promptCount => _promptCount;






  void queuePromptAnswer(CoreRejectPrompt answer) {
    _queuedPromptAnswer = answer;
    if (_promptPending) answerPrompt(answer);
    notifyListeners();
  }

  Future<CoreRejectPrompt> askPrompt(int count) {
    final pending = _promptCompleter;
    if (pending != null && !pending.isCompleted) return pending.future;
    final queued = _queuedPromptAnswer;
    if (queued != null) {
      _queuedPromptAnswer = null;
      return Future.value(queued);
    }
    final c = Completer<CoreRejectPrompt>();
    _promptCompleter = c;
    _promptPending = true;
    _promptCount = count;
    notifyListeners();
    return c.future;
  }



  void answerPrompt(CoreRejectPrompt p) {
    final c = _promptCompleter;
    _promptCompleter = null;
    _promptPending = false;
    if (c != null && !c.isCompleted) c.complete(p);
    notifyListeners();
  }





  void beginRun() {
    _phase = CoreRejectPhase.signalStart;
    _round = 0;
    _disabled = const [];
    _lastOutcome = null;
    _lastError = '';
    if (_bannerVisible) {
      _bannerVisible = false;
      _bannerNodes = const [];
    }

    notifyListeners();
  }




  bool get guardActive =>
      _phase != CoreRejectPhase.idle && _phase != CoreRejectPhase.done;


  bool get checking =>
      _phase == CoreRejectPhase.checking ||
      _phase == CoreRejectPhase.awaitingPrompt;








  void onProgress(
    CoreRejectPhase phase,
    int round, {
    List<DisabledNode> disabledNodes = const [],
  }) {
    _phase = phase;
    _round = round;
    _disabled = List.unmodifiable(disabledNodes);
    notifyListeners();
  }




  void finish(CoreRejectRun run) {
    _phase = CoreRejectPhase.done;
    _cancel = null;
    _round = run.rounds;
    _disabled = List.unmodifiable(run.disabled);
    _lastOutcome = run.outcome;
    _lastError = run.error;
    _queuedPromptAnswer = null;
    if (run.outcome == CoreRejectOutcome.startedWithDisabled &&
        run.disabled.isNotEmpty) {
      _bannerVisible = true;
      _bannerNodes = List.unmodifiable(run.disabled);
    }
    notifyListeners();
  }



  void resetRunState() {
    _phase = CoreRejectPhase.idle;
    _round = 0;
    _disabled = const [];
    _lastOutcome = null;
    _lastError = '';
    _cancel = null;
    notifyListeners();
  }

  @visibleForTesting
  void resetForTest() {
    _phase = CoreRejectPhase.idle;
    _round = 0;
    _disabled = const [];
    _lastOutcome = null;
    _lastError = '';
    _bannerVisible = false;
    _bannerNodes = const [];
    _promptPending = false;
    _promptCount = 0;
    _promptCompleter = null;
    _queuedPromptAnswer = null;
    _cancel = null;
  }
}
