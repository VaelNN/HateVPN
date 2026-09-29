import '../../../models/source_chain.dart';









Map<String, Object?> serializeChain(SourceChain c) => {
      'tag': c.tag,
      'label': c.label,
      'enabled': c.enabled,
      ...c.toCanonJson(),
    };
