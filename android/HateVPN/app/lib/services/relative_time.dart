import 'l10n/get_local_text.dart';
import 'l10n/locale_controller.dart';








String relativeTime(DateTime now, DateTime past, {GetLocalText? t}) {
  final loc = t ?? getLocalText;
  final diff = now.difference(past);



  if (diff.inSeconds < 60) return loc.s("just now");
  if (diff.inMinutes < 60) return loc.plural("%d min ago", diff.inMinutes);
  if (diff.inHours < 24) return loc.plural("%dh ago", diff.inHours);
  if (diff.inDays == 1) return loc.s("yesterday");
  if (diff.inDays < 7) return loc.plural("%dd ago", diff.inDays);
  if (diff.inDays < 30) return loc.plural("%dw ago", (diff.inDays / 7).floor());
  if (diff.inDays < 365) {
    return loc.plural("%dmo ago", (diff.inDays / 30).floor());
  }
  return loc.plural("%dy ago", (diff.inDays / 365).floor());
}
