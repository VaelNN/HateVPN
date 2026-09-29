import '../models/config_node.dart';
import '../vpn/cc_channel.dart' show CcTailscaleStatus;
import 'contract/body_sanitizer.dart' show exitCapableByRegistry;









const String kNetworksLabel = 'NETWORKS';




const String kNetworksDirectionValue = '\u0001networks';

final Expando<List<String>> _cache = Expando<List<String>>('networks579');



List<String> networksNodeTags(ParsedConfig model) =>
    _cache[model] ??= List.unmodifiable([
      for (final n in model.nodes)
        if (n.kind == 'endpoint' &&
            n.type == 'tailscale' &&
            !exitCapableByRegistry(n.raw))
          n.tag,
    ]);


enum TailnetStateKind {

  none,


  starting,


  running,


  signInNeeded,


  stopped,


  other,
}

class TailnetRowState {
  const TailnetRowState(this.kind, [this.text = '']);

  final TailnetStateKind kind;



  final String text;


  bool get isWarning =>
      kind == TailnetStateKind.signInNeeded || kind == TailnetStateKind.stopped;

  @override
  bool operator ==(Object other) =>
      other is TailnetRowState && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => 'TailnetRowState($kind, $text)';
}


TailnetRowState tailnetRowState({
  required bool tunnelUp,
  required String tag,
  required Map<String, CcTailscaleStatus> byTag,
}) {
  if (!tunnelUp) return const TailnetRowState(TailnetStateKind.none);
  final s = byTag[tag];
  if (s == null) return const TailnetRowState(TailnetStateKind.starting);
  switch (s.backendState) {
    case 'Running':
      return const TailnetRowState(TailnetStateKind.running);
    case 'NeedsLogin':
      return const TailnetRowState(TailnetStateKind.signInNeeded);
    case 'Stopped':
      return const TailnetRowState(TailnetStateKind.stopped);
  }
  return TailnetRowState(
    TailnetStateKind.other,
    s.stateText.isNotEmpty ? s.stateText : s.backendState,
  );
}
