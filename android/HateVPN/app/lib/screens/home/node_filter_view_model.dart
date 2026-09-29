import 'dart:async';

import 'package:flutter/widgets.dart';

import 'direction_filters.dart';




















class NodeFilterViewModel extends ChangeNotifier {

  bool _panelExpanded = false;
  bool get panelExpanded => _panelExpanded;
  void togglePanel() {
    _panelExpanded = !_panelExpanded;
    notifyListeners();
  }





  bool _detourEnabled = false;
  bool _detourHide = true;
  bool get detourEnabled => _detourEnabled;
  bool get detourHide => _detourHide;

  void setDetourEnabled(bool v) {
    _detourEnabled = v;
    notifyListeners();
  }

  void toggleDetourHide() {
    _detourHide = !_detourHide;
    notifyListeners();
  }



  bool detourPoolPasses(bool isDetour) =>
      !_detourEnabled || (_detourHide ? !isDetour : isDetour);



  bool get detourActive => _detourEnabled;



  bool get detourOnly => _detourEnabled && !_detourHide;


  bool _showNonMatching = true;
  bool get showNonMatching => _showNonMatching;
  void setShowNonMatching(bool v) {
    _showNonMatching = v;
    notifyListeners();
  }


  final TextEditingController regexController = TextEditingController();
  RegExp? _regexCompiled;
  bool _regexValid = true;
  bool _regexInvert = false;
  Timer? _regexTimer;

  bool get regexValid => _regexValid;
  bool get regexInvert => _regexInvert;




  RegExp? get activeRegex => _regexCompiled;

  void onRegexChanged(String text) {
    _regexTimer?.cancel();
    _regexTimer = Timer(const Duration(milliseconds: 300), () {
      if (_disposed) return;
      if (text.isEmpty) {
        _regexCompiled = null;
        _regexValid = true;
      } else {
        try {
          _regexCompiled = RegExp(text, caseSensitive: false);
          _regexValid = true;
        } catch (_) {
          _regexCompiled = null;
          _regexValid = false;
        }
      }
      notifyListeners();
    });
  }

  void toggleRegexInvert() {
    _regexInvert = !_regexInvert;
    notifyListeners();
  }

  void clearRegex() {
    regexController.clear();
    _regexTimer?.cancel();
    _regexCompiled = null;
    _regexValid = true;
    _regexInvert = false;
    notifyListeners();
  }



  void onEmojiChipTap(String emoji) {
    final parts =
        regexController.text.split('|').where((p) => p.isNotEmpty).toList();
    if (!parts.remove(emoji)) parts.add(emoji);
    final next = parts.join('|');
    regexController.text = next;
    regexController.selection = TextSelection.collapsed(offset: next.length);
    notifyListeners();
    onRegexChanged(next);
  }


  Set<String> get selectedEmojis =>
      regexController.text.split('|').where((p) => p.isNotEmpty).toSet();


  final Set<String> enabledProtocols = <String>{};
  final Set<String> enabledVariants = <String>{};
  final Set<String> enabledSubscriptions = <String>{};
  bool _protocolsInvert = false;
  bool _variantsInvert = false;
  bool _subscriptionsInvert = false;
  bool get protocolsInvert => _protocolsInvert;
  bool get variantsInvert => _variantsInvert;
  bool get subscriptionsInvert => _subscriptionsInvert;

  void toggleProtocol(String proto) {
    if (!enabledProtocols.add(proto)) enabledProtocols.remove(proto);
    notifyListeners();
  }

  void toggleProtocolsInvert() {
    _protocolsInvert = !_protocolsInvert;
    notifyListeners();
  }



  void toggleVariant(String v) {
    if (!enabledVariants.add(v)) enabledVariants.remove(v);
    notifyListeners();
  }

  void toggleVariantsInvert() {
    _variantsInvert = !_variantsInvert;
    notifyListeners();
  }

  void toggleSubscription(String id) {
    if (!enabledSubscriptions.add(id)) enabledSubscriptions.remove(id);
    notifyListeners();
  }

  void toggleSubscriptionsInvert() {
    _subscriptionsInvert = !_subscriptionsInvert;
    notifyListeners();
  }






  static const defaultPingText = '200';

  final TextEditingController pingController =
      TextEditingController(text: defaultPingText);
  int? _maxPingMs = int.tryParse(defaultPingText);
  bool _pingEnabled = false;
  Timer? _pingTimer;

  bool get pingEnabled => _pingEnabled;


  int? get activeMaxPingMs => _pingEnabled ? _maxPingMs : null;

  void onPingChanged(String text) {
    _pingTimer?.cancel();
    _pingTimer = Timer(const Duration(milliseconds: 300), () {
      if (_disposed) return;
      final n = int.tryParse(text);
      _maxPingMs = (n != null && n > 0) ? n : null;
      if (_maxPingMs != null) _pingEnabled = true;
      notifyListeners();
    });
  }

  void setPingEnabled(bool v) {
    _pingEnabled = v;
    notifyListeners();
  }

  void clearPing() {
    pingController.clear();
    _pingTimer?.cancel();
    _maxPingMs = null;
    _pingEnabled = false;
    notifyListeners();
  }


  bool get regexActive => _regexCompiled != null;
  bool get protocolActive => enabledProtocols.isNotEmpty;
  bool get variantActive => enabledVariants.isNotEmpty;
  bool get subscriptionActive => enabledSubscriptions.isNotEmpty;
  bool get pingActive => _pingEnabled && _maxPingMs != null;


  bool get isActive =>
      regexActive ||
      protocolActive ||
      variantActive ||
      subscriptionActive ||
      pingActive;


  bool get nonMatchingHidden => !_showNonMatching;



  bool get settingsActive => pingActive || detourActive || nonMatchingHidden;



  bool get hasActiveFilters => isActive || detourActive || nonMatchingHidden;


  final Map<String, DirectionFilters> _byDirection = {};
  String? _activeDirection;


  bool get _pingIsDefault =>
      !_pingEnabled && pingController.text == defaultPingText;

  DirectionFilters _capture() => DirectionFilters(
        regexPattern: regexController.text,
        regexInvert: _regexInvert,
        protocols: Set.of(enabledProtocols),
        protocolsInvert: _protocolsInvert,
        variants: Set.of(enabledVariants),
        variantsInvert: _variantsInvert,
        subscriptions: Set.of(enabledSubscriptions),
        subscriptionsInvert: _subscriptionsInvert,

        pingText: _pingIsDefault ? '' : pingController.text,
        pingEnabled: _pingEnabled,
      );

  void _restore(DirectionFilters f) {
    _regexTimer?.cancel();
    _pingTimer?.cancel();
    regexController.text = f.regexPattern;
    if (f.regexPattern.isEmpty) {
      _regexCompiled = null;
      _regexValid = true;
    } else {
      try {
        _regexCompiled = RegExp(f.regexPattern, caseSensitive: false);
        _regexValid = true;
      } catch (_) {
        _regexCompiled = null;
        _regexValid = false;
      }
    }
    _regexInvert = f.regexInvert;
    enabledProtocols
      ..clear()
      ..addAll(f.protocols);
    _protocolsInvert = f.protocolsInvert;
    enabledVariants
      ..clear()
      ..addAll(f.variants);
    _variantsInvert = f.variantsInvert;
    enabledSubscriptions
      ..clear()
      ..addAll(f.subscriptions);
    _subscriptionsInvert = f.subscriptionsInvert;

    final restoredPing = f.pingText.isEmpty ? defaultPingText : f.pingText;
    pingController.text = restoredPing;
    final n = int.tryParse(restoredPing);
    _maxPingMs = (n != null && n > 0) ? n : null;
    _pingEnabled = f.pingEnabled;
  }




  void syncDirection(String? direction) {
    if (direction == _activeDirection) return;
    final prev = _activeDirection;
    if (prev != null) {
      final snap = _capture();
      if (snap.isEmpty) {
        _byDirection.remove(prev);
      } else {
        _byDirection[prev] = snap;
      }
    }
    if (direction == null) {
      _activeDirection = null;
      return;
    }
    _restore(_byDirection[direction] ?? DirectionFilters.empty);
    _activeDirection = direction;
    notifyListeners();
  }


  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _regexTimer?.cancel();
    _pingTimer?.cancel();
    regexController.dispose();
    pingController.dispose();
    super.dispose();
  }
}
