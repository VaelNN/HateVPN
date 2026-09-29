part of '../box_vpn_client.dart';











class _Timeouts {
  const _Timeouts._();



  static const status = Duration(seconds: 3);



  static const startVpn = Duration(seconds: 30);












  static const stopVpn = Duration(seconds: 10);



  static const config = Duration(seconds: 5);



  static const apps = Duration(seconds: 15);


  static const app = Duration(seconds: 5);



  static const settings = Duration(seconds: 3);


  static const requestTile = Duration(seconds: 10);



  static const reload = Duration(seconds: 10);


  static const resetNet = Duration(seconds: 5);





  static const formatConfig = Duration(seconds: 5);



  static const checkConfig = Duration(seconds: 10);



  static const dnsCache = Duration(seconds: 10);




  static const goroutineDump = Duration(seconds: 5);





  static const cpuHeadroomSeconds = 10;
}
