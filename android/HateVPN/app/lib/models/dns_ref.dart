




















import 'package:collection/collection.dart';

const _eq = DeepCollectionEquality();




sealed class DnsServerRef {
  const DnsServerRef({
    required this.enabled,
    this.description,
  });

  final bool enabled;



  String get tag;

  final String? description;


  String get kind;


  DnsServerRef withEnabled(bool enabled);
}

class DnsServerInline extends DnsServerRef {
  const DnsServerInline({
    required super.enabled,
    required this.tag,
    required this.body,
    super.description,
  });

  @override
  final String tag;


  final Map<String, dynamic> body;

  @override
  String get kind => 'inline';

  @override
  DnsServerInline withEnabled(bool enabled) => copyWith(enabled: enabled);

  DnsServerInline copyWith({
    bool? enabled,
    String? tag,
    Map<String, dynamic>? body,
    String? description,
  }) =>
      DnsServerInline(
        enabled: enabled ?? this.enabled,
        tag: tag ?? this.tag,
        body: body ?? this.body,
        description: description ?? this.description,
      );

  @override
  bool operator ==(Object other) =>
      other is DnsServerInline &&
      other.enabled == enabled &&
      other.tag == tag &&
      other.description == description &&
      _eq.equals(other.body, body);

  @override
  int get hashCode =>
      Object.hash('inline', enabled, tag, description, _eq.hash(body));
}












class DnsServerPreset extends DnsServerRef {
  const DnsServerPreset({
    required super.enabled,
    required String tag,
    String presetId = '',
    super.description,
  })  : _tag = tag,
        _presetId = presetId;

  final String _tag;
  final String _presetId;

  @override
  String get tag => _presetId.isEmpty || _tag.startsWith('$_presetId:')
      ? _tag
      : '$_presetId:$_tag';




  String get presetId =>
      _presetId.isNotEmpty ? _presetId : presetIdOfDnsServerTag(_tag);

  @override
  String get kind => 'preset';

  @override
  DnsServerPreset withEnabled(bool enabled) => copyWith(enabled: enabled);

  DnsServerPreset copyWith({
    bool? enabled,
    String? tag,
    String? presetId,
    String? description,
  }) =>
      DnsServerPreset(
        enabled: enabled ?? this.enabled,
        tag: tag ?? this.tag,
        presetId: presetId ?? this.presetId,
        description: description ?? this.description,
      );

  @override
  bool operator ==(Object other) =>
      other is DnsServerPreset &&
      other.enabled == enabled &&
      other.tag == tag &&
      other.presetId == presetId &&
      other.description == description;

  @override
  int get hashCode =>
      Object.hash('preset', enabled, tag, presetId, description);
}




String presetIdOfDnsServerTag(String tag) {
  final at = tag.indexOf(':');
  return at <= 0 ? '' : tag.substring(0, at);
}

class DnsServerTemplate extends DnsServerRef {
  const DnsServerTemplate({
    required super.enabled,
    required this.tag,
    this.varValues = const {},
    super.description,
  });

  @override
  final String tag;

  final Map<String, String> varValues;

  @override
  String get kind => 'template';

  @override
  DnsServerTemplate withEnabled(bool enabled) => copyWith(enabled: enabled);

  DnsServerTemplate copyWith({
    bool? enabled,
    String? tag,
    Map<String, String>? varValues,
    String? description,
  }) =>
      DnsServerTemplate(
        enabled: enabled ?? this.enabled,
        tag: tag ?? this.tag,
        varValues: varValues ?? this.varValues,
        description: description ?? this.description,
      );

  @override
  bool operator ==(Object other) =>
      other is DnsServerTemplate &&
      other.enabled == enabled &&
      other.tag == tag &&
      other.description == description &&
      _eq.equals(other.varValues, varValues);

  @override
  int get hashCode =>
      Object.hash('template', enabled, tag, description, _eq.hash(varValues));
}




DnsServerInline retargetDnsServerDetour(
  DnsServerInline server,
  Map<String, String> retarget,
) {
  final detour = server.body['detour'];
  final to = detour is String ? retarget[detour.trim()] : null;
  if (to == null) return server;
  return server.copyWith(body: {...server.body, 'detour': to});
}








sealed class DnsRuleRef {
  const DnsRuleRef();

  String get kind;


  bool get enabled;


  DnsRuleRef withEnabled(bool enabled);
}

class DnsRuleInline extends DnsRuleRef {
  const DnsRuleInline({
    required this.name,
    required this.rule,
    this.enabled = true,
  });
  final String name;
  final Map<String, dynamic> rule;



  @override
  final bool enabled;

  @override
  String get kind => 'inline';

  @override
  DnsRuleInline withEnabled(bool enabled) => copyWith(enabled: enabled);

  DnsRuleInline copyWith({
    String? name,
    Map<String, dynamic>? rule,
    bool? enabled,
  }) =>
      DnsRuleInline(
        name: name ?? this.name,
        rule: rule ?? this.rule,
        enabled: enabled ?? this.enabled,
      );

  @override
  bool operator ==(Object other) =>
      other is DnsRuleInline &&
      other.name == name &&
      other.enabled == enabled &&
      _eq.equals(other.rule, rule);

  @override
  int get hashCode => Object.hash('inline', name, enabled, _eq.hash(rule));
}





class DnsRuleSrs extends DnsRuleRef {
  const DnsRuleSrs({
    required this.name,
    required this.id,
    this.body,
    this.server,
    this.rule,
    this.srsUrl,
    this.enabled = true,
  });
  final String name;
  final String id;
  final Map<String, dynamic>? body;
  final String? server;
  final Map<String, dynamic>? rule;
  final String? srsUrl;

  @override
  final bool enabled;

  @override
  String get kind => 'srs';

  @override
  DnsRuleSrs withEnabled(bool enabled) => copyWith(enabled: enabled);

  DnsRuleSrs copyWith({
    String? name,
    String? id,
    Map<String, dynamic>? body,
    String? server,
    Map<String, dynamic>? rule,
    String? srsUrl,
    bool? enabled,
  }) =>
      DnsRuleSrs(
        name: name ?? this.name,
        id: id ?? this.id,
        body: body ?? this.body,
        server: server ?? this.server,
        rule: rule ?? this.rule,
        srsUrl: srsUrl ?? this.srsUrl,
        enabled: enabled ?? this.enabled,
      );

  @override
  bool operator ==(Object other) =>
      other is DnsRuleSrs &&
      other.name == name &&
      other.id == id &&
      other.server == server &&
      other.srsUrl == srsUrl &&
      other.enabled == enabled &&
      _eq.equals(other.body, body) &&
      _eq.equals(other.rule, rule);

  @override
  int get hashCode => Object.hash('srs', name, id, server, srsUrl, enabled,
      _eq.hash(body), _eq.hash(rule));
}

class DnsRulePreset extends DnsRuleRef {
  const DnsRulePreset({required this.presetId, this.enabled = true});
  final String presetId;



  @override
  final bool enabled;

  @override
  String get kind => 'preset';

  @override
  DnsRulePreset withEnabled(bool enabled) => copyWith(enabled: enabled);

  DnsRulePreset copyWith({String? presetId, bool? enabled}) => DnsRulePreset(
      presetId: presetId ?? this.presetId, enabled: enabled ?? this.enabled);

  @override
  bool operator ==(Object other) =>
      other is DnsRulePreset &&
      other.presetId == presetId &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash('preset', presetId, enabled);
}

class DnsRuleTemplate extends DnsRuleRef {
  const DnsRuleTemplate({required this.name, this.enabled = true});
  final String name;

  @override
  final bool enabled;

  @override
  String get kind => 'template';

  @override
  DnsRuleTemplate withEnabled(bool enabled) => copyWith(enabled: enabled);

  DnsRuleTemplate copyWith({String? name, bool? enabled}) => DnsRuleTemplate(
      name: name ?? this.name, enabled: enabled ?? this.enabled);

  @override
  bool operator ==(Object other) =>
      other is DnsRuleTemplate &&
      other.name == name &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash('template', name, enabled);
}
