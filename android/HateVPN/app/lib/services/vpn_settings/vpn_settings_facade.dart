














import '../settings_storage.dart';
import '../subscription/subscription_identity.dart' show generateProxyPassword;

class VpnSettingsFacade {
  const VpnSettingsFacade._();









  static Future<VpnModeConfig> applyVpnMode(VpnModeConfig requested) async {
    var next = requested;
    if (next.hasMixed && next.effectiveAuth && next.proxyPassword.isEmpty) {
      next = next.copyWith(proxyPassword: generateProxyPassword());
    }
    final cur = await SettingsStorage.getVpnMode();
    await SettingsStorage.setVpnMode(next);
    if (next.hasTun != cur.hasTun) {
      await SettingsStorage.setNativeHasTun(next.hasTun);
    }
    return next;
  }


  static Future<VpnModeConfig> loadVpnMode() => SettingsStorage.getVpnMode();
}
