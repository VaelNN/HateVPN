import '../../models/tcp_keep_alive_spec.dart';
import 'uri_utils.dart';














final _goDuration = RegExp(r'^(\d+(\.\d+)?(ns|us|µs|ms|s|m|h))+$');



String _duration(String raw) {
  final v = normalizeSingboxDuration(raw.trim());
  if (v.isEmpty) return '';
  return _goDuration.hasMatch(v) ? v : '';
}



TcpKeepAliveSpec? tcpKeepAliveFromSingbox(Map entry) {
  final s = TcpKeepAliveSpec(
    disabled: entry['disable_tcp_keep_alive'] == true,


    idle: _duration(entry['tcp_keep_alive']?.toString() ?? ''),
    interval: _duration(entry['tcp_keep_alive_interval']?.toString() ?? ''),
  );
  return s.isEmpty ? null : s;
}



void tcpKeepAliveToSingbox(Map<String, dynamic> out, TcpKeepAliveSpec? s) {
  if (s == null) return;
  if (s.disabled) out['disable_tcp_keep_alive'] = true;
  if (s.idle.isNotEmpty) out['tcp_keep_alive'] = s.idle;
  if (s.interval.isNotEmpty) out['tcp_keep_alive_interval'] = s.interval;
}





TcpKeepAliveSpec? tcpKeepAliveFromQuery(Map<String, String> q) {
  final raw = (q['disable_tcp_keep_alive'] ?? '').toLowerCase().trim();
  final s = TcpKeepAliveSpec(
    disabled: raw == '1' || raw == 'true',
    idle: _duration(q['tcp_keep_alive'] ?? ''),
    interval: _duration(q['tcp_keep_alive_interval'] ?? ''),
  );
  return s.isEmpty ? null : s;
}


Map<String, String> tcpKeepAliveToQuery(TcpKeepAliveSpec? s) {
  if (s == null) return const <String, String>{};
  return <String, String>{
    if (s.disabled) 'disable_tcp_keep_alive': '1',
    if (s.idle.isNotEmpty) 'tcp_keep_alive': s.idle,
    if (s.interval.isNotEmpty) 'tcp_keep_alive_interval': s.interval,
  };
}
