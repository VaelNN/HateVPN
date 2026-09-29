import '../../../models/home_state.dart';
import '../../tailscale_network.dart';




Map<String, Object?> serializeHomeState(HomeState s) {
  return {
    'tunnel': s.tunnel.name,
    'tunnel_up': s.tunnelUp,
    'busy': s.busy,
    'config_length': s.configRaw.length,



    'running_config_length': s.runningConfigRaw?.length,
    'active_in_group': s.activeInGroup,
    'selected_group': s.selectedGroup,
    'highlighted_node': s.highlightedNode,
    'groups': s.groups,
    'nodes_count': s.nodes.length,




    'delay_by_direction': s.delayByDirection,
    'last_delay': {
      for (final tag in s.nodes)
        if (s.delayOf(tag) != null) tag: s.delayOf(tag),
    },
    'ping_busy': s.pingBusy,




    'endpoint_states': s.endpointStates,


    'tailscale': {
      for (final e in s.tailscaleStatus.entries)
        e.key: tailscaleDebugSummary(e.value),
    },
    'traffic': {
      'up_total': s.traffic.uploadTotal,
      'down_total': s.traffic.downloadTotal,
      'active_connections': s.traffic.activeConnections,
    },
    'connected_since': s.connectedSince?.toUtc().toIso8601String(),
    'last_error': s.lastError?.renderEn() ?? '',



    'last_start_error': s.lastStartError,
    'last_start_error_at': s.lastStartErrorAt?.toUtc().toIso8601String(),

    'config_changed_need_restart': s.configChangedNeedRestart,
    'sort_mode': s.sortMode.name,

    'pin_direct': s.pinDirect,
    'pin_auto': s.pinAuto,
    'resort_on_manual_ping': s.resortOnManualPing,
    'ping_batch_gen': s.pingBatchGen,
    'manual_order': s.manualOrder,
  };
}
