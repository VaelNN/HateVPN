import 'dart:convert';

import '../models/node_spec.dart';











const List<String> kEmojiPalette = [
  '🏠', '⚡', '🚀', '🔁', '⚙', '⭐', '🌍', '🔒',
  '☁️', '🎭', '⛈️', '🌀', '🛡️', '❤️',
];






final RegExp _emojiRe = RegExp(

  r'(\p{Regional_Indicator}\p{Regional_Indicator}|\p{Extended_Pictographic})',
  unicode: true,
);


bool hasEmoji(String s) => _emojiRe.hasMatch(s);



String defaultEmojiFor(NodeSpec node) {



  final bareTag = node.tag.trim();
  if (bareTag == 'WARP' || bareTag == 'WARP+') return '🔥☁️';

  final server = node.server.trim().toLowerCase();
  if (server == '127.0.0.1' || server == 'localhost' || server == '::1') {
    return '🔁';
  }
  if (node is WireguardSpec) return '🏠';

  if (node is TailscaleSpec) return '🕸️';



  if (node is MasqueSpec) return '🎭';
  if (node is Hysteria2Spec || node is TuicSpec) return '🚀';
  return '⚡';
}




String withDefaultEmoji(String rawBody, NodeSpec node) {
  if (hasEmoji(node.tag)) return rawBody;
  return prependEmojiToRawBody(rawBody, defaultEmojiFor(node));
}



String prependEmojiToRawBody(String rawBody, String emoji) {
  final trimmed = rawBody.trim();
  if (trimmed.isEmpty) return rawBody;
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    return _prependToJsonTag(trimmed, emoji) ?? rawBody;
  }
  return _prependToUriFragment(trimmed, emoji);
}

String? _prependToJsonTag(String json, String emoji) {
  try {
    final parsed = jsonDecode(json);
    final map = parsed is List
        ? (parsed.isNotEmpty ? parsed.first : null)
        : parsed;
    if (map is! Map<String, dynamic>) return null;
    final cur = (map['tag'] as String?) ?? '';
    if (hasEmoji(cur)) return json;
    map['tag'] = cur.isEmpty ? emoji : '$emoji $cur';
    if (parsed is List) {
      parsed[0] = map;
      return jsonEncode(parsed);
    }
    return jsonEncode(map);
  } catch (_) {
    return null;
  }
}

String _prependToUriFragment(String uri, String emoji) {
  final idx = uri.indexOf('#');
  if (idx < 0) {

    return '$uri#${Uri.encodeComponent(emoji)}';
  }
  final frag = uri.substring(idx + 1);


  String decoded;
  try {
    decoded = Uri.decodeComponent(frag);
  } catch (_) {
    decoded = frag;
  }
  if (hasEmoji(decoded)) return uri;
  final base = uri.substring(0, idx + 1);
  return '$base${Uri.encodeComponent('$emoji ')}$frag';
}
