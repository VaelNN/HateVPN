






library;

import '../services/l10n/get_local_text.dart';
import '../services/l10n/locale_controller.dart';

sealed class StopReason {
  const StopReason();


  static const _permissionLocationMarker = 'alert:permission_location:';


  static StopReason? fromEvent(
      {required bool revoked, required String? errorReason}) {
    if (revoked) return const StopRevoked();
    if (errorReason == null) return null;
    if (errorReason.contains(_permissionLocationMarker)) {
      return StopPermissionLocation(
        permissions:
            errorReason.replaceFirst(_permissionLocationMarker, '').trim(),
        raw: errorReason,
      );
    }
    return StopError(errorReason);
  }





  String messageWith(GetLocalText t);


  String message() => messageWith(getLocalText);


  String renderEn() => messageWith(GetLocalText.en);

  List<Object?> get props => const [];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StopReason &&
          runtimeType == other.runtimeType &&
          _propsEqual(props, other.props));

  @override
  int get hashCode => Object.hashAll([runtimeType, ...props]);

  @override
  String toString() => '$runtimeType(${props.join(', ')})';
}

bool _propsEqual(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}


final class StopRevoked extends StopReason {
  const StopRevoked();

  @override
  String messageWith(GetLocalText t) => t.s("Another VPN app took the system VPN slot (e.g. an always-on VPN). Start again to reconnect.");
}



final class StopPermissionLocation extends StopReason {

  final String permissions;



  final String raw;

  const StopPermissionLocation({required this.permissions, required this.raw});

  @override
  List<Object?> get props => [permissions, raw];

  @override
  String messageWith(GetLocalText t) => t.s("Stopped: %s", raw);
}










final class StopStartTimeout extends StopReason {
  final int seconds;
  final int endpoints;

  const StopStartTimeout({required this.seconds, required this.endpoints});

  @override
  List<Object?> get props => [seconds, endpoints];

  @override
  String messageWith(GetLocalText t) => t.s(
      "Start timed out after %1\$d s (post-start did not finish, %2\$d endpoints)",
      seconds,
      endpoints);
}


final class StopError extends StopReason {
  final String detail;
  const StopError(this.detail);

  @override
  List<Object?> get props => [detail];

  @override
  String messageWith(GetLocalText t) => t.s("Stopped: %s", detail);
}
