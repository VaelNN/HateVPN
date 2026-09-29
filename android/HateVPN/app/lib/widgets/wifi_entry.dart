







class WifiEntry {
  const WifiEntry(this.ssid, this.bssid);
  final String ssid;
  final String bssid;

  @override
  bool operator ==(Object other) =>
      other is WifiEntry && other.ssid == ssid && other.bssid == bssid;

  @override
  int get hashCode => Object.hash(ssid, bssid);

  @override
  String toString() =>
      bssid.isEmpty ? 'WifiEntry($ssid)' : 'WifiEntry($ssid · $bssid)';
}
