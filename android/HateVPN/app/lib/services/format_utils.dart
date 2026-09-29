

















import 'package:intl/intl.dart';




String formatBytes(int b, {bool spaced = false}) {
  final sp = spaced ? ' ' : '';
  if (spaced && b <= 0) return '0 B';
  if (b < 1024) return '$b${sp}B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)}${sp}KB';
  if (b < 1024 * 1024 * 1024) {
    return '${(b / 1024 / 1024).toStringAsFixed(1)}${sp}MB';
  }
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)}${sp}GB';
}










String formatDuration(Duration d, {bool daysRollup = false}) {
  if (daysRollup && d.inHours >= 24) {
    return '${d.inDays}d ${d.inHours % 24}h';
  }
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
  return '${d.inSeconds}s';
}



String hostOf(String destination) {
  final i = destination.lastIndexOf(':');
  return i < 0 ? destination : destination.substring(0, i);
}



String portOf(String destination) {
  final i = destination.lastIndexOf(':');
  if (i < 0 || i == destination.length - 1) return '';
  return destination.substring(i + 1);
}




String formatDurationCoarse(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds}s';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  return '${d.inHours}h${d.inMinutes % 60}m';
}


String formatTime(DateTime t) => DateFormat.Hms().format(t);


String formatTimeHm(DateTime t) => DateFormat.Hm().format(t);





String formatDateTime(DateTime t) {
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${pad(t.month)}-${pad(t.day)} ${formatTime(t)}';
}
