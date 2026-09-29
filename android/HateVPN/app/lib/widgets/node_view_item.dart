import '../models/node_warning.dart';
import '../services/networks_direction.dart' show TailnetRowState;












class NodeViewItem {
  const NodeViewItem({
    required this.tag,
    required this.active,
    required this.highlighted,
    required this.delay,
    this.delayIsForeign = false,
    required this.pingBusy,
    required this.tunnelUp,
    required this.busy,
    required this.urltestNow,
    required this.hasDetour,
    required this.protocolLabel,
    this.outboundType,
    this.isDirectionAuto = false,
    this.autoGroupLabel,
    this.matches = true,
    this.isSickRoot = false,
    this.notificationWarnings,
    this.endpointState = '',
    this.tailnetState,
  });


  final String tag;


  final bool active;


  final bool highlighted;


  final int? delay;






  final bool delayIsForeign;


  final bool pingBusy;








  final String endpointState;


  final bool tunnelUp;


  final bool busy;




  final String? urltestNow;



  final bool hasDetour;





  final bool isDirectionAuto;




  final String? autoGroupLabel;



  final String? protocolLabel;




  final String? outboundType;





  final bool matches;





  final bool isSickRoot;




  final List<NodeWarning>? notificationWarnings;




  final TailnetRowState? tailnetState;
}
