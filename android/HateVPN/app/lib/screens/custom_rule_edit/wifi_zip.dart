import '../../widgets/wifi_entry.dart';














({List<String> ssids, List<String> bssids}) zipWifiEntries(
    List<WifiEntry> entries) {
  final ssids = <String>[];
  final bssids = <String>[];
  for (final e in entries) {
    if (e.ssid.isNotEmpty && !ssids.contains(e.ssid)) ssids.add(e.ssid);
    if (e.bssid.isNotEmpty && !bssids.contains(e.bssid)) bssids.add(e.bssid);
  }
  return (ssids: ssids, bssids: bssids);
}







List<WifiEntry> unzipWifiEntries(
    List<String> ssids, List<String> bssids) {
  if (ssids.isEmpty && bssids.isEmpty) return [];
  if (ssids.length == bssids.length) {
    return [
      for (var i = 0; i < ssids.length; i++) WifiEntry(ssids[i], bssids[i]),
    ];
  }
  return [for (final s in ssids) WifiEntry(s, '')];
}
