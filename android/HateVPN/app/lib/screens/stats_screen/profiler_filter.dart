import 'package:flutter/foundation.dart';

import '../../services/traffic_profiler.dart';
















class ProfilerFilter extends ChangeNotifier {
  String _search = '';
  final Set<TrafficEventKind> _kinds = <TrafficEventKind>{};
  final Set<String> _apps = <String>{};


  final Set<String> _rules = <String>{};
  final Set<String> _outbounds = <String>{};

  bool _includeUnattributed = false;

  String get search => _search;
  Set<TrafficEventKind> get kinds => _kinds;
  Set<String> get apps => _apps;
  Set<String> get rules => _rules;
  Set<String> get outbounds => _outbounds;
  bool get includeUnattributed => _includeUnattributed;


  bool get appAxisActive => _apps.isNotEmpty || _includeUnattributed;


  int get activeCount {
    var n = 0;
    if (_search.isNotEmpty) n++;
    n += _kinds.length;
    n += _apps.length;
    n += _rules.length;
    n += _outbounds.length;
    if (_includeUnattributed) n++;
    return n;
  }


  int get activeCountNoApps {
    var n = 0;
    if (_search.isNotEmpty) n++;
    n += _kinds.length;
    return n;
  }

  bool get isActive => activeCount > 0;


  set search(String v) {
    if (_search == v) return;
    _search = v;
    notifyListeners();
  }


  bool hasKind(TrafficEventKind k) => _kinds.contains(k);
  void toggleKind(TrafficEventKind k, bool on) {
    if (on) {
      _kinds.add(k);
    } else {
      _kinds.remove(k);
    }
    notifyListeners();
  }


  bool hasApp(String pkg) => _apps.contains(pkg);
  void toggleApp(String pkg, bool on) {
    if (on) {
      _apps.add(pkg);
    } else {
      _apps.remove(pkg);
    }
    notifyListeners();
  }


  bool hasRule(String r) => _rules.contains(r);
  void toggleRule(String r, bool on) {
    if (on) {
      _rules.add(r);
    } else {
      _rules.remove(r);
    }
    notifyListeners();
  }


  bool hasOutbound(String o) => _outbounds.contains(o);
  void toggleOutbound(String o, bool on) {
    if (on) {
      _outbounds.add(o);
    } else {
      _outbounds.remove(o);
    }
    notifyListeners();
  }


  set includeUnattributed(bool v) {
    if (_includeUnattributed == v) return;
    _includeUnattributed = v;
    notifyListeners();
  }

  void clearAll() {
    _search = '';
    _kinds.clear();
    _apps.clear();
    _rules.clear();
    _outbounds.clear();
    _includeUnattributed = false;
    notifyListeners();
  }



  static TrafficEventKind kindFamily(TrafficEventKind k) => switch (k) {
        TrafficEventKind.dnsFail => TrafficEventKind.dnsResolve,
        TrafficEventKind.tcpClose => TrafficEventKind.tcpOpen,
        _ => k,
      };

  static bool _isUnattributed(TrafficEvent e) =>
      e.confidence == ConfidenceLevel.unattributed;



  Iterable<TrafficEvent> apply(Iterable<TrafficEvent> src,
      {bool includeApps = true}) {
    var list = src;
    if (_kinds.isNotEmpty) {
      list = list.where((e) => _kinds.contains(kindFamily(e.kind)));
    }
    if (includeApps && appAxisActive) {
      list = list.where((e) {

        final byApp = e.process != null && _apps.contains(e.process);
        final byUnattr = _includeUnattributed && _isUnattributed(e);
        return byApp || byUnattr;
      });
    }
    if (_rules.isNotEmpty) {

      list = list.where((e) => _rules.contains(e.rule ?? ''));
    }
    if (_outbounds.isNotEmpty) {

      list = list.where((e) =>
          e.outboundChain.any(_outbounds.contains) ||
          e.detourChain.any(_outbounds.contains));
    }
    if (_search.isNotEmpty) {
      final lq = _search.toLowerCase();
      list = list.where((e) =>
          (e.domain?.toLowerCase().contains(lq) ?? false) ||
          (e.ip?.contains(_search) ?? false) ||
          (e.process?.toLowerCase().contains(lq) ?? false));
    }
    return list;
  }
}
