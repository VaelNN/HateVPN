import '../models/direction.dart';
import '../models/config_node.dart';
import 'selector_info.dart';











const int kMaxRuntimeHops = 12;



const Set<String> _kGroupTypes = {'selector', 'urltest'};


class RuntimeHop {
  const RuntimeHop({
    required this.tag,
    required this.type,
    this.direction,
    this.viaSelection = false,
  });


  final String tag;


  final String type;


  final Direction? direction;



  final bool viaSelection;

  bool get isDirection => direction != null;


  bool get isUnknown => type.isEmpty;


  bool get isGroup => _kGroupTypes.contains(type);
}





Direction? directionForTag(String tag, List<Direction> directions) {
  for (final c in directions) {
    if (tag == c.tag || tag == c.autoTag) return c;
  }
  return null;
}










List<RuntimeHop> runtimeChainOf(
  String tag,
  ParsedConfig config, {
  required List<Direction> directions,
  String? Function(String tag)? selectedOf,
}) {
  final selected = selectedOf ?? SelectorInfo.I.selectedOf;
  final hops = <RuntimeHop>[];
  final seen = <String>{};
  String? cur = tag;
  var via = false;


  while (cur != null &&
      cur.isNotEmpty &&
      hops.length < kMaxRuntimeHops &&
      seen.add(cur)) {
    final node = config[cur];
    hops.add(RuntimeHop(
      tag: cur,
      type: node?.type ?? '',
      direction: directionForTag(cur, directions),
      viaSelection: via,
    ));
    if (node == null) break;
    if (_kGroupTypes.contains(node.type)) {
      cur = selected(cur);
      via = true;
    } else {
      cur = node.detour;
      via = false;
    }
  }


  return hops.reversed.toList();
}
