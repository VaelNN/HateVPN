


















library;

import 'package:flutter/foundation.dart';


@immutable
class SupportLinkAction {
  const SupportLinkAction(this.action, this.payload);

  final String action;
  final String payload;

  static const _scheme = 'lxbox://';


  static SupportLinkAction? parse(String url) {
    if (!url.startsWith(_scheme)) return null;
    final rest = url.substring(_scheme.length);
    final i = rest.indexOf(':');
    if (i <= 0) return null;
    final payload = rest.substring(i + 1);
    if (payload.isEmpty) return null;
    return SupportLinkAction(rest.substring(0, i), payload);
  }
}




const kSupportRouteScreens = <String>{
  'servers',
  'routing',
  'dns',
  'vpn-settings',
  'app-settings',
  'speedtest',
  'stats',
  'config',
  'debug',
  'about',
  'profiler',
};


List<String> routeSegments(SupportLinkAction a) => a.payload.split('/');



bool isResolvableSupportAction(SupportLinkAction a) => switch (a.action) {
      'route' => kSupportRouteScreens.contains(routeSegments(a).first),
      'add' => a.payload.trim().isNotEmpty,
      'share' => a.payload.trim().isNotEmpty,
      _ => false,
    };



bool isInPlaceSupportAction(SupportLinkAction a) => a.action == 'share';
