import 'dart:convert';
import 'dart:io' show InternetAddress;

import 'package:flutter/widgets.dart';

import '../../config/consts.dart' show kDirectOutboundTag;
import '../../models/dns_ref.dart';
import '../../models/parser_config.dart' show WizardVar;
import '../../services/dns/tailscale_endpoint_options.dart' show TailscaleEndpointOption;
import '../../services/record_vars.dart';
import '../../widgets/outbound_picker.dart';
import '../../widgets/var_values_model.dart';
import '../dns_settings_screen/resolved_server.dart';







const kDnsServerModes = [
  'udp',
  'tls',
  'https',
  'quic',
  'h3',
  'group',
  'tailscale',
];




const kDnsAddresslessModes = {'group', 'tailscale'};


const kDnsPathModes = {'https', 'h3'};


const kDnsGroupModes = ['stable', 'fastest', 'parallel'];




final kDnsDurationRe = RegExp(r'^(\d+h)?(\d+m)?(\d+s)?$');

bool isValidDnsDuration(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return true;
  final m = kDnsDurationRe.firstMatch(v);
  return m != null && m[0] == v && v != '';
}


class DnsMemberOption {
  const DnsMemberOption({
    required this.tag,
    required this.type,
    required this.enabled,
  });
  final String tag;
  final String type;
  final bool enabled;
}



int defaultDnsPort(String mode) => switch (mode) {
  'tls' || 'quic' => 853,
  'https' || 'h3' => 443,
  _ => 53,
};


















class DnsServerEditController extends ChangeNotifier {
  DnsServerEditController({
    required this.initialRef,
    this.resolved,
    this.templateWrapper,
    this.canonicalDescription = '',
    this.outboundOptions = const [],
    this.dnsServerTags = const [],
    this.dnsMemberOptions = const [],
    this.tailscaleEndpoints = const [],
  }) {
    _init();
  }



  final DnsServerRef initialRef;


  final ResolvedServer? resolved;



  final Map<String, dynamic>? templateWrapper;



  final String canonicalDescription;



  final List<OutboundOption> outboundOptions;


  final List<String> dnsServerTags;




  final List<DnsMemberOption> dnsMemberOptions;




  final List<TailscaleEndpointOption> tailscaleEndpoints;



  bool get isNew => resolved == null;
  ServerKind get kind => resolved?.kind ?? ServerKind.inline;
  bool get locked => resolved?.locked ?? false;
  String get lockedByLabel => resolved?.lockedByLabel ?? '';
  ServerKind? get overrides => resolved?.overrides;
  bool get isUserOnly => resolved?.isUserOnly ?? true;
  List<WizardVar> get vars => resolved?.vars ?? const [];



  late final TextEditingController tagCtrl;
  late final TextEditingController descCtrl;
  late final TextEditingController bodyCtrl;



  late final TextEditingController addressCtrl;
  late final TextEditingController portCtrl;
  late final TextEditingController pathCtrl;
  late final TextEditingController sniCtrl;


  late final TextEditingController errorTtlCtrl;
  late final TextEditingController winTtlCtrl;

  late bool _enabled;
  late Map<String, String> _varValues;







  late final VarValuesModel varModel;
  late Map<String, dynamic> _body;
  String? _jsonError;
  bool _disposed = false;



  bool _syncingFromJson = false;

  bool get enabled => _enabled;
  Map<String, String> get varValues => _varValues;
  String? get jsonError => _jsonError;



  String get inlineDetour {
    final d = _body['detour'];
    return d is String && d.isNotEmpty ? d : kDirectOutboundTag;
  }




  String? get serverMode {
    final t = _body['type'];
    return t is String && kDnsServerModes.contains(t) ? t : null;
  }






  bool get isGroup => serverMode == 'group';




  bool get isTailscale => serverMode == 'tailscale';


  String get tailscaleEndpoint => _body['endpoint']?.toString() ?? '';




  bool get acceptDefaultResolvers => _body['accept_default_resolvers'] == true;


  String get rawServerType => _body['type']?.toString() ?? '';



  bool get isHostnameAddress {
    final addr = _body['server']?.toString() ?? '';
    if (addr.isEmpty) return false;
    return InternetAddress.tryParse(addr) == null;
  }

  String get domainResolver => _body['domain_resolver']?.toString() ?? '';

  void _init() {
    final r = resolved;
    final ref = initialRef;
    tagCtrl = TextEditingController(text: r?.tag ?? ref.tag);
    descCtrl = TextEditingController(
      text: r?.description ?? ref.description ?? '',
    );
    _enabled = ref.enabled;
    _varValues = ref is DnsServerTemplate
        ? Map<String, String>.of(ref.varValues)
        : <String, String>{};


    varModel = VarValuesModel({
      for (final v in vars) v.name: _varValues[v.name] ?? v.defaultValue,
    });


    Map<String, dynamic> body;
    if (kind == ServerKind.inline) {
      final src = r != null
          ? r.body
          : (ref is DnsServerInline ? ref.body : const <String, dynamic>{});
      body = Map<String, dynamic>.from(src);
      _stripRefLevelFields(body);
    } else {
      body = const {};
    }
    _body = body;
    bodyCtrl = TextEditingController(
      text: kind == ServerKind.inline ? _encodeBodyWithTag() : '',
    );
    addressCtrl = TextEditingController(
      text: _body['server']?.toString() ?? '',
    );
    portCtrl = TextEditingController(
      text: _body['server_port'] is int ? '${_body['server_port']}' : '',
    );
    pathCtrl = TextEditingController(text: _body['path']?.toString() ?? '');
    final tls = _body['tls'];
    sniCtrl = TextEditingController(
      text: tls is Map ? (tls['server_name']?.toString() ?? '') : '',
    );

    errorTtlCtrl = TextEditingController(
      text: _body['error_ttl']?.toString() ?? '',
    );
    winTtlCtrl = TextEditingController(
      text: _body['win_ttl']?.toString() ?? '',
    );
    tagCtrl.addListener(_onTagChanged);
    descCtrl.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (_disposed) return;
    notifyListeners();
  }




  void _onTagChanged() {
    if (_disposed) return;
    if (kind == ServerKind.inline && !_syncingFromJson) {
      _syncJsonFromBody();
    }
    notifyListeners();
  }



  String _encodeBodyWithTag() => const JsonEncoder.withIndent(
    '  ',
  ).convert({'tag': tagCtrl.text.trim(), ..._body});

  @override
  void dispose() {
    _disposed = true;
    varModel.dispose();
    tagCtrl
      ..removeListener(_onTagChanged)
      ..dispose();
    descCtrl
      ..removeListener(_onTextChanged)
      ..dispose();
    bodyCtrl.dispose();
    addressCtrl.dispose();
    portCtrl.dispose();
    pathCtrl.dispose();
    sniCtrl.dispose();
    errorTtlCtrl.dispose();
    winTtlCtrl.dispose();
    super.dispose();
  }



  void setEnabled(bool v) {
    if (_enabled == v) return;
    _enabled = v;
    notifyListeners();
  }



  void setVarValue(String name, String value) {
    WizardVar? decl;
    for (final v in vars) {
      if (v.name == name) {
        decl = v;
        break;
      }
    }
    final stored = recordVarValueToStore(
      value,
      decl == null
          ? null
          : RecordVarDecl(name: decl.name, defaultValue: decl.defaultValue),
    );
    if (stored == null) {
      _varValues.remove(name);
    } else {
      _varValues[name] = stored;
    }
    notifyListeners();
  }




  void setInlineDetour(String tag) {
    if (tag == kDirectOutboundTag || tag.isEmpty) {
      _body.remove('detour');
    } else {
      _body['detour'] = tag;
    }
    _syncJsonFromBody();
    notifyListeners();
  }














  void setServerMode(String mode) {
    if (!kDnsServerModes.contains(mode)) return;
    final old = serverMode;
    if (old == mode) return;
    _body['type'] = mode;


    if (old == 'group') {
      _body
        ..remove('servers')
        ..remove('mode')
        ..remove('error_ttl')
        ..remove('win_ttl');
      errorTtlCtrl.text = '';
      winTtlCtrl.text = '';
    }
    if (old == 'tailscale') {
      _body
        ..remove('endpoint')
        ..remove('accept_default_resolvers');
    }
    if (kDnsAddresslessModes.contains(mode)) {


      _body
        ..remove('server')
        ..remove('server_port')
        ..remove('path')
        ..remove('tls')
        ..remove('domain_resolver')
        ..remove('detour');
      if (mode == 'group') {
        _body['servers'] = _body['servers'] is List
            ? _body['servers']
            : <String>[];
      }
      addressCtrl.text = '';
      portCtrl.text = '';
      pathCtrl.text = '';
      sniCtrl.text = '';
      _syncJsonFromBody();
      notifyListeners();
      return;
    }


    final port = _body['server_port'];
    if (old != null && (port == null || port == defaultDnsPort(old))) {
      _body.remove('server_port');
      portCtrl.text = '';
    }
    if (!kDnsPathModes.contains(mode)) _body.remove('path');
    if (mode == 'udp') _body.remove('tls');
    if (!kDnsPathModes.contains(mode)) pathCtrl.text = '';
    if (mode == 'udp') sniCtrl.text = '';
    _syncJsonFromBody();
    notifyListeners();
  }




  List<String> get groupMembers => [
    for (final m in (_body['servers'] as List<dynamic>? ?? const []))
      if (m is String && m.isNotEmpty) m,
  ];


  String get groupMode {
    final m = _body['mode'];
    return m is String && kDnsGroupModes.contains(m) ? m : 'stable';
  }

  String get groupErrorTtl => _body['error_ttl']?.toString() ?? '';
  String get groupWinTtl => _body['win_ttl']?.toString() ?? '';



  bool get groupErrorTtlInvalid => !isValidDnsDuration(errorTtlCtrl.text);
  bool get groupWinTtlInvalid => !isValidDnsDuration(winTtlCtrl.text);

  void toggleGroupMember(String tag, bool on) {
    if (tag.isEmpty || tag == tagCtrl.text.trim()) return;
    final members = groupMembers;
    if (on && !members.contains(tag)) {
      members.add(tag);
    } else if (!on) {
      members.remove(tag);
    } else {
      return;
    }
    _body['servers'] = members;
    _syncJsonFromBody();
    notifyListeners();
  }


  void setGroupMode(String mode) {
    if (!kDnsGroupModes.contains(mode) || groupMode == mode) return;
    if (mode == 'stable') {
      _body.remove('mode');
    } else {
      _body['mode'] = mode;
    }
    _syncJsonFromBody();
    notifyListeners();
  }



  void onErrorTtlChanged(String raw) {
    final v = raw.trim();
    if (v.isEmpty || !isValidDnsDuration(v)) {
      _body.remove('error_ttl');
    } else {
      _body['error_ttl'] = v;
    }
    _syncJsonFromBody();
    notifyListeners();
  }

  void onWinTtlChanged(String raw) {
    final v = raw.trim();
    if (v.isEmpty || !isValidDnsDuration(v)) {
      _body.remove('win_ttl');
    } else {
      _body['win_ttl'] = v;
    }
    _syncJsonFromBody();
    notifyListeners();
  }









  void setTailscaleEndpoint(String tag) {
    final t = tag.trim();
    if (t.isEmpty) {
      _body.remove('endpoint');
    } else {
      _body['endpoint'] = t;
    }
    _syncJsonFromBody();
    notifyListeners();
  }



  void setAcceptDefaultResolvers(bool v) {
    if (v) {
      _body['accept_default_resolvers'] = true;
    } else {
      _body.remove('accept_default_resolvers');
    }
    _syncJsonFromBody();
    notifyListeners();
  }






  void onAddressChanged(String raw) {
    var addr = raw.trim();
    if (addr.startsWith('https://')) {
      final uri = Uri.tryParse(addr);
      if (uri != null && uri.host.isNotEmpty) {
        addr = uri.host;
        addressCtrl.text = addr;
        addressCtrl.selection = TextSelection.collapsed(offset: addr.length);
        if (uri.path.isNotEmpty && uri.path != '/') {
          _body['path'] = uri.path;
          pathCtrl.text = uri.path;
        }
        if (!kDnsPathModes.contains(serverMode)) setServerMode('https');
      }
    }
    if (addr.isEmpty) {
      _body.remove('server');
    } else {
      _body['server'] = addr;
    }
    if (isHostnameAddress) {
      if (domainResolver.isEmpty) {
        final def = dnsServerTags.contains('google_udp')
            ? 'google_udp'
            : (dnsServerTags.isNotEmpty ? dnsServerTags.first : '');
        if (def.isNotEmpty) _body['domain_resolver'] = def;
      }
    } else {
      _body.remove('domain_resolver');
    }
    _syncJsonFromBody();
    notifyListeners();
  }


  void onPortChanged(String raw) {
    final port = int.tryParse(raw.trim());
    if (port == null || port < 1 || port > 65535) {
      _body.remove('server_port');
    } else {
      _body['server_port'] = port;
    }
    _syncJsonFromBody();
    notifyListeners();
  }


  void onPathChanged(String raw) {
    final p = raw.trim();
    if (p.isEmpty) {
      _body.remove('path');
    } else {
      _body['path'] = p.startsWith('/') ? p : '/$p';
    }
    _syncJsonFromBody();
    notifyListeners();
  }



  void onSniChanged(String raw) {
    final sni = raw.trim();
    if (sni.isEmpty) {
      _body.remove('tls');
    } else {
      _body['tls'] = {'enabled': true, 'server_name': sni};
    }
    _syncJsonFromBody();
    notifyListeners();
  }


  void setDomainResolver(String tag) {
    if (tag.isEmpty) {
      _body.remove('domain_resolver');
    } else {
      _body['domain_resolver'] = tag;
    }
    _syncJsonFromBody();
    notifyListeners();
  }

  void _syncJsonFromBody() {
    bodyCtrl.text = _encodeBodyWithTag();
    _jsonError = null;
  }



  void _syncFormFromBody() {
    final addr = _body['server']?.toString() ?? '';
    if (addressCtrl.text != addr) addressCtrl.text = addr;
    final port = _body['server_port'] is int ? '${_body['server_port']}' : '';
    if (portCtrl.text != port) portCtrl.text = port;
    final path = _body['path']?.toString() ?? '';
    if (pathCtrl.text != path) pathCtrl.text = path;
    final tls = _body['tls'];
    final sni = tls is Map ? (tls['server_name']?.toString() ?? '') : '';
    if (sniCtrl.text != sni) sniCtrl.text = sni;

    final ettl = _body['error_ttl']?.toString() ?? '';
    if (errorTtlCtrl.text != ettl) errorTtlCtrl.text = ettl;
    final wttl = _body['win_ttl']?.toString() ?? '';
    if (winTtlCtrl.text != wttl) winTtlCtrl.text = wttl;



  }








  void onBodyTextChanged(String text) {
    try {
      final parsed = jsonDecode(text);
      if (parsed is! Map<String, dynamic>) {
        _jsonError = 'Body must be a JSON object';
      } else {
        final jsonTag = parsed['tag']?.toString().trim() ?? '';
        if (jsonTag.isNotEmpty && jsonTag != tagCtrl.text.trim()) {
          _syncingFromJson = true;
          tagCtrl.text = jsonTag;
          _syncingFromJson = false;
        }
        parsed.remove('tag');
        _stripRefLevelFields(parsed);
        _body = parsed;
        _jsonError = null;
        _syncFormFromBody();
      }
    } catch (e) {
      _jsonError = 'Invalid JSON';
    }
    notifyListeners();
  }





  DnsServerRef snapshot() {
    final desc = descCtrl.text.trim();


    final override =
        desc.isNotEmpty && desc != canonicalDescription ? desc : null;
    return switch (kind) {
      ServerKind.inline => DnsServerInline(
          enabled: _enabled,
          tag: tagCtrl.text.trim(),
          description: desc.isNotEmpty ? desc : null,
          body: Map<String, dynamic>.of(_body),
        ),
      ServerKind.template => DnsServerTemplate(
          enabled: _enabled,
          tag: initialRef.tag,
          varValues: Map<String, String>.of(_varValues),
          description: override,
        ),
      ServerKind.preset => DnsServerPreset(
          enabled: _enabled,
          tag: initialRef.tag,
          presetId: switch (initialRef) {
            DnsServerPreset(:final presetId) => presetId,
            _ => '',
          },
          description: override,
        ),
    };
  }

  bool isDirty() => snapshot() != initialRef;
}



void _stripRefLevelFields(Map<String, dynamic> body) {
  body
    ..remove('tag')
    ..remove('description')
    ..remove('enabled')
    ..remove('_origin')
    ..remove('_kind')
    ..remove('_overrides')
    ..remove('_preset_label')
    ..remove('_preset_id');
}



class DnsServerEditScope extends InheritedNotifier<DnsServerEditController> {
  const DnsServerEditScope({
    super.key,
    required DnsServerEditController super.notifier,
    required super.child,
  });

  static DnsServerEditController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<DnsServerEditScope>();
    assert(scope != null, 'DnsServerEditScope.of: no scope in context');
    return scope!.notifier!;
  }
}
