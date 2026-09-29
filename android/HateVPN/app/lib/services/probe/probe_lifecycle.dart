












class ProbeLifecycle {
  ProbeLifecycle._();


  static final ProbeLifecycle I = ProbeLifecycle._();


  final Set<void Function()> _cancellers = <void Function()>{};



  void Function() register(void Function() cancel) {
    _cancellers.add(cancel);
    return cancel;
  }


  void deregister(void Function() cancel) {
    _cancellers.remove(cancel);
  }




  void haltAll() {
    if (_cancellers.isEmpty) return;
    for (final cancel in _cancellers.toList()) {
      cancel();
    }
    _cancellers.clear();
  }


  bool get isProbing => _cancellers.isNotEmpty;
}
