import 'server_list.dart';
import 'source_chain.dart';


























sealed class SourceEntry {
  const SourceEntry();






  String get sourceKey;



  String get kind;


  bool get enabled;


  String get displayLabel;
}


final class ContainerEntry extends SourceEntry {
  const ContainerEntry(this.list);

  final ServerList list;

  @override
  String get sourceKey => sourceKeyForIdOf(list.id);



  @override
  String get kind => switch (list) {
        SubscriptionServers() => 'subscription',
        UserServer() => 'server',
        FolderServers() => 'folder',
      };

  @override
  bool get enabled => list.enabled;

  @override
  String get displayLabel => list.name;
}



final class ChainEntry extends SourceEntry {
  const ChainEntry(this.chain);

  final SourceChain chain;

  @override
  String get sourceKey => sourceKeyForChainOf(chain.tag);

  @override
  String get kind => kSourceKindChainKey;

  @override
  bool get enabled => chain.enabled;

  @override
  String get displayLabel => chain.displayLabel;
}








final class OpaqueEntry extends SourceEntry {
  const OpaqueEntry(this.record, this.slot);


  final Map<String, dynamic> record;

  final int slot;

  @override
  String get sourceKey => 'raw:$slot';

  @override
  String get kind => '${record['kind'] ?? ''}';

  @override
  bool get enabled => false;

  @override
  String get displayLabel => '';
}






String sourceKeyForIdOf(String id) => 'id:$id';


String sourceKeyForChainOf(String tag) => 'chain:$tag';



const String kSourceKindChainKey = 'chain';
