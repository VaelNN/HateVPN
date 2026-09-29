import '../../models/node_warning.dart';
import '../../services/l10n/locale_controller.dart';
import '../../services/parser/body_decoder.dart';
import '../../services/parser/json_comments.dart';
import '../../services/parser/parse_all.dart';
import '../../services/subscription/input_helpers.dart';
import '../../services/hate_invitation.dart';


class ClipboardAnalysis {
  ClipboardAnalysis({
    required this.type,
    required this.title,
    required this.subtitle,
    this.notImported = const [],
    this.dropped = const [],
  });
  final String type;
  final String title;
  final String subtitle;




  final List<NodeWarning> dropped;

  ClipboardAnalysis withDropped(List<NodeWarning> d) => d.isEmpty
      ? this
      : ClipboardAnalysis(
          type: type,
          title: title,
          subtitle: subtitle,
          notImported: notImported,
          dropped: d,
        );




  final List<String> notImported;
}



const _kIgnoredConfigSections = ['route', 'dns', 'inbounds'];



List<NodeWarning> _droppedOf(DecodedBody decoded) {
  final dropped = <NodeWarning>[];
  try {
    final nodes = parseAll(decoded, dropped: dropped);


    if (nodes.isEmpty && acceptsOwnUnknownType(decoded) != null) {
      return const [];
    }
  } catch (_) {
    return const [];
  }
  return dropped;
}

ClipboardAnalysis analyzeClipboard(String text) {
  if (HateInvitationClient.isLink(text)) {
    return ClipboardAnalysis(
      type: 'hatevpn_invitation',
      title: 'Приглашение HateVPN',
      subtitle: text.trim().toLowerCase().startsWith('hatevpn://claim/')
          ? 'Одноразовая ссылка. После добавления повторно использовать её нельзя.'
          : 'Ссылка с готовым VPN-профилем.',
    );
  }
  if (isSubscriptionUrl(text)) {
    final uri = Uri.tryParse(text);
    return ClipboardAnalysis(
      type: 'subscription',
      title: getLocalText.s("Subscription URL"),
      subtitle: uri?.host ?? text,
    );
  }
  if (isWireGuardConfig(text)) {
    final lines = text.split('\n');
    final endpoint = lines
        .where((l) => l.trim().toLowerCase().startsWith('endpoint'))
        .map((l) => l.split('=').last.trim())
        .firstOrNull ?? '';
    return ClipboardAnalysis(
      type: 'wireguard_config',
      title: getLocalText.s("WireGuard config"),
      subtitle: endpoint.isNotEmpty ? endpoint : '[Interface] + [Peer]',
    );
  }


  if (isAmneziaVpnLink(text)) {
    final decoded = decode(text);
    if (decoded is AmneziaConfig) {
      final endpoint = decoded.iniTexts.first
          .split('\n')
          .where((l) => l.trim().toLowerCase().startsWith('endpoint'))
          .map((l) => l.split('=').last.trim())
          .firstOrNull ?? '';
      final n = decoded.iniTexts.length;
      return ClipboardAnalysis(
        type: 'amnezia_vpn',
        title: getLocalText.s("Amnezia VPN config"),
        subtitle: '${endpoint.isNotEmpty ? endpoint : "WG/AWG"}'
            '${n > 1 ? " × $n" : ""}',
      );
    }
    return ClipboardAnalysis(type: 'unknown', title: getLocalText.s("Unknown"), subtitle: '');
  }
  if (isDirectLink(text)) {
    final uri = Uri.tryParse(text);
    final scheme = text.split('://').first.toUpperCase();
    final label = uri?.fragment ?? '';
    final server = uri != null ? '${uri.host}:${uri.port}' : '';
    return ClipboardAnalysis(
      type: 'direct',
      title: getLocalText.s("%s link", scheme),
      subtitle: '${label.isNotEmpty ? "$label\n" : ""}$server',
    ).withDropped(_droppedOf(decode(text)));
  }







  final decoded = decode(uncommentedJson(text) ?? text);
  if (decoded is JsonConfig) {
    final analysis = _analyzeJson(decoded);
    if (analysis != null) return analysis.withDropped(_droppedOf(decoded));
  }

  return ClipboardAnalysis(type: 'unknown', title: getLocalText.s("Unknown"), subtitle: '');
}



ClipboardAnalysis? _analyzeJson(JsonConfig j) {


  switch (j.source.kind) {
    case SourceKind.singboxOutbound:
      final map = j.value is Map<String, dynamic>
          ? j.value as Map<String, dynamic>
          : const <String, dynamic>{};
      final type = map['type']?.toString() ?? 'unknown';
      final tag = map['tag']?.toString() ?? '';
      return ClipboardAnalysis(
        type: 'json_outbound',
        title: getLocalText.s("Outbound JSON"),
        subtitle: '$type${tag.isNotEmpty ? " — $tag" : ""}',
      );

    case SourceKind.singboxOutboundArray:
      final list = j.value is List ? j.value as List : const [];
      final types = list
          .whereType<Map<String, dynamic>>()
          .map((o) => o['type']?.toString() ?? '?')
          .toList();
      return ClipboardAnalysis(
        type: 'json_outbound',
        title: getLocalText.s("Outbound JSON"),
        subtitle: getLocalText.plural(
            "%1\$d outbounds (%2\$s)", list.length, types.join(" + ")),
      );

    case SourceKind.singboxConfig:
    case SourceKind.singboxConfigArray:
      final configs = j.source.kind == SourceKind.singboxConfig
          ? [
              if (j.value is Map<String, dynamic>)
                j.value as Map<String, dynamic>,
            ]
          : (j.value is List ? j.value as List : const [])
              .whereType<Map<String, dynamic>>()
              .toList();
      final nodes = parseAll(j);
      final groups = nodes.where((n) => n.isGroup).length;
      final chained = nodes.where((n) => n.chained != null).length;

      final ignored = <String>[
        for (final s in _kIgnoredConfigSections)
          if (configs.any((c) => c.containsKey(s))) s,
      ];

      return ClipboardAnalysis(
        type: 'singbox_config',
        title: getLocalText.s("sing-box config"),
        subtitle: [
          getLocalText.plural("%d nodes", nodes.length - groups),
          if (groups > 0) getLocalText.plural("%d groups", groups),
          if (chained > 0) getLocalText.plural("%d chained", chained),
        ].join(' · '),
        notImported: ignored,
      );





    case SourceKind.xrayConfigArray:
    case SourceKind.xrayConfig:
    case SourceKind.xrayOutbound:
    case SourceKind.xrayOutboundArray:
      final list = j.value is List ? j.value as List : const [];
      final count = list.isNotEmpty ? list.length : parseAll(j).length;
      return ClipboardAnalysis(
        type: 'json_outbound',
        title: getLocalText.s("Xray config"),
        subtitle: getLocalText.plural("%d elements", count),
      );



    default:
      return null;
  }
}
