import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../vpn/box_vpn_client.dart';
import '../context.dart';
import '../transport/request.dart';
import '../transport/response.dart';






Future<DebugResponse> deviceHandler(
  DebugRequest req,
  DebugContext ctx,
) async {
  final info = DeviceInfoPlugin();
  final pkg = await PackageInfo.fromPlatform();
  final vpn = BoxVpnClient();
  final connectivity = Connectivity();

  String androidVersion = '';
  int sdkInt = 0;
  String manufacturer = '';
  String model = '';
  String device = '';
  String abi = '';

  if (Platform.isAndroid) {
    final a = await info.androidInfo;
    androidVersion = a.version.release;
    sdkInt = a.version.sdkInt;
    manufacturer = a.manufacturer;
    model = a.model;
    device = a.device;
    abi = a.supportedAbis.isNotEmpty ? a.supportedAbis.first : '';
  }

  final batteryOk = await vpn.isIgnoringBatteryOptimizations().catchError(
        (_) => false,
      );


  final coreVersion = await vpn.getCoreVersion().catchError((_) => '');
  final connResults = await connectivity.checkConnectivity();
  final networkType = _networkLabel(connResults);

  final uptime = ctx.now().difference(ctx.appStartedAt).inSeconds;

  return JsonResponse({
    'android_version': androidVersion,
    'sdk_int': sdkInt,
    'manufacturer': manufacturer,
    'model': model,
    'device': device,
    'abi': abi,
    'app_version': pkg.version,
    'app_build': int.tryParse(pkg.buildNumber) ?? 0,
    'core_version': coreVersion,
    'package_name': pkg.packageName,
    'locale': Platform.localeName,
    'timezone': ctx.now().timeZoneName,
    'is_ignoring_battery_optimizations': batteryOk,
    'network_type': networkType,
    'uptime_seconds': uptime,
  });
}

String _networkLabel(List<ConnectivityResult> results) {
  if (results.isEmpty || results.contains(ConnectivityResult.none)) {
    return 'none';
  }

  if (results.contains(ConnectivityResult.vpn)) return 'vpn';
  if (results.contains(ConnectivityResult.ethernet)) return 'ethernet';
  if (results.contains(ConnectivityResult.wifi)) return 'wifi';
  if (results.contains(ConnectivityResult.mobile)) return 'cellular';
  if (results.contains(ConnectivityResult.bluetooth)) return 'bluetooth';
  return 'other';
}
