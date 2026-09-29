import 'package:lxbox/services/contract/registry.dart';
import 'package:lxbox/services/parser/engine/section_loader.dart';
import 'package:lxbox/services/parser/mappers/draft_sections.dart';

import '../contract_paths.dart';









Future<void> loadEngineSections() async {
  await loadTestRegistry();
  await MapperSections.I
      .loadDrafts(dir: 'assets/contract_draft', files: kDraftFiles);
}


void unloadEngineSections() {
  MapperSections.I.resetForTesting();
  ContractRegistry.I.resetForTesting();
}
