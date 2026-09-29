import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../models/custom_rule.dart';
import '../../models/parser_config.dart';
import '../../models/preset_rule_set.dart' show ruleSetsEnabledByVar;
import '../../services/builder/preset_expand.dart' show PresetNode;
import '../../services/l10n/locale_controller.dart';
import '../../services/preset_on_change.dart';
import '../../services/record_vars.dart';
import '../../services/relative_time.dart';
import '../../services/rule_set_downloader.dart';
import '../../services/settings_storage.dart';
import '../../services/template_loader.dart';
import '../../widgets/wifi_entry.dart';
import 'normalizers.dart' as norm;
import 'sections/srs_section.dart' show SrsDownloadState;
import 'wifi_zip.dart';

export 'sections/srs_section.dart' show SrsDownloadState;

























class CustomRuleEditController extends ChangeNotifier {
  CustomRuleEditController({
    required this.initial,
    required this.preset,
    required this.existingNames,
    this.displayName,
    this.presetNodes = const [],
  }) {
    _init();
  }


  final List<PresetNode> presetNodes;




  final CustomRule initial;




  final SelectableRule? preset;




  final Set<String> existingNames;






  final String? displayName;



  late final TextEditingController nameCtrl;
  late final TextEditingController domainCtrl;
  late final TextEditingController domainSuffixCtrl;
  late final TextEditingController domainKeywordCtrl;
  late final TextEditingController ipCidrCtrl;
  late final TextEditingController sourceIpCidrCtrl;
  late final TextEditingController portCtrl;
  late final TextEditingController portRangeCtrl;
  late final TextEditingController srsUrlCtrl;


  late final TextEditingController jsonCtrl;



  late bool _enabled;
  late bool _ipIsPrivate;
  late bool _sourceIpIsPrivate;
  late Set<String> _inbounds;
  late CustomRuleKind _kind;
  late String _outbound;
  late Set<String> _protocols;
  late Set<String> _network;
  late List<String> _packages;
  late List<WifiEntry> _wifiNetworks;
  late Map<String, String> _varsValues;
  late RuleDns? _dns;
  late RuleResolve? _resolve;
  List<String> _dnsServerTags = const [];




  bool _hasMixedInbound = false;





  Map<String, String> _globalVars = const {};
  Map<String, String> get globalVars => _globalVars;





  Map<String, WizardVar> _refVarDefs = const {};
  Map<String, WizardVar> get refVarDefs => _refVarDefs;

  Map<String, String> _presetSrsPaths = const {};
  SrsDownloadState _srsState = SrsDownloadState.none;


  int _srsTtlHours = kDefaultSrsTtlHours;



  String? _srsLastUpdatedText;
  final Set<String> _boolVarDownloading = <String>{};

  bool _disposed = false;



  bool get enabled => _enabled;
  bool get ipIsPrivate => _ipIsPrivate;
  bool get sourceIpIsPrivate => _sourceIpIsPrivate;


  Set<String> get inbounds => _inbounds;




  List<({String tag, String label})> get inboundChoices => [
        (tag: 'tun-in', label: 'TUN — system interface'),
        if (_hasMixedInbound) (tag: 'mixed-in', label: 'Proxy interface'),
      ];

  CustomRuleKind get kind => _kind;
  String get outbound => _outbound;
  Set<String> get protocols => _protocols;


  Set<String> get network => _network;
  List<String> get packages => _packages;
  List<WifiEntry> get wifiNetworks => _wifiNetworks;
  Map<String, String> get varsValues => _varsValues;
  Map<String, String> get presetSrsPaths => _presetSrsPaths;
  SrsDownloadState get srsState => _srsState;


  String? get srsLastUpdatedText => _srsLastUpdatedText;


  Future<void> _loadSrsMeta(String id) async {
    final meta = await RuleSetDownloader.readMeta(id);
    if (_disposed) return;
    final last = meta.lastUpdated;
    if (meta.failing) {
      _srsLastUpdatedText =
          getLocalText.s("Update failed — using cached copy");
    } else if (last != null) {
      _srsLastUpdatedText =
          getLocalText.s("Updated %s", relativeTime(DateTime.now(), last));
    } else {
      _srsLastUpdatedText = null;
    }
    notifyListeners();
  }


  int get srsTtlHours => _srsTtlHours;

  set srsTtlHours(int v) {
    if (_srsTtlHours == v) return;
    _srsTtlHours = v;
    notifyListeners();
  }
  Set<String> get boolVarDownloading => _boolVarDownloading;


  RuleDns? get dns => _dns;


  RuleResolve? get resolve => _resolve;





  bool get resolveEligible => switch (_kind) {
        CustomRuleKind.srs => true,
        CustomRuleKind.inline =>
          norm.normalizedDomains(domainCtrl.text).isNotEmpty ||
              norm
                  .normalizedDomains(domainSuffixCtrl.text,
                      stripLeadingDot: true)
                  .isNotEmpty ||
              norm.normalizedKeywords(domainKeywordCtrl.text).isNotEmpty,
        _ => false,
      };



  List<String> get dnsServerTags => _dnsServerTags;




  bool get dnsGateBlocked =>
      norm.normalizedPorts(portCtrl.text).isNotEmpty ||
      norm.normalizedPortRanges(portRangeCtrl.text).isNotEmpty ||
      _protocols.isNotEmpty ||
      _network.isNotEmpty;



  List<TextEditingController> get _allTextCtrls => [
        nameCtrl,
        domainCtrl,
        domainSuffixCtrl,
        domainKeywordCtrl,
        ipCidrCtrl,
        sourceIpCidrCtrl,
        portCtrl,
        portRangeCtrl,
        srsUrlCtrl,
        jsonCtrl,
      ];

  void _init() {
    final r = initial;
    nameCtrl = TextEditingController(text: r.name);
    domainCtrl = TextEditingController(text: r.domains.join('\n'));
    domainSuffixCtrl =
        TextEditingController(text: r.domainSuffixes.join('\n'));
    domainKeywordCtrl =
        TextEditingController(text: r.domainKeywords.join('\n'));
    ipCidrCtrl = TextEditingController(text: r.ipCidrs.join('\n'));
    sourceIpCidrCtrl = TextEditingController(text: r.sourceIpCidrs.join('\n'));
    portCtrl = TextEditingController(text: r.ports.join('\n'));
    portRangeCtrl = TextEditingController(text: r.portRanges.join('\n'));

    srsUrlCtrl = TextEditingController(text: r.srsUrls.join('\n'));


    if (r is CustomRuleSrs) _srsTtlHours = r.updateIntervalHours;
    jsonCtrl = TextEditingController(text: r.json);
    _enabled = r.enabled;
    _ipIsPrivate = r.ipIsPrivate;
    _sourceIpIsPrivate = r.sourceIpIsPrivate;
    _inbounds = r.inbounds.toSet();
    _kind = r.kind;
    _outbound = r.outbound;
    _protocols = r.protocols.toSet();
    _network = r.network.toSet();
    _packages = List.of(r.packages);
    _wifiNetworks = unzipWifiEntries(r.wifiSsids, r.wifiBssids);
    _varsValues = Map<String, String>.from(r.varsValues);
    _dns = r.dns;
    _resolve = r.resolve;
    unawaited(_loadDnsServerTags());
    unawaited(_loadVpnMode());



    for (final c in _allTextCtrls) {
      c.addListener(_onTextChanged);
    }

    if (_kind == CustomRuleKind.srs) {
      _allSrsCached(r).then((cached) {
        if (_disposed) return;
        _srsState =
            cached ? SrsDownloadState.cached : SrsDownloadState.none;
        notifyListeners();
      });
      unawaited(_loadSrsMeta(r.id));
    }
    if (r is CustomRulePreset && preset != null) {
      _resolvePresetSrsPaths(r, preset!);
    }
  }

  void _onTextChanged() {
    if (_disposed) return;





    notifyListeners();
  }




  Future<void> _loadDnsServerTags() async {
    final stored = await SettingsStorage.getDnsServers();
    final template = await TemplateLoader.load();
    final tags = <String>{
      for (final s in stored)
        if (s.tag.isNotEmpty) s.tag,
    };

    tags.addAll(template.dnsOptionsModel.servers.map((s) => s.tag));
    if (_disposed) return;
    _dnsServerTags = tags.toList();
    notifyListeners();
  }



  Future<void> _loadVpnMode() async {
    final cfg = await SettingsStorage.getVpnMode();
    final userVars = await SettingsStorage.getAllVars();
    final template = await TemplateLoader.load();
    if (_disposed) return;
    _hasMixedInbound = cfg.hasMixed;



    final refDefs = <String, WizardVar>{};
    final refDefaults = <String, String>{};
    final p = preset;
    if (p != null) {
      for (final v in p.vars) {
        if (!v.isRef) continue;
        final global = template.globalVar(v.ref);
        if (global == null) continue;
        refDefs[v.ref] = global;
        refDefaults[v.ref] = global.defaultValue;
      }
    }
    _refVarDefs = refDefs;





    _globalVars = {...refDefaults, ...userVars, 'vpn_mode': cfg.mode};
    notifyListeners();
  }




  Future<void> setGlobalVar(String name, String val) async {
    await SettingsStorage.setVar(name, val);
    _globalVars = {..._globalVars, name: val};
    notifyListeners();
  }




  Future<void> _resolvePresetSrsPaths(
      CustomRulePreset rule, SelectableRule preset) async {
    final paths = <String, String>{};
    for (final rs in preset.ruleSets) {
      if (rs['type'] != 'remote') continue;
      final tag = rs['tag'];
      if (tag is! String || tag.isEmpty) continue;
      final p =
          await RuleSetDownloader.cachedPathForPreset(rule.presetId, tag);
      if (p != null) paths[tag] = p;
    }
    if (_disposed) return;
    _presetSrsPaths = paths;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final c in _allTextCtrls) {
      c.removeListener(_onTextChanged);
      c.dispose();
    }
    super.dispose();
  }



  void setEnabled(bool v) {
    if (_enabled == v) return;
    _enabled = v;
    notifyListeners();
    _applyPresetOnChange();
  }




  void _applyPresetOnChange() {
    final p = preset;
    if (p == null) return;
    final snap = snapshot();
    if (snap is CustomRulePreset) {
      unawaited(applyPresetOnChange(p, snap));
    }
  }

  void setIpIsPrivate(bool v) {
    if (_ipIsPrivate == v) return;
    _ipIsPrivate = v;
    notifyListeners();
  }

  void setSourceIpIsPrivate(bool v) {
    if (_sourceIpIsPrivate == v) return;
    _sourceIpIsPrivate = v;
    notifyListeners();
  }


  void toggleInbound(String tag, bool checked) {
    if (checked) {
      if (!_inbounds.add(tag)) return;
    } else {
      if (!_inbounds.remove(tag)) return;
    }
    notifyListeners();
  }

  void setKind(CustomRuleKind v) {
    if (_kind == v) return;
    _kind = v;

    if (_kind == CustomRuleKind.srs &&
        _srsState != SrsDownloadState.cached) {
      _enabled = false;
    }



    notifyListeners();
  }

  void setOutbound(String v) {
    if (_outbound == v) return;
    _outbound = v;
    notifyListeners();
  }



  void setResolve(RuleResolve? v) {
    _resolve = v;
    notifyListeners();
  }



  void notifyJsonChanged() => notifyListeners();

  void toggleProtocol(String p, bool checked) {
    if (checked) {
      if (!_protocols.add(p)) return;
    } else {
      if (!_protocols.remove(p)) return;
    }
    notifyListeners();
  }


  void toggleNetwork(String n, bool checked) {
    if (checked) {
      if (!_network.add(n)) return;
    } else {
      if (!_network.remove(n)) return;
    }
    notifyListeners();
  }


  void clearNetworkAndProtocol() {
    if (_network.isEmpty && _protocols.isEmpty) return;
    _network.clear();
    _protocols.clear();
    notifyListeners();
  }

  void setPackages(List<String> v) {
    _packages = v;
    notifyListeners();
  }

  void addWifiEntry(WifiEntry e) {
    if (_wifiNetworks.any((x) => x.ssid == e.ssid && x.bssid == e.bssid)) {
      return;
    }
    _wifiNetworks.add(e);
    notifyListeners();
  }



  int addWifiEntries(Iterable<WifiEntry> entries) {
    var added = 0;
    for (final e in entries) {
      if (_wifiNetworks
          .any((x) => x.ssid == e.ssid && x.bssid == e.bssid)) {
        continue;
      }
      _wifiNetworks.add(e);
      added++;
    }
    if (added > 0) notifyListeners();
    return added;
  }

  void removeWifiAt(int i) {
    _wifiNetworks.removeAt(i);
    notifyListeners();
  }

  void setVarValue(String name, String val) {
    _putVarValue(name, val);
    notifyListeners();
  }





  void _putVarValue(String name, String val) {
    WizardVar? decl;
    for (final v in preset?.vars ?? const <WizardVar>[]) {
      if (v.name == name && !v.isRef) {
        decl = v;
        break;
      }
    }
    final stored = recordVarValueToStore(
      val,
      decl == null
          ? null
          : RecordVarDecl(name: decl.name, defaultValue: decl.defaultValue),
    );
    if (stored == null) {
      _varsValues.remove(name);
    } else {
      _varsValues[name] = stored;
    }
  }




  void setDnsEnabled(bool v) {
    if (!v) {




      final force = _dns?.forceIpv4 ?? false;
      _dns = force ? const RuleDns(forceIpv4: true) : null;
      notifyListeners();
      return;
    }
    var tag = _dns?.serverTag ?? '';
    if (tag.isEmpty) {
      tag = _dnsServerTags.contains('google_udp')
          ? 'google_udp'
          : (_dnsServerTags.isNotEmpty ? _dnsServerTags.first : '');
    }

    _dns = (_dns ?? const RuleDns()).copyWith(enabled: true, serverTag: tag);
    notifyListeners();
  }


  void setDnsServerTag(String tag) {
    _dns = (_dns ?? const RuleDns()).copyWith(serverTag: tag);
    notifyListeners();
  }





  void setForceIpv4(bool v) {
    final next = (_dns ?? const RuleDns()).copyWith(forceIpv4: v);
    _dns = (!next.forceIpv4 && !next.enabled && next.serverTag.isEmpty)
        ? null
        : next;
    notifyListeners();
  }



  Future<void> downloadSrs() async {
    final urls = parseSrsUrlsText(srsUrlCtrl.text);
    if (urls.isEmpty) return;
    _srsState = SrsDownloadState.loading;
    notifyListeners();


    var ok = true;
    for (var i = 0; i < urls.length; i++) {
      final path = await RuleSetDownloader.download(
          CustomRuleSrs.cacheIdAt(initial.id, i), urls[i]);
      if (_disposed) return;
      if (path == null) {
        ok = false;
        break;
      }
    }
    _srsState = ok ? SrsDownloadState.cached : SrsDownloadState.error;
    notifyListeners();

    unawaited(_loadSrsMeta(initial.id));
  }




  Future<void> clearSrsCache() async {


    final saved = initial.srsUrls.length;
    final typed = parseSrsUrlsText(srsUrlCtrl.text).length;
    final n = saved > typed ? saved : typed;
    for (var i = 0; i < (n == 0 ? 1 : n); i++) {
      await RuleSetDownloader.delete(CustomRuleSrs.cacheIdAt(initial.id, i));
    }
    if (_disposed) return;
    _srsState = SrsDownloadState.none;
    _enabled = false;
    _srsLastUpdatedText = null;
    notifyListeners();
  }


  static Future<bool> _allSrsCached(CustomRule r) async {
    if (r is! CustomRuleSrs || r.srsUrls.isEmpty) return false;
    for (final cacheId in r.cacheIds) {
      if (!await RuleSetDownloader.isCached(cacheId)) return false;
    }
    return true;
  }



  void resetSrsErrorIfAny() {
    if (_srsState != SrsDownloadState.error) return;
    _srsState = SrsDownloadState.none;
    notifyListeners();
  }









  Future<bool> onBoolVarToggle(WizardVar v, bool val) async {
    final p = preset;
    if (p == null) return false;




    if (v.isRef) {
      await setGlobalVar(v.ref, val ? 'true' : 'false');
      return false;
    }

    if (!val) {
      _putVarValue(v.name, 'false');
      notifyListeners();
      _applyPresetOnChange();
      return false;
    }

    final initial = this.initial;
    final presetId =
        initial is CustomRulePreset ? initial.presetId : p.presetId;


    final controlled = ruleSetsEnabledByVar(
      p,
      CustomRulePreset(name: '', presetId: presetId, varsValues: _varsValues),
      v.name,
      globalVars: _globalVars,
    );

    if (controlled.isEmpty) {
      _putVarValue(v.name, 'true');
      notifyListeners();
      _applyPresetOnChange();
      return false;
    }

    final missing = <_PendingDownload>[];
    for (final rs in controlled) {
      final cached =
          await RuleSetDownloader.cachedPathForPreset(presetId, rs.tag) != null;
      if (!cached) missing.add(_PendingDownload(tag: rs.tag, url: rs.url));
    }
    if (_disposed) return false;

    if (missing.isEmpty) {
      _putVarValue(v.name, 'true');
      _presetSrsPaths = {..._presetSrsPaths};
      notifyListeners();
      _applyPresetOnChange();
      return false;
    }

    _boolVarDownloading.add(v.name);
    notifyListeners();

    final newPaths = <String, String>{};
    var anyFailed = false;
    for (final m in missing) {
      final path = await RuleSetDownloader.downloadForPreset(
          presetId, m.tag, m.url);
      if (path == null) {
        anyFailed = true;
      } else {
        newPaths[m.tag] = path;
      }
    }
    if (_disposed) return false;

    _boolVarDownloading.remove(v.name);
    if (!anyFailed) {
      _putVarValue(v.name, 'true');
      _presetSrsPaths = {..._presetSrsPaths, ...newPaths};
      _applyPresetOnChange();
    }
    notifyListeners();
    return anyFailed;
  }













  CustomRule snapshot() {
    final name = nameCtrl.text.trim();
    switch (_kind) {
      case CustomRuleKind.json:
        return CustomRuleJson(
          id: initial.id,
          name: name,
          enabled: _enabled,
          orderNum: initial.orderNum,
          json: jsonCtrl.text,
        );
      case CustomRuleKind.preset:
        final init = initial;
        return CustomRulePreset(
          id: init.id,
          name: name,
          enabled: _enabled,
          orderNum: init.orderNum,
          presetId: init is CustomRulePreset ? init.presetId : '',
          varsValues: Map<String, String>.from(_varsValues),
        );
      case CustomRuleKind.srs:
        final wifi = zipWifiEntries(_wifiNetworks);
        return CustomRuleSrs(
          id: initial.id,
          name: name,
          enabled: _enabled,
          orderNum: initial.orderNum,
          srsUrls: parseSrsUrlsText(srsUrlCtrl.text),
          updateIntervalHours: _srsTtlHours,
          ports: norm.normalizedPorts(portCtrl.text),
          portRanges: norm.normalizedPortRanges(portRangeCtrl.text),
          packages: List.of(_packages),
          protocols: _protocols.toList()..sort(),
          network: _network.toList()..sort(),
          ipIsPrivate: _ipIsPrivate,
          sourceIpCidrs: norm.normalizedCidrs(sourceIpCidrCtrl.text),
          sourceIpIsPrivate: _sourceIpIsPrivate,
          inbounds: _inbounds.toList()..sort(),
          wifiSsids: wifi.ssids,
          wifiBssids: wifi.bssids,
          outbound: _outbound,
          dns: _dns,


          resolve: resolveEligible ? _resolve : null,
        );
      case CustomRuleKind.inline:
        final wifi = zipWifiEntries(_wifiNetworks);
        return CustomRuleInline(
          id: initial.id,
          name: name,
          enabled: _enabled,
          orderNum: initial.orderNum,
          domains: norm.normalizedDomains(domainCtrl.text),
          domainSuffixes: norm.normalizedDomains(
              domainSuffixCtrl.text,
              stripLeadingDot: true),
          domainKeywords: norm.normalizedKeywords(domainKeywordCtrl.text),
          ipCidrs: norm.normalizedCidrs(ipCidrCtrl.text),
          ports: norm.normalizedPorts(portCtrl.text),
          portRanges: norm.normalizedPortRanges(portRangeCtrl.text),
          packages: List.of(_packages),
          protocols: _protocols.toList()..sort(),
          network: _network.toList()..sort(),
          ipIsPrivate: _ipIsPrivate,
          sourceIpCidrs: norm.normalizedCidrs(sourceIpCidrCtrl.text),
          sourceIpIsPrivate: _sourceIpIsPrivate,
          inbounds: _inbounds.toList()..sort(),
          wifiSsids: wifi.ssids,
          wifiBssids: wifi.bssids,
          outbound: _outbound,
          dns: _dns,
          resolve: resolveEligible ? _resolve : null,
        );
    }
  }



  bool isDirty() =>
      snapshot() != initial ||
      (_kind == CustomRuleKind.json && jsonCtrl.text != initial.json);





  String? get saveBlockReason => jsonError;








  String? get jsonError {
    if (_kind != CustomRuleKind.json) return null;
    final text = jsonCtrl.text.trim();
    if (text.isEmpty) return 'Enter a JSON object.';
    final dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return 'Invalid JSON.';
    }
    if (decoded is Map) return null;
    if (decoded is List) {
      return getLocalText.s(
          "One rule holds one JSON object. Add each object of the array as a separate rule.");
    }
    return 'Expected a JSON object.';
  }
}


class _PendingDownload {
  const _PendingDownload({required this.tag, required this.url});
  final String tag;
  final String url;
}





class CustomRuleEditScope extends InheritedNotifier<CustomRuleEditController> {
  const CustomRuleEditScope({
    super.key,
    required CustomRuleEditController super.notifier,
    required super.child,
  });

  static CustomRuleEditController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<CustomRuleEditScope>();
    assert(scope != null, 'CustomRuleEditScope.of: no scope in context');
    return scope!.notifier!;
  }

}
