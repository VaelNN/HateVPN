import 'dart:async';

import 'package:flutter/widgets.dart';

import '../controllers/subscription_controller.dart';
import '../services/settings_storage.dart';



































mixin LazyPersistMixin<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver {
  bool _lazyPending = false;








  Future<void>? _stagingInFlight;



  bool get hasPendingChanges => _lazyPending;


  SubscriptionController get lazyController;





  Future<void> stageChanges();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);


    if (_lazyPending) unawaited(_flush());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {


    if (state == AppLifecycleState.paused && _lazyPending) {
      unawaited(_flush());
    }
  }



  void markDirty() {
    _lazyPending = true;
    lazyController.configDirty = true;
    _stagingInFlight = stageChanges();
    unawaited(_stagingInFlight);
  }

  Future<void> _flush() async {
    if (!_lazyPending) return;
    _lazyPending = false;




    await _stagingInFlight;
    await SettingsStorage.flushToDisk();
  }
}
