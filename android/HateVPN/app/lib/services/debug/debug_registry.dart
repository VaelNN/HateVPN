import '../../controllers/home_controller.dart';
import '../../controllers/subscription_controller.dart';
import '../subscription/auto_updater.dart';








class DebugRegistry {
  DebugRegistry._();
  static final DebugRegistry I = DebugRegistry._();

  HomeController? home;
  SubscriptionController? sub;
  AutoUpdater? autoUpdater;

  bool get ready => home != null && sub != null;
}
