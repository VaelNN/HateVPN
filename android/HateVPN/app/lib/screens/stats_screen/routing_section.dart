














import '../../services/selector_info.dart';



class RoutingRow {
  const RoutingRow(this.label, this.value);
  final String label;
  final String value;
}












List<RoutingRow> routingRows({
  required String route,
  required String rule,
  required List<String> chain,
  required List<String> detour,
  String outbound = '',
  String outboundType = '',
}) {
  return [
    RoutingRow('Route', route),
    RoutingRow('Rule', rule.isNotEmpty ? rule : 'final'),


    RoutingRow('Chain', chain.join(' / ')),



    RoutingRow('Detour', foldSelectorPairs(detour).reversed.join(' → ')),
    RoutingRow('Outbound', outbound),
    RoutingRow('Outbound type', outboundType),
  ];
}
