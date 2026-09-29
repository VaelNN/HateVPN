





import '../../models/parser_config.dart' show WizardVar;




enum ServerKind {
  template,
  preset,
  inline;

  static ServerKind? tryParse(String s) {
    switch (s) {
      case 'inline':
        return ServerKind.inline;
      case 'preset':
        return ServerKind.preset;
      case 'template':
        return ServerKind.template;
    }
    return null;
  }

  String get name => toString().split('.').last;
}











class ResolvedServer {
  const ResolvedServer({
    required this.kind,
    required this.tag,
    required this.description,
    required this.enabled,
    required this.body,
    this.overrides,
    this.presetLabel,
    this.presetId = '',
    this.vars = const [],
    this.varValues = const {},
    this.usedByRule,
  });

  final ServerKind kind;
  final String tag;
  final String description;
  final bool enabled;
  final Map<String, dynamic> body;
  final ServerKind? overrides;
  final String? presetLabel;



  final String presetId;




  final List<WizardVar> vars;


  final Map<String, String> varValues;



  final String? usedByRule;

  bool get isOverridden => kind == ServerKind.inline && overrides != null;
  bool get isUserOnly => kind == ServerKind.inline && overrides == null;



  bool get lockedByPreset =>
      kind == ServerKind.preset || overrides == ServerKind.preset;



  bool get locked => lockedByPreset || usedByRule != null;


  String get lockedByLabel =>
      lockedByPreset ? (presetLabel ?? 'preset') : (usedByRule ?? '');
}
