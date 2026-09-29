











import '../../models/node_spec.dart';
import '../../models/server_list.dart';
import '../node_hash.dart';
import '../settings_storage.dart';
import 'probe_runner.dart';

class ProbeController {
  ProbeController({ProbeRunner? runner}) : _runner = runner ?? ProbeRunner();

  final ProbeRunner _runner;

  void cancel() => _runner.cancel();






  Future<String> run({
    required List<NodeSpec?> nodes,
    required String url,
    required int timeoutMs,
    required void Function(int index, ProbeResult result) onResult,
  }) =>
      _runner.run(nodes, url: url, timeoutMs: timeoutMs, onResult: onResult);


  Future<String> runList(
    ServerList list, {
    required String url,
    required int timeoutMs,
    required void Function(int index, ProbeResult result) onResult,
  }) =>
      run(nodes: probeNodesOf(list), url: url, timeoutMs: timeoutMs, onResult: onResult);






  static List<NodeSpec?> probeNodesOf(ServerList list) => switch (list) {
        FolderServers(:final members) => [for (final m in members) m.node],
        _ => list.nodes,
      };




  static Future<ProbeThresholds> loadThresholds() async {
    final g = int.tryParse(await SettingsStorage.getVar('probe_ms_green', ''));
    final y = int.tryParse(await SettingsStorage.getVar('probe_ms_yellow', ''));
    final o = int.tryParse(await SettingsStorage.getVar('probe_ms_orange', ''));
    return ProbeThresholds(
      greenMs: g ?? ProbeThresholds.defaults.greenMs,
      yellowMs: y ?? ProbeThresholds.defaults.yellowMs,
      orangeMs: o ?? ProbeThresholds.defaults.orangeMs,
    );
  }


  static Future<ProbeThresholds> saveThresholds({
    int? greenMs,
    int? yellowMs,
    int? orangeMs,
  }) async {
    final next = ProbeThresholds(
      greenMs: (greenMs == null || greenMs <= 0)
          ? ProbeThresholds.defaults.greenMs
          : greenMs,
      yellowMs: (yellowMs == null || yellowMs <= 0)
          ? ProbeThresholds.defaults.yellowMs
          : yellowMs,
      orangeMs: (orangeMs == null || orangeMs <= 0)
          ? ProbeThresholds.defaults.orangeMs
          : orangeMs,
    );
    await SettingsStorage.setVar('probe_ms_green', '${next.greenMs}');
    await SettingsStorage.setVar('probe_ms_yellow', '${next.yellowMs}');
    await SettingsStorage.setVar('probe_ms_orange', '${next.orangeMs}');
    return next;
  }






  static Future<({String url, int timeoutMs})> resolvePingOptions({
    String? overrideUrl,
    int? overrideTimeoutMs,
  }) async {
    final ping = await SettingsStorage.getPingOptions();
    final url = (overrideUrl ?? (ping['url'] as String?))?.trim() ?? '';
    final timeoutMs = overrideTimeoutMs ??
        (ping['timeout_ms'] as num?)?.toInt() ??
        3000;
    return (url: url, timeoutMs: timeoutMs);
  }


  static Future<({String url, int timeoutMs})> globalPingTarget() async {
    final ping = await SettingsStorage.getPingOptions();
    return (
      url: (ping['url'] as String?) ?? '',
      timeoutMs: (ping['timeout_ms'] as num?)?.toInt() ?? 3000,
    );
  }


  static Future<void> saveGlobalPing(String url, {int? timeoutMs}) async {
    await SettingsStorage.setGlobalPingUrl(url);
    if (timeoutMs != null && timeoutMs > 0) {
      await SettingsStorage.setGlobalPingTimeout(timeoutMs);
    }
  }






  static Set<int> unreachableIndexes(Map<int, ProbeResult> probe) => {
        for (final e in probe.entries)
          if (e.value.status == ProbeStatus.failed ||
              e.value.status == ProbeStatus.broken ||
              e.value.status == ProbeStatus.invalid)
            e.key,
      };


  static Set<int> slowerThan(Map<int, ProbeResult> probe, int ms) => {
        for (final e in probe.entries)
          if (e.value.status == ProbeStatus.ok && e.value.delayMs > ms) e.key,
      };




  static List<int> pingSortOrder(Map<int, ProbeResult> probe, int count) {
    int rank(int i) {
      final r = probe[i];
      if (r == null) return 1 << 30;
      return switch (r.status) {
        ProbeStatus.ok => r.delayMs,

        ProbeStatus.pending || ProbeStatus.group => 1 << 30,
        ProbeStatus.failed ||
        ProbeStatus.broken ||
        ProbeStatus.invalid =>
          (1 << 30) + 1,
      };
    }

    return [for (var i = 0; i < count; i++) i]
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : a.compareTo(b);
      });
  }






















  static List<String> probeKeys(List<FolderMember> members) {
    final identities =
        sourceNodeIdentities([for (final m in members) ?m.node]);
    return _dedupKeys([
      for (final (i, m) in members.indexed)
        m.node == null
            ? 'raw:${m.raw}'
            : (identities[m.node!] ?? 'slot:$i'),
    ]);
  }




  static List<String> probeKeysForNodes(List<NodeSpec?> nodes) {
    final identities = sourceNodeIdentities([for (final n in nodes) ?n]);
    return _dedupKeys([
      for (final (i, n) in nodes.indexed)
        n == null ? 'slot:$i' : (identities[n] ?? 'slot:$i'),
    ]);
  }

  static List<String> _dedupKeys(List<String> bases) {
    final seen = <String, int>{};
    final keys = <String>[];
    for (final base in bases) {
      final n = (seen[base] ?? 0) + 1;
      seen[base] = n;
      keys.add(n == 1 ? base : '$base#$n');
    }
    return keys;
  }
}
