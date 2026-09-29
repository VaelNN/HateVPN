import '../controllers/subscription_controller.dart';
import '../models/direction.dart';
import 'l10n/locale_controller.dart';
import 'settings_storage.dart';

































class DirectionMutations {
  const DirectionMutations._();








  static Future<Direction> add({String? label, String? tag}) =>

      SettingsStorage.addDirection(label: label, tag: tag);





  static Future<DirectionHealResult> update(
    Direction direction,
    SubscriptionController? sub,
  ) async {

    final healed = await SettingsStorage.updateDirection(direction);
    _resync(healed, direction.tag, sub);
    return healed;
  }




  static Future<DirectionHealResult> delete(
    String tag,
    SubscriptionController? sub,
  ) async {

    final healed = await SettingsStorage.deleteDirection(tag);
    _resync(healed, tag, sub);



    final chains = await SettingsStorage.healChainHops(tag);
    return (
      rules: healed.rules,
      detours: healed.detours,
      includes: healed.includes,
      chainPositions: chains.positions,
      dnsServers: healed.dnsServers,
    );
  }









  static Future<void> bulkReplace(
    List<Direction> directions, {
    bool flush = true,
  }) =>

      SettingsStorage.setDirections(directions, flush: flush);







  static List<String> healMessageParts(DirectionHealResult healed) => [
        if (healed.rules > 0)
          getLocalText.s(
              '%s rule reference(s) switched to vpn-1', '${healed.rules}'),
        if (healed.detours > 0)
          getLocalText.s(
              '%s detour reference(s) reset to None', '${healed.detours}'),


        if (healed.includes > 0)
          getLocalText.s('%s direction option(s) removed', '${healed.includes}'),



        if (healed.chainPositions > 0)
          getLocalText.s(
              '%s chain position(s) removed', '${healed.chainPositions}'),



        if (healed.dnsServers > 0)
          getLocalText.s(
              '%s DNS server(s) switched to vpn-1', '${healed.dnsServers}'),
      ];




  static void _resync(
    DirectionHealResult healed,
    String tag,
    SubscriptionController? sub,
  ) {
    if (healed.detours > 0) sub?.syncDetourDirectionRefsCleared(tag);
  }
}
