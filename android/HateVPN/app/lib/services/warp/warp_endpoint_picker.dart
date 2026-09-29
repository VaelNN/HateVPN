import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;

import 'scan/scan_pool.dart';
import '../usage_region.dart';










class WarpEndpointPicker {
  WarpEndpointPicker._(this._scan);

  static const String _assetPath = 'assets/warp_endpoints.json';
  static final Random _rng = Random.secure();


  final ScanPool? _scan;

  static WarpEndpointPicker? _cached;
  static String? _cachedRegion;







  static Future<WarpEndpointPicker> load({String? region}) async {
    final r = region ?? await UsageRegion.effective();
    if (_cached != null && _cachedRegion == r) return _cached!;
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _cached = WarpEndpointPicker._(ScanPool.fromFullJson(json, region: r));
    } catch (_) {
      _cached = WarpEndpointPicker._(null);
    }
    _cachedRegion = r;
    return _cached!;
  }


  static Future<List<String>> availableRegions() async {
    try {
      final raw = await rootBundle.loadString(_assetPath);
      return ScanPool.regionsOf(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const [];
    }
  }

  bool get hasData => _scan?.hasData ?? false;







  String? randomEndpoint({bool allowV6 = false}) {
    final s = _scan;
    if (s == null) return null;
    final useV6 = allowV6 && s.wgV6Cidr.isNotEmpty && _rng.nextBool();
    final blocks = useV6 ? s.wgV6Cidr : s.wgV4Cidr;
    final ports = [...s.wgPorts, ...s.wgPortsExtra];
    if (blocks.isEmpty || ports.isEmpty) return null;
    try {
      final ip = randomIpInCidr(blocks[_rng.nextInt(blocks.length)], _rng);
      final port = ports[_rng.nextInt(ports.length)];

      final host = ip.contains(':') ? '[$ip]' : ip;
      return '$host:$port';
    } catch (_) {
      return null;
    }
  }


  String randomSni() {
    final p = _scan?.wgSniPool ?? const [];
    return p.isEmpty ? '' : p[_rng.nextInt(p.length)];
  }

  List<String> get sniPool => List.unmodifiable(_scan?.wgSniPool ?? const []);



  List<String> get endpointsPreset =>
      List.unmodifiable(_scan?.wgEndpointsPreset ?? const []);



  String get recommendedEndpoint => _scan?.wgRecommendedEndpoint ?? '';


  String get recommendedMasqueHost => _scan?.masqueRecommendedHost ?? '';


  List<String> get masqueHostsPreset =>
      List.unmodifiable(_scan?.masqueHostsPreset ?? const <String>[]);



  List<String> masqueHostsFor(String network) =>
      List.unmodifiable(_scan?.masqueHostsFor(network) ?? const <String>[]);



  List<String> get masqueH3Hosts =>
      List.unmodifiable(_scan?.masqueH3Hosts ?? const <String>[]);


  String randomMasqueSni() {
    final p = _scan?.masqueSniPool ?? const [];
    return p.isEmpty ? '' : p[_rng.nextInt(p.length)];
  }


  List<String> get masqueSniPool =>
      List.unmodifiable(_scan?.masqueSniPool ?? const []);


  String get recommendedMasqueSni => _scan?.masqueRecommendedSni ?? '';



  List<String> get apiHosts =>
      List.unmodifiable(_scan?.apiHosts ?? const <String>[]);


  ScanPool? get scan => _scan;


  List<String> get masqueV4Cidr =>
      List.unmodifiable(_scan?.masqueV4Cidr ?? const []);



  List<int> masquePortsFor(String network) =>
      _scan?.masquePortsFor(network) ?? const [];


  int? randomMasquePortFor(String network) {
    final ports = masquePortsFor(network);
    return ports.isEmpty ? null : ports[_rng.nextInt(ports.length)];
  }




  String? randomMasqueIp({String network = 'h3'}) =>
      _scan?.randomMasqueIp(network, _rng);


  static Future<String> loadRawJson() async {
    try {
      return await rootBundle.loadString(_assetPath);
    } catch (_) {
      return '';
    }
  }


  static void resetForTest() {
    _cached = null;
    _cachedRegion = null;
  }
}
