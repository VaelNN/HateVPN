import '../../controllers/home_controller.dart';
import '../../controllers/subscription_controller.dart';
import '../app_log.dart';
import '../subscription/auto_updater.dart';
import 'contract/errors.dart';
import 'debug_registry.dart';
import 'transport/config.dart';






class DebugContext {
  DebugContext({
    required this.registry,
    required this.appStartedAt,
    this.config = const DebugServerConfig(port: 0, token: ''),
    DateTime Function()? clock,
    AppLog? log,
  })  : _clock = clock ?? DateTime.now,
        log = log ?? AppLog.I;

  final DebugRegistry registry;
  final DateTime appStartedAt;




  final DebugServerConfig config;
  final AppLog log;
  final DateTime Function() _clock;


  DateTime now() => _clock();

  HomeController? get home => registry.home;
  SubscriptionController? get sub => registry.sub;
  AutoUpdater? get autoUpdater => registry.autoUpdater;




  HomeController requireHome() {
    final h = home;
    if (h == null) throw const Conflict('home controller not ready');
    return h;
  }


  SubscriptionController requireSub() {
    final s = sub;
    if (s == null) throw const Conflict('subscription controller not ready');
    return s;
  }




  DebugContext withConfig(DebugServerConfig newConfig) => DebugContext(
        registry: registry,
        appStartedAt: appStartedAt,
        config: newConfig,
        log: log,
        clock: _clock,
      );
}
