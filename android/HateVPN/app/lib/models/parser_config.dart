
class WizardTemplate {
  WizardTemplate({
    required this.parserConfig,
    required this.groupTemplates,
    required this.vars,
    required this.varSections,
    required this.config,
    required this.selectableRules,
    required this.dnsOptions,
    required this.pingOptions,
    required this.speedTestOptions,
    DnsOptionsModel? dnsOptionsModel,
    PingOptionsModel? pingOptionsModel,
    SpeedTestOptionsModel? speedTestOptionsModel,
  })  : dnsOptionsModel =
            dnsOptionsModel ?? DnsOptionsModel.fromJson(dnsOptions),
        pingOptionsModel =
            pingOptionsModel ?? PingOptionsModel.fromJson(pingOptions),
        speedTestOptionsModel = speedTestOptionsModel ??
            SpeedTestOptionsModel.fromJson(speedTestOptions);

  final ParserConfigBlock parserConfig;
  final GroupTemplates groupTemplates;
  final List<WizardVar> vars;
  final Map<String, dynamic> config;
  final List<SelectableRule> selectableRules;
  final Map<String, dynamic> dnsOptions;
  final Map<String, dynamic> pingOptions;
  final Map<String, dynamic> speedTestOptions;





  final DnsOptionsModel dnsOptionsModel;
  final PingOptionsModel pingOptionsModel;
  final SpeedTestOptionsModel speedTestOptionsModel;

  final List<VarSection> varSections;





  List<WizardVar> varsFor(String chapter) => vars
      .where((v) => v.chapter == chapter && v.wizardUI != 'hidden')
      .toList(growable: false);



  List<VarSection> sectionsFor(String chapter) =>
      varSections.where((s) => s.chapter == chapter).toList(growable: false);




  WizardVar? globalVar(String name) {
    for (final v in vars) {
      if (v.name == name && !v.isRef) return v;
    }
    return null;
  }

  factory WizardTemplate.fromJson(Map<String, dynamic> json) {
    final pcJson = json['parser_config'] as Map<String, dynamic>? ?? {};
    final rulesJson = json['selectable_rules'] as List<dynamic>? ?? [];

    final groupTemplatesJson =
        json['group_templates'] as Map<String, dynamic>? ?? const {};
    final defaultDirectionsJson =
        json['default_directions'] as List<dynamic>? ?? const [];



    final allVars = <WizardVar>[];
    final sections = <VarSection>[];
    final sectionsJson = json['sections'] as List<dynamic>? ?? [];
    for (final s in sectionsJson.whereType<Map<String, dynamic>>()) {
      final name = s['name'] as String? ?? '';
      final chapter = s['chapter'] as String? ?? 'core';
      final description = s['description'] as String? ?? '';
      sections.add(VarSection(
        title: name,
        id: s['id'] as String? ?? '',
        description: description,
        chapter: chapter,
      ));
      final varsArr = s['vars'] as List<dynamic>? ?? [];
      for (final v in varsArr.whereType<Map<String, dynamic>>()) {
        if (!v.containsKey('name')) continue;
        allVars.add(WizardVar.fromJson(v, section: name, chapter: chapter));
      }
    }

    return WizardTemplate(
      parserConfig: ParserConfigBlock.fromJson(pcJson),
      groupTemplates:
          GroupTemplates.fromJson(groupTemplatesJson, defaultDirectionsJson),
      vars: allVars,
      varSections: sections,
      config: json['config'] as Map<String, dynamic>? ?? {},
      selectableRules: rulesJson
          .map((e) => SelectableRule.fromJson(e as Map<String, dynamic>))
          .toList(),
      dnsOptions: json['dns_options'] as Map<String, dynamic>? ?? {},
      pingOptions: json['ping_options'] as Map<String, dynamic>? ?? {},
      speedTestOptions: json['speed_test_options'] as Map<String, dynamic>? ?? {},
    );
  }
}


class ParserConfigBlock {
  ParserConfigBlock({
    this.version = 5,
    this.reload = '12h',
  });

  final int version;
  final String reload;

  factory ParserConfigBlock.fromJson(Map<String, dynamic> json) {
    final parser = json['parser'] as Map<String, dynamic>? ?? {};
    return ParserConfigBlock(
      version: json['version'] as int? ?? 5,
      reload: parser['reload'] as String? ?? '12h',
    );
  }
}











class TemplateDnsServerEntry {
  TemplateDnsServerEntry({
    required this.tag,
    this.description = '',
    this.enabled = true,
    this.vars = const [],
    this.wrapper = const {},
  });

  final String tag;
  final String description;
  final bool enabled;
  final List<WizardVar> vars;



  final Map<String, dynamic> wrapper;


  static TemplateDnsServerEntry? fromWrapper(Map<String, dynamic> w) {
    final server = w['server'];
    final tag = server is Map ? server['tag'] : null;
    if (tag is! String || tag.isEmpty) return null;
    return TemplateDnsServerEntry(
      tag: tag,
      description: w['description']?.toString() ?? '',
      enabled: w['enabled'] as bool? ?? true,
      vars: (w['vars'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((v) => WizardVar.fromJson(v))
          .toList(),
      wrapper: w,
    );
  }
}



class DnsOptionsModel {
  DnsOptionsModel({this.servers = const []});

  final List<TemplateDnsServerEntry> servers;


  Map<String, Map<String, dynamic>> get wrappersByTag =>
      {for (final s in servers) s.tag: s.wrapper};

  factory DnsOptionsModel.fromJson(Map<String, dynamic> json) {
    final servers = <TemplateDnsServerEntry>[];
    for (final s in json['servers'] as List<dynamic>? ?? const []) {
      if (s is! Map<String, dynamic>) continue;
      final entry = TemplateDnsServerEntry.fromWrapper(s);
      if (entry != null) servers.add(entry);
    }
    return DnsOptionsModel(servers: servers);
  }
}



class PingPreset {
  PingPreset({required this.id, this.name = '', this.url = ''});

  final String id;
  final String name;
  final String url;

  factory PingPreset.fromJson(Map<String, dynamic> json) => PingPreset(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        url: json['url']?.toString() ?? '',
      );
}


class PingOptionsModel {
  PingOptionsModel({
    this.defaultUrl = '',
    this.defaultTimeoutMs = 0,
    this.presets = const [],
  });

  final String defaultUrl;
  final int defaultTimeoutMs;
  final List<PingPreset> presets;

  factory PingOptionsModel.fromJson(Map<String, dynamic> json) {
    final timeout = json['timeout_ms'];
    return PingOptionsModel(
      defaultUrl: json['url']?.toString() ?? '',
      defaultTimeoutMs: (timeout is num && timeout > 0) ? timeout.toInt() : 0,
      presets: (json['presets'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PingPreset.fromJson)
          .toList(),
    );
  }
}



class SpeedTestServer {
  SpeedTestServer({
    required this.id,
    this.name = '',
    this.downloadUrl = '',
    this.uploadUrl,
    this.uploadMethod = 'PUT',
    this.pingUrl = '',
  });

  final String id;
  final String name;
  final String downloadUrl;
  final String? uploadUrl;
  final String uploadMethod;
  final String pingUrl;

  factory SpeedTestServer.fromJson(Map<String, dynamic> json) =>
      SpeedTestServer(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        downloadUrl: json['download_url']?.toString() ?? '',
        uploadUrl: json['upload_url']?.toString(),
        uploadMethod: json['upload_method']?.toString() ?? 'PUT',
        pingUrl: json['ping_url']?.toString() ?? '',
      );
}


class SpeedTestOptionsModel {
  SpeedTestOptionsModel({
    this.servers = const [],
    this.streamOptions = const [],
    this.defaultStreams,
  });

  final List<SpeedTestServer> servers;
  final List<int> streamOptions;
  final int? defaultStreams;

  factory SpeedTestOptionsModel.fromJson(Map<String, dynamic> json) =>
      SpeedTestOptionsModel(
        servers: (json['servers'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SpeedTestServer.fromJson)
            .toList(),
        streamOptions: (json['stream_options'] as List<dynamic>? ?? const [])
            .whereType<num>()
            .map((n) => n.toInt())
            .toList(),
        defaultStreams: (json['default_streams'] as num?)?.toInt(),
      );
}



















class MagicNode {
  MagicNode({
    required this.role,
    required this.title,
    required this.source,
    this.tag,
    this.tpl,
  });

  final String role;
  final String title;
  final String source;
  final String? tag;
  final String? tpl;

  factory MagicNode.fromJson(String role, Map<String, dynamic> json) {
    return MagicNode(
      role: role,
      title: json['title'] as String? ?? '',
      source: json['source'] as String? ?? 'preset',
      tag: json['tag'] as String?,
      tpl: json['tpl'] as String?,
    );
  }
}





class DirectionTemplate {
  DirectionTemplate({
    this.type = 'selector',
    this.include = const [],
    this.options = const {},
  });

  final String type;
  final List<String> include;
  final Map<String, dynamic> options;

  factory DirectionTemplate.fromJson(Map<String, dynamic> json) {
    return DirectionTemplate(
      type: json['type'] as String? ?? 'selector',
      include: (json['include'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      options: json['options'] as Map<String, dynamic>? ?? const {},
    );
  }
}




class AutoTemplate {
  AutoTemplate({this.type = 'urltest', this.options = const {}});

  final String type;
  final Map<String, dynamic> options;

  factory AutoTemplate.fromJson(Map<String, dynamic> json) {
    return AutoTemplate(
      type: json['type'] as String? ?? 'urltest',
      options: json['options'] as Map<String, dynamic>? ?? const {},
    );
  }
}


class DefaultDirection {
  DefaultDirection({
    required this.tag,
    this.label = '',
    this.defaultEnabled = true,
  });

  final String tag;
  final String label;
  final bool defaultEnabled;

  factory DefaultDirection.fromJson(Map<String, dynamic> json) {
    return DefaultDirection(
      tag: json['tag'] as String? ?? '',
      label: json['label'] as String? ?? '',
      defaultEnabled: json['default_enabled'] as bool? ?? true,
    );
  }
}






class GroupTemplates {
  GroupTemplates({
    this.magicNodes = const {},
    DirectionTemplate? direction,
    AutoTemplate? auto,
    this.defaultDirections = const [],
  })  : direction = direction ?? DirectionTemplate(),
        auto = auto ?? AutoTemplate();

  final Map<String, MagicNode> magicNodes;
  final DirectionTemplate direction;
  final AutoTemplate auto;
  final List<DefaultDirection> defaultDirections;

  factory GroupTemplates.fromJson(
    Map<String, dynamic> groupTemplatesJson,
    List<dynamic> defaultDirectionsJson,
  ) {
    final nodesJson =
        groupTemplatesJson['magic_nodes'] as Map<String, dynamic>? ?? const {};
    final magicNodes = <String, MagicNode>{};
    for (final entry in nodesJson.entries) {
      final v = entry.value;
      if (v is Map<String, dynamic>) {
        magicNodes[entry.key] = MagicNode.fromJson(entry.key, v);
      }
    }
    return GroupTemplates(
      magicNodes: magicNodes,
      direction: DirectionTemplate.fromJson(
          groupTemplatesJson['direction'] as Map<String, dynamic>? ?? const {}),
      auto: AutoTemplate.fromJson(
          groupTemplatesJson['auto'] as Map<String, dynamic>? ?? const {}),
      defaultDirections: defaultDirectionsJson
          .whereType<Map<String, dynamic>>()
          .map(DefaultDirection.fromJson)
          .toList(),
    );
  }
}




String resolveTpl(String tpl, String parentTag) =>
    tpl.replaceAll('{parent_tag}', parentTag);







class WizardOption {
  final String value;
  final String title;
  const WizardOption({required this.value, required this.title});




  factory WizardOption.fromAny(dynamic raw) {
    if (raw is String) return WizardOption(value: raw, title: raw);
    if (raw is Map) {
      final v = raw['value']?.toString() ?? '';
      final t = (raw['title']?.toString() ?? '').trim();
      return WizardOption(value: v, title: t.isEmpty ? v : t);
    }
    return const WizardOption(value: '', title: '');
  }
}









class WizardVar {
  WizardVar({
    required this.name,
    required this.type,
    required this.defaultValue,
    this.wizardUI = 'edit',
    this.options = const [],
    this.optionsOpen = false,
    this.title = '',
    this.tooltip = '',
    this.section = '',
    this.chapter = 'core',
    this.required = true,
    this.onChange,
    this.ref = '',
  });

  final String name;





  final String
      type;
  final String defaultValue;
  final String wizardUI;






  final List<WizardOption> options;





  final bool optionsOpen;
  final String title;
  final String tooltip;
  final String section;
  final String chapter;




  final bool required;








  final Map<String, dynamic>? onChange;







  final String ref;


  bool get isRef => ref.isNotEmpty;

  bool get isEditable => wizardUI == 'edit';



  List<String> get optionValues =>
      options.map((o) => o.value).toList(growable: false);





  bool acceptsValue(String value) {
    if (options.isEmpty || optionsOpen) return true;
    final allowed = optionValues.toSet();
    if (type == 'text_list') {
      return value
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .every(allowed.contains);
    }
    return allowed.contains(value);
  }

  factory WizardVar.fromJson(
    Map<String, dynamic> json, {
    String section = '',
    String chapter = 'core',
  }) {



    final refName = json['ref'] as String? ?? '';
    if (refName.isNotEmpty) {
      return WizardVar(
        name: refName,
        type: 'text',
        defaultValue: '',
        section: section,
        chapter: chapter,
        ref: refName,
      );
    }

    var defVal = json['default_value'];
    String defaultStr;
    if (defVal is Map) {
      defaultStr = (defVal['default'] ?? defVal.values.first)?.toString() ?? '';
    } else {
      defaultStr = defVal?.toString() ?? '';
    }

    return WizardVar(
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'text',
      defaultValue: defaultStr,
      wizardUI: json['wizard_ui'] as String? ?? 'edit',
      options: (json['options'] as List<dynamic>?)
              ?.map(WizardOption.fromAny)
              .where((o) => o.value.isNotEmpty)
              .toList() ??
          const [],
      optionsOpen: json['options_open'] == true,
      title: json['title'] as String? ?? '',
      tooltip: json['tooltip'] as String? ?? '',
      section: section,
      chapter: chapter,
      required: json['required'] as bool? ?? true,


      onChange: (json['#on_change'] ?? json['on_change']) as Map<String, dynamic>?,
    );
  }
}




class VarSection {
  VarSection({
    required this.title,
    this.id = '',
    this.description = '',
    this.chapter = 'core',
  });




  final String id;
  final String title;
  final String description;
  final String chapter;
}






const int kUserRuleNumStart = 1000;
const int kUserRuleNumEnd = 1100;


const int kDefaultRuleNum = kUserRuleNumStart;











class PresetForEach {
  const PresetForEach({
    required this.nodeType,
    required this.as,
    this.filter,
  });

  final String nodeType;
  final String as;
  final Object? filter;



  static PresetForEach? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final type = raw['node_type'];
    final as = raw['as'];
    if (type is! String || type.isEmpty || as is! String || as.isEmpty) {
      return null;
    }
    return PresetForEach(nodeType: type, as: as, filter: raw['filter']);
  }
}


class SelectableRule {
  SelectableRule({
    required this.label,
    required this.presetId,
    this.description = '',
    this.defaultEnabled = false,
    this.locked = false,
    this.num = kDefaultRuleNum,
    this.isSortable = true,
    this.ruleSets = const [],
    dynamic rule,
    this.vars = const [],
    dynamic dnsRule,
    this.dnsServers = const [],
    this.forEach,
  })  : rules = _normalizeRules(rule),
        dnsRules = _normalizeRules(dnsRule);

  final String label;


  final PresetForEach? forEach;
  final String description;
  final bool defaultEnabled;



  final bool locked;









  final int num;







  final bool isSortable;

  final List<Map<String, dynamic>> ruleSets;







  final List<Map<String, dynamic>> rules;








  Map<String, dynamic> get terminalRule {
    for (final r in rules.reversed) {
      final action = r['action'];
      if (action is String && _intermediateActions.contains(action)) continue;
      if (r['outbound'] is String || action is String) return r;
    }
    return const {};
  }

  static const _intermediateActions = {'resolve', 'sniff', 'route-options'};

  static List<Map<String, dynamic>> _normalizeRules(dynamic rule) {
    if (rule is Map<String, dynamic>) return rule.isEmpty ? const [] : [rule];
    if (rule is List) {
      return rule.whereType<Map<String, dynamic>>().toList();
    }
    return const [];
  }


  final String presetId;



  final List<WizardVar> vars;






  final List<Map<String, dynamic>> dnsRules;




  final List<Map<String, dynamic>> dnsServers;









  bool get hasOutboundAffordance => vars.any((v) => v.type == 'outbound');






  bool get touchesDns => dnsRules.isNotEmpty || dnsServers.isNotEmpty;

  factory SelectableRule.fromJson(Map<String, dynamic> json) {
    final presetId = (json['preset_id'] as String?) ?? '';
    if (presetId.isEmpty) {
      throw FormatException(
        'SelectableRule "${json['ui']?['label'] ?? '<no-label>'}" missing '
        'required `preset_id` (legacy entries without preset_id are no longer '
        'supported)',
      );
    }




    final ui = json['ui'] as Map<String, dynamic>? ?? const {};
    return SelectableRule(
      label: ui['label'] as String? ?? '',
      description: ui['description'] as String? ?? '',
      defaultEnabled: ui['default'] as bool? ?? false,
      locked: ui['locked'] as bool? ?? false,
      num: ui['num'] as int? ?? kDefaultRuleNum,
      isSortable: ui['isSortable'] as bool? ?? true,
      ruleSets: (json['rule_set'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],


      rule: json['rules'] ?? json['rule'],
      presetId: presetId,
      vars: (json['vars'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map((v) => WizardVar.fromJson(v))
              .toList() ??
          const [],


      dnsRule: json['dns_rules'] ?? json['dns_rule'],
      dnsServers: (json['dns_servers'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      forEach: PresetForEach.fromJson(json['for_each']),
    );
  }
}
