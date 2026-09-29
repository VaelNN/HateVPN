
library;

import '../services/l10n/locale_controller.dart';

enum TunnelStatus {
  disconnected,
  connecting,
  connected,
  stopping,
  revoked,
  error,







  unknown;

  bool get isUp => this == connected;





  static TunnelStatus fromNative(String raw, {bool revoked = false}) {
    return switch (raw) {
      'Started' => connected,
      'Starting' => connecting,
      'Stopped' => revoked ? TunnelStatus.revoked : disconnected,
      'Stopping' => stopping,
      _ => unknown,
    };
  }



  String label() => switch (this) {
        disconnected => getLocalText.s("Disconnected"),
        connecting => getLocalText.s("Connecting…"),
        connected => getLocalText.s("Connected"),
        stopping => getLocalText.s("Stopping…"),
        revoked => getLocalText.s("Taken by another VPN"),
        error => getLocalText.s("Error"),
        unknown => getLocalText.s("Unknown"),
      };
}










class TunnelStatusEvent {
  const TunnelStatusEvent({
    required this.status,
    required this.raw,
    this.errorReason,
    this.coreError,
  });




  factory TunnelStatusEvent.fromNative(Map<dynamic, dynamic> raw) {
    final rawStatus = raw['status']?.toString() ?? '';
    return TunnelStatusEvent(


      status: TunnelStatus.fromNative(rawStatus, revoked: raw['revoked'] == true),
      raw: rawStatus,
      errorReason: _extractReason(raw),



      coreError: _nonEmpty(raw[_coreErrorKey]),
    );
  }



  static const TunnelStatusEvent unknownEmpty = TunnelStatusEvent(
    status: TunnelStatus.unknown,
    raw: '',
  );

  final TunnelStatus status;




  final String raw;



  final String? errorReason;







  final String? coreError;

  static const _coreErrorKey = 'core_error';

  static String? _nonEmpty(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static String? _extractReason(Map<dynamic, dynamic> raw) {
    const keys = <String>['error', 'message', 'reason', 'details', 'description'];
    for (final key in keys) {
      final value = raw[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }
}
