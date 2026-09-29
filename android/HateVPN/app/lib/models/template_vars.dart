




class TemplateVars {

  final bool tlsFragment;


  final bool tlsRecordFragment;


  final bool muxEnabled;


  final String? sniOverride;

  const TemplateVars({
    this.tlsFragment = false,
    this.tlsRecordFragment = false,
    this.muxEnabled = false,
    this.sniOverride,
  });

  static const empty = TemplateVars();
}
