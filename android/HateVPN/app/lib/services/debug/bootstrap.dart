import 'context.dart';
import 'debug_registry.dart';
import 'transport/server.dart';




final DateTime appStartedAt = DateTime.now();








Future<void> applyDebugApiSettings() async {
  final ctx = DebugContext(
    registry: DebugRegistry.I,
    appStartedAt: appStartedAt,
  );
  await DebugServer.I.restartFromSettings(ctx);
}
