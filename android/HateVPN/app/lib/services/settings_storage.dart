import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:path_provider/path_provider.dart';

import '../models/background_mode.dart';
import '../models/codec/chain_record.dart';
import '../models/codec/dns_record.dart';
import '../models/codec/rule_record.dart';
import '../models/codec/source_record.dart';
import '../models/direction.dart';
import '../models/dns_ref.dart';
import '../models/source_chain.dart';
import '../models/source_entry.dart';
import '../models/memory_limit_setting.dart';
import '../models/custom_rule.dart';
import '../models/parser_config.dart';
import '../models/server_list.dart';
import '../vpn/box_vpn_client.dart';
import 'app_log.dart';
import 'config_dirty_check.dart';
import 'l10n/app_language_reconcile.dart';
import 'record_vars.dart';
import 'selectable_to_custom.dart';
import 'settings_storage_keys.dart';
import 'storage_migration/migrate_storage.dart';
import 'subscription/http_cache.dart';
import 'template_loader.dart';
import 'warp/masque_account.dart';
import 'warp/warp_account.dart';

part 'settings_storage/io.dart';
part 'settings_storage/vars.dart';
part 'settings_storage/sources_rules.dart';
part 'settings_storage/directions.dart';
part 'settings_storage/chains.dart';
part 'settings_storage/network.dart';
part 'settings_storage/backup_tun.dart';
part 'settings_storage/vpn_mode.dart';
part 'settings_storage/warp.dart';
part 'settings_storage/native_prefs.dart';


















class SettingsStorage {
  SettingsStorage._();

  static const _fileName = 'lxbox_settings.json';
  static const _bakSuffix = '.bak';
  static const _tmpSuffix = '.tmp';






  static int _tmpSeq = 0;
  static Map<String, dynamic>? _cache;
  static Future<void>? _pendingSave;















  static bool get configDirty => _configDirty;
  static bool _configDirty = false;





  static set configDirty(bool v) {
    if (v && !_configDirty) {
      final frames = StackTrace.current.toString().split('\n');
      final caller = frames
          .skip(1)
          .take(3)
          .map((f) => f.replaceAll(RegExp(r'\s+'), ' ').trim())
          .join(' ← ');
      AppLog.I.debug('configDirty ↑ $caller');
    }
    _configDirty = v;
  }


  static void markConfigDirty() => configDirty = true;





  static const _configVarKeys = <String>{
    'auto_detect_interface',
    'dns_cache_capacity',
    'dns_default_domain_resolver',
    'dns_final',
    'dns_optimistic',
    'dns_store_cache',
    'dns_strategy',
    'log_level',
    'resolve_strategy',
    'tun_address',
    'tun_address6',
    'tun_auto_route',
    'tun_mtu',
    'tun_name',
    'tun_stack',
    'tun_strict_route',
  };












  static const allowedTopLevelKeys = <String>{
    kStorageVersionKey,
    'vars',
    kSourcesKey,
    kRulesKey,
    kDnsKey,
    'ping_options',
    'route_final',
    'route_idle_suspend',
    'route_idle_suspend_reachable',
    'wg_build_max',
    'wg_lazy_build',
    'urltest_passive_check',
    'enabled_groups',
    'directions',
    'directions_migrated',



    'tun_apps',
    'vpn_mode',
    'warp_account',
    'masque_account',

    'last_global_update',
    'presets_migrated',
    'late_presets_seeded',
    'interrupt_connections_on_switch',
    'node_sort_mode',
    'node_manual_order',
    'profiler_retention_sec',
  };





  static const _appFeatureFlagVars = <String>{

    'auto_update_subs',
    'auto_update_disabled_subs',

    'auto_reload_on_change',

    'auto_check_updates',
    'last_update_check_at',
    'last_known_version',
    'dismissed_update_version',

    'shown_crash_stamp',

    'config_locked_for_debug',
    'debug_enabled',
    'debug_token',
    'debug_port',

    'wifi_history',
    'auto_record_wifi_history',


    'probe_ms_green',
    'probe_ms_yellow',
    'probe_ms_orange',


    'auto_ping_on_start',

    'automation_receive_enabled',
    'automation_emit_lifecycle',
    'automation_emit_state',
    'automation_emit_subs',
    'automation_emit_health',
    'automation_explainer_shown_v1',

    'subscription_user_agent',
    'subscription_send_hwid',
    'subscription_hwid',
    'subscription_device_os',
    'subscription_ver_os',
    'subscription_device_model',

    'haptic_enabled',
    'notif_perm_prompted_v1',
    'allow_rotation',
    'node_list_two_columns',
    'app_language',
    'region',
  };




  static Set<String> allowedVarKeys(Iterable<String> templateVarNames) =>
      {..._appFeatureFlagVars, ...templateVarNames};










  static bool _mainIsCorrupted = false;
  static bool _corruptionLogged = false;




  static void resetCacheForTesting() {
    _cache = null;
    _pendingSave = null;
    _mainIsCorrupted = false;
    _corruptionLogged = false;
    configDirty = false;
  }




  static bool get mainIsCorruptedForTesting => _mainIsCorrupted;


  static void clearCache() => _cache = null;





  static Future<void> flushToDisk() async {
    if (_cache == null) return;
    await _save();
  }





  static Future<String> getVar(String name, String defaultValue) =>
      _getVar(name, defaultValue);



  static Future<void> setVar(String name, String value,
          {bool flush = true}) =>
      _setVar(name, value, flush: flush);

  static Future<Map<String, String>> getAllVars() => _getAllVars();





  static Future<void> removeVar(String name) => _removeVar(name);










  static Future<List<SourceEntry>> getSourceEntries() => _getSourceEntries();




  static Future<void> saveSourceEntries(List<SourceEntry> entries,
          {bool flush = true}) =>
      _saveSourceEntries(entries, flush: flush);



  static List<SourceEntry> sourceEntriesOf(
    Map<String, dynamic> doc, {
    void Function(Object error)? onCorrupt,
  }) =>
      _sourceEntriesOf(doc, onCorrupt: onCorrupt);

  static Future<List<ServerList>> getServerLists() => _getServerLists();



  static Future<void> saveServerLists(List<ServerList> lists) =>
      _saveServerLists(lists);




  static String sourceKeyForId(String id) => sourceKeyForIdOf(id);


  static String sourceKeyForChain(String tag) => sourceKeyForChainOf(tag);



  static Future<List<String>> getSourceKeys() => _getSourceKeys();




  static Future<bool> reorderSources(List<String> keys) =>
      _reorderSources(keys);




  static List<ServerList> serverListsOf(
    Map<String, dynamic> doc, {
    void Function(Object error)? onCorrupt,
  }) =>
      _serverListsOf(doc, onCorrupt: onCorrupt);







  static Future<Set<String>> getEnabledGroups() => _getEnabledGroups();

  static Future<void> saveEnabledGroups(Set<String> groups,
          {bool flush = true}) =>
      _saveEnabledGroups(groups, flush: flush);








  static Future<List<Direction>> getDirections() => _getDirections();




  @visibleForTesting
  static Future<void> setDirections(List<Direction> directions, {bool flush = true}) =>
      _setDirections(directions, flush: flush);







  @visibleForTesting
  static Future<Direction> addDirection({String? label, String? tag}) =>
      _addDirection(label: label, tag: tag);









  @visibleForTesting
  static Future<DirectionHealResult> updateDirection(Direction direction) =>
      _updateDirection(direction);





  @visibleForTesting
  static Future<DirectionHealResult> deleteDirection(String tag) =>
      _deleteDirection(tag);










  static Future<void> migrateDirectionsIfNeeded(
    GroupTemplates gt, {
    Map<String, String> varDefaults = const {},
  }) =>
      _migrateDirectionsIfNeeded(gt, varDefaults: varDefaults);









  static Future<List<SourceChain>> getChains() => _getChains();




  static List<SourceChain> chainsOf(
    Map<String, dynamic> doc, {
    void Function(Object error)? onCorrupt,
  }) =>
      _chainsOf(doc, onCorrupt: onCorrupt);

  static Future<void> setChains(List<SourceChain> chains, {bool flush = true}) =>
      _setChains(chains, flush: flush);




  static Future<SourceChain> addChain({String? label, String? tag}) =>
      _addChain(label: label, tag: tag);






  static Future<SourceChain> createChain(SourceChain chain) =>
      _createChain(chain);



  static Future<void> updateChain(SourceChain chain) => _updateChain(chain);



  static Future<void> reorderChains(List<SourceChain> chains) =>
      _reorderChains(chains);



  static Future<ChainHealResult> deleteChain(String tag) => _deleteChain(tag);





  static Future<ChainHealResult> healChainHops(String tag, {bool flush = true}) =>
      _healChainHops(tag, flush: flush);





  static Future<DateTime?> getLastGlobalUpdate() => _getLastGlobalUpdate();

  static Future<void> setLastGlobalUpdate(DateTime dt) =>
      _setLastGlobalUpdate(dt);


  static Duration? parseReloadInterval(String reload) =>
      _parseReloadInterval(reload);


  static Future<bool> shouldRefreshSubscriptions(String reloadInterval) =>
      _shouldRefreshSubscriptions(reloadInterval);









  static Future<List<CustomRule>> getCustomRules() => _getCustomRules();




  static List<CustomRule> customRulesOf(
    Map<String, dynamic> doc, {
    void Function(Object error)? onCorrupt,
  }) =>
      _customRulesOf(doc, onCorrupt: onCorrupt);

  static Future<void> saveCustomRules(List<CustomRule> rules,
          {bool flush = true}) =>
      _saveCustomRules(rules, flush: flush);



  static Future<bool> hasDefaultsSeeded() => _hasDefaultsSeeded();

  static Future<void> markDefaultsSeeded() => _markDefaultsSeeded();




  static Future<bool> seedLateDefaultPresets([WizardTemplate? template]) =>
      _seedLateDefaultPresets(template);






  static Future<String> getRouteFinal() => _getRouteFinal();

  static Future<void> saveRouteFinal(String outbound, {bool flush = true}) =>
      _saveRouteFinal(outbound, flush: flush);



  static Future<String> getIdleSuspend() => _getIdleSuspend();

  static Future<void> saveIdleSuspend(String threshold, {bool flush = true}) =>
      _saveIdleSuspend(threshold, flush: flush);



  static Future<String> getIdleSuspendReachable() => _getIdleSuspendReachable();

  static Future<void> saveIdleSuspendReachable(String threshold,
          {bool flush = true}) =>
      _saveIdleSuspendReachable(threshold, flush: flush);



  static Future<int> getWgBuildMax() => _getWgBuildMax();

  static Future<void> saveWgBuildMax(int value, {bool flush = true}) =>
      _saveWgBuildMax(value, flush: flush);



  static Future<bool> getWgLazyBuild() => _getWgLazyBuild();

  static Future<void> saveWgLazyBuild(bool enabled, {bool flush = true}) =>
      _saveWgLazyBuild(enabled, flush: flush);



  static Future<bool> getPassiveCheck() => _getPassiveCheck();

  static Future<void> savePassiveCheck(bool enabled, {bool flush = true}) =>
      _savePassiveCheck(enabled, flush: flush);





  static Future<({String mode, List<String> order})> getNodeSort() async {
    final c = await _load();
    final raw = c['node_manual_order'];
    return (
      mode: c['node_sort_mode'] as String? ?? '',
      order: raw is List ? raw.whereType<String>().toList() : const <String>[],
    );
  }

  static Future<void> setNodeSort(String mode, List<String> order) async {
    final c = await _load();
    c['node_sort_mode'] = mode;
    c['node_manual_order'] = List<String>.from(order);
    await _save();
  }




  static Future<bool> getInterruptOnSwitch() async {
    final c = await _load();
    return c['interrupt_connections_on_switch'] == true;
  }

  static Future<void> setInterruptOnSwitch(bool value) async {
    final c = await _load();
    c['interrupt_connections_on_switch'] = value;
    SettingsStorage._cache = c;
    await _save();
  }





  static const int profilerRetentionDefaultSec = 600;

  static Future<int> getProfilerRetentionSec() async {
    final c = await _load();
    final v = c['profiler_retention_sec'];
    if (v is int && v > 0) return v;
    return profilerRetentionDefaultSec;
  }

  static Future<void> setProfilerRetentionSec(int seconds) async {
    final c = await _load();
    c['profiler_retention_sec'] = seconds;
    SettingsStorage._cache = c;
    await _save();
  }




  static Future<List<DnsServerRef>> getDnsServers() => _getDnsServers();



  static Future<void> saveDnsServers(List<DnsServerRef> servers,
          {bool flush = true}) =>
      _saveDnsServers(servers, flush: flush);







  static Future<Map<String, dynamic>> getPingOptions() => _getPingOptions();




  static Future<void> savePingOptions(Map<String, dynamic> options) =>
      _savePingOptions(options);


  static Future<void> setGlobalPingUrl(String url) => _setGlobalPingUrl(url);


  static Future<void> setGlobalPingTimeout(int timeoutMs) =>
      _setGlobalPingTimeout(timeoutMs);




  static Future<void> setGroupPing(
    String groupTag, {
    String? url,
    int? timeoutMs,
  }) =>
      _setGroupPing(groupTag, url: url, timeoutMs: timeoutMs);


  static Future<void> clearGroupPing(String groupTag) =>
      _clearGroupPing(groupTag);



  static Future<List<DnsRuleRef>> getDnsRulesList() => _getDnsRulesList();



  static Future<void> saveDnsRulesList(List<DnsRuleRef> rules,
          {bool flush = true}) =>
      _saveDnsRulesList(rules, flush: flush);







  static Future<bool> getAutoUpdateSubs() async =>
      (await getVar('auto_update_subs', 'true')) != 'false';

  static Future<void> setAutoUpdateSubs(bool enabled) =>
      setVar('auto_update_subs', enabled ? 'true' : 'false');





  static Future<bool> getAutoUpdateDisabledSubs() async =>
      (await getVar('auto_update_disabled_subs', 'false')) == 'true';

  static Future<void> setAutoUpdateDisabledSubs(bool enabled) =>
      setVar('auto_update_disabled_subs', enabled ? 'true' : 'false');








  static Future<bool> getAutoReloadOnChange() async =>
      (await getVar('auto_reload_on_change', 'false')) == 'true';

  static Future<void> setAutoReloadOnChange(bool enabled) =>
      setVar('auto_reload_on_change', enabled ? 'true' : 'false');









  static Future<bool> getConfigLockedForDebug() async =>
      (await getVar('config_locked_for_debug', 'false')) == 'true';

  static Future<void> setConfigLockedForDebug(bool locked) =>
      setVar('config_locked_for_debug', locked ? 'true' : 'false');











  static const int _wifiHistoryCap = 50;

  static Future<List<Map<String, String>>> getWifiHistory() => _getWifiHistory();



  static Future<void> addToWifiHistory(String ssid, String bssid) =>
      _addToWifiHistory(ssid, bssid);

  static Future<void> removeFromWifiHistory(String ssid, String bssid) =>
      _removeFromWifiHistory(ssid, bssid);

  static Future<void> clearWifiHistory() => setVar('wifi_history', '[]');





  static Future<bool> getAutoRecordWifi() async =>
      (await getVar('auto_record_wifi_history', 'false')) == 'true';

  static Future<void> setAutoRecordWifi(bool enabled) =>
      setVar('auto_record_wifi_history', enabled ? 'true' : 'false');





  static Future<bool> getAllowRotation() async =>
      (await getVar('allow_rotation', 'false')) == 'true';

  static Future<void> setAllowRotation(bool enabled) =>
      setVar('allow_rotation', enabled ? 'true' : 'false');





  static final ValueNotifier<bool> nodeListTwoColumns = ValueNotifier<bool>(true);

  static Future<bool> getNodeListTwoColumns() async {
    final v = (await getVar('node_list_two_columns', 'true')) != 'false';
    nodeListTwoColumns.value = v;
    return v;
  }

  static Future<void> setNodeListTwoColumns(bool enabled) {
    nodeListTwoColumns.value = enabled;
    return setVar('node_list_two_columns', enabled ? 'true' : 'false');
  }



  static const appLanguageValues = {'system', 'en', 'ru', 'zh'};




  static Future<String> getAppLanguage() async {
    final v = await getVar('app_language', 'system');
    return appLanguageValues.contains(v) ? v : 'system';
  }

  static Future<void> setAppLanguage(String value) async {
    final v = appLanguageValues.contains(value) ? value : 'system';
    await setVar('app_language', v);
    await _mirrorAppLanguageToNative(v);
  }




  static const regionAuto = 'auto';
  static const regionNone = 'none';

  static String normalizeRegion(String value) {
    final v = value.trim().toLowerCase();
    if (v == regionAuto || v == regionNone) return v;
    return RegExp(r'^[a-z]{2}$').hasMatch(v) ? v : regionAuto;
  }

  static Future<String> getRegion() async =>
      normalizeRegion(await getVar('region', regionAuto));

  static Future<void> setRegion(String value) =>
      setVar('region', normalizeRegion(value));











  static Future<bool> getAutoCheckUpdates() async =>
      (await getVar('auto_check_updates', 'false')) != 'false';

  static Future<void> setAutoCheckUpdates(bool enabled) =>
      setVar('auto_check_updates', enabled ? 'true' : 'false');

  static Future<DateTime?> getLastUpdateCheck() async {
    final raw = await getVar('last_update_check_at', '');
    return raw.isEmpty ? null : DateTime.tryParse(raw);
  }

  static Future<void> setLastUpdateCheck(DateTime dt) =>
      setVar('last_update_check_at', dt.toUtc().toIso8601String());



  static Future<String> getLastKnownVersion() async =>
      getVar('last_known_version', '');

  static Future<void> setLastKnownVersion(String tag) =>
      setVar('last_known_version', tag);



  static Future<String> getDismissedUpdateVersion() async =>
      getVar('dismissed_update_version', '');

  static Future<void> setDismissedUpdateVersion(String tag) =>
      setVar('dismissed_update_version', tag);








  static Future<String> getShownCrashStamp() async =>
      getVar('shown_crash_stamp', '');

  static Future<void> setShownCrashStamp(String stamp) =>
      setVar('shown_crash_stamp', stamp);





  static const int debugPortDefault = 9269;




  static const int debugPortMin = 1024;
  static const int debugPortMax = 49151;

  static Future<bool> getDebugEnabled() async =>
      (await getVar('debug_enabled', 'false')) == 'true';

  static Future<void> setDebugEnabled(bool enabled) =>
      setVar('debug_enabled', enabled ? 'true' : 'false');

  static Future<String> getDebugToken() async => getVar('debug_token', '');

  static Future<void> setDebugToken(String token) =>
      setVar('debug_token', token);

  static Future<int> getDebugPort() async {
    final raw = await getVar('debug_port', '$debugPortDefault');
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < debugPortMin || parsed > debugPortMax) {
      return debugPortDefault;
    }
    return parsed;
  }

  static Future<void> setDebugPort(int port) =>
      setVar('debug_port', port.toString());











  static Future<bool> getAutomationReceiveEnabled() async =>
      (await getVar('automation_receive_enabled', 'false')) == 'true';

  static Future<void> setAutomationReceiveEnabled(bool enabled) =>
      setVar('automation_receive_enabled', enabled ? 'true' : 'false');



  static Future<bool> getAutomationEmitLifecycle() async =>
      (await getVar('automation_emit_lifecycle', 'false')) == 'true';

  static Future<void> setAutomationEmitLifecycle(bool enabled) =>
      setVar('automation_emit_lifecycle', enabled ? 'true' : 'false');


  static Future<bool> getAutomationEmitState() async =>
      (await getVar('automation_emit_state', 'false')) == 'true';

  static Future<void> setAutomationEmitState(bool enabled) =>
      setVar('automation_emit_state', enabled ? 'true' : 'false');


  static Future<bool> getAutomationEmitSubs() async =>
      (await getVar('automation_emit_subs', 'false')) == 'true';

  static Future<void> setAutomationEmitSubs(bool enabled) =>
      setVar('automation_emit_subs', enabled ? 'true' : 'false');


  static Future<bool> getAutomationEmitHealth() async =>
      (await getVar('automation_emit_health', 'false')) == 'true';

  static Future<void> setAutomationEmitHealth(bool enabled) =>
      setVar('automation_emit_health', enabled ? 'true' : 'false');


  static Future<bool> getAutomationExplainerShown() async =>
      (await getVar('automation_explainer_shown_v1', 'false')) == 'true';

  static Future<void> setAutomationExplainerShown(bool shown) =>
      setVar('automation_explainer_shown_v1', shown ? 'true' : 'false');








  static Future<Map<String, dynamic>> dumpCache() => _dumpCache();




  static Future<Map<String, dynamic>> exportRaw() => dumpCache();



  static Future<Map<String, dynamic>?> exportV0Backup() => _readV0Backup();




  static Future<Map<String, String>> presetIdsForMigration() =>
      _presetIdsForMigration();





  static Future<Map<String, String>> subscriptionBodiesForMigration(
          Map<String, dynamic> doc) =>
      _subscriptionBodiesForMigration(doc);





  static const Set<String> debugApiVarKeys = {
    'debug_enabled',
    'debug_token',
    'debug_port',
  };







  static const String batteryPromptVar = 'wizard_battery_v1';
  static const String addTilePromptVar = 'wizard_addtile_v1';
  static const String updateCheckPromptVar = 'wizard_update_check_v1';
  static const String notificationPromptVar = 'notif_perm_prompted_v1';
  static const Set<String> startupPromptVarKeys = {
    batteryPromptVar,
    addTilePromptVar,
    updateCheckPromptVar,
    notificationPromptVar,
  };









  static Future<List<String>> replaceRaw(
    Map<String, dynamic> snapshot, {
    bool merge = false,
  }) =>
      _replaceRaw(snapshot, merge: merge);















  static const _tunAppsModeOff = 'off';
  static const _tunAppsModeAllow = 'allow';
  static const _tunAppsModeDeny = 'deny';



  static Future<TunAppsConfig> getTunApps() => _getTunApps();



  static Future<void> setTunApps(TunAppsConfig cfg, {bool flush = true}) =>
      _setTunApps(cfg, flush: flush);











  static const _vpnModeVpn = 'vpn';
  static const _vpnModeProxy = 'proxy';
  static const _vpnModeVpnProxy = 'vpn_proxy';



  static Future<VpnModeConfig> getVpnMode() => _getVpnMode();


  static Future<void> setVpnMode(VpnModeConfig cfg, {bool flush = true}) =>
      _setVpnMode(cfg, flush: flush);




  static Future<Map<String, dynamic>> getNativePrefs() => _getNativePrefs();
  static Future<bool> getNativeBool(String key) => _getNativeBool(key);
  static Future<String> getNativeBackgroundMode() => _getNativeBackgroundMode();
  static Future<void> setNativeBool(String key, bool value) =>
      _setNativeBool(key, value);
  static Future<void> setNativeBackgroundMode(String wireValue) =>
      _setNativeBackgroundMode(wireValue);

  static Future<String> getNativeMemoryLimit() => _getNativeMemoryLimit();
  static Future<void> setNativeMemoryLimit(String wireValue) =>
      _setNativeMemoryLimit(wireValue);



  static Future<void> bootstrapAndSyncNativePrefs() =>
      _bootstrapAndSyncNativePrefs();



  static Future<Map<String, dynamic>> exportNativePrefsBackup() =>
      _exportToBackupMap();
  static Future<int> applyNativePrefsBackup(Map<String, dynamic> data,
          {void Function(String, Object)? onError}) =>
      _applyFromBackupMap(data, onError: onError);



  static Future<void> setNativeHasTun(bool hasTun) => _setNativeHasTun(hasTun);







  static Future<WarpAccount?> getWarpAccount() => _getWarpAccount();


  static Future<void> setWarpAccount(WarpAccount? account,
          {bool flush = true}) =>
      _setWarpAccount(account, flush: flush);


  static Future<MasqueAccount?> getMasqueAccount() => _getMasqueAccount();


  static Future<void> setMasqueAccount(MasqueAccount? account,
          {bool flush = true}) =>
      _setMasqueAccount(account, flush: flush);
}
