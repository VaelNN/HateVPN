import '../services/builder/node_link_resolve.dart';
import '../services/builder/rule_set_registry.dart';
import '../services/builder/source_replace_build.dart' show ReplacePlan;
import 'node_spec.dart';
import 'singbox_entry.dart';
import 'template_vars.dart';














abstract class EmitContext {
  TemplateVars get vars;



  String allocateTag(String baseTag);


  void addEntry(SingboxEntry entry);


  void addToSelectorTagList(SingboxEntry entry);


  void addToAutoList(SingboxEntry entry);






  bool get passiveCheck => false;




  RuleSetRegistry get ruleSets;





  void noteEmitted(NodeSpec node, String finalTag) {}




  void noteEmittedAlias(String finalTag, NodeSpec owner) {}



  void warn(String line) {}




  void addReplacePlan(ReplacePlan plan) {}




  bool isReplaceBlocked(String listId) => false;


  String get coreVersion => '';




  NodeLinkTargets? get linkTargets => null;




  void deferDetour(DeferredDetour detour) {}
}
