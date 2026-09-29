

















library;

import 'registry.dart';


const List<String> kGenusFallbackValues = ['selector', 'urltest'];


const String kGenusFallbackAuto = 'urltest';


const String kGenusAsIs = r'$as_is';


const String kGenusSourceSingbox = 'singbox';
const String kGenusSourceXray = 'xray';
const String kGenusSourceUri = 'uri';

abstract final class GroupGenus {
  static int _gen = -1;
  static Map<String, dynamic>? _cached;


  static Map<String, dynamic>? _table() {
    final reg = ContractRegistry.I;
    if (reg.generation == _gen) return _cached;
    _gen = reg.generation;
    return _cached = _scan(reg);
  }

  static Map<String, dynamic>? _scan(ContractRegistry reg) {
    for (final name in reg.protocolNames) {
      final p = reg.rawProtocol(name);
      if (p?['kind'] == 'group' && p?['genus'] is Map) {
        return (p!['genus'] as Map).cast<String, dynamic>();
      }
    }
    return null;
  }


  static List<String> get values {
    final v = _table()?['values'];
    return v is List && v.isNotEmpty
        ? [for (final e in v) '$e']
        : kGenusFallbackValues;
  }



  static String? forSource(String source) {
    final by = _table()?['by_source'];
    if (by is! Map) {
      return source == kGenusSourceSingbox ? null : kGenusFallbackAuto;
    }
    final v = by[source];
    if (v is! String || v == kGenusAsIs) return null;
    return v;
  }


  static String get auto => forSource(kGenusSourceUri) ?? kGenusFallbackAuto;


  static String get manual =>
      values.firstWhere((v) => v != auto, orElse: () => auto);


  static bool isKnown(String value) => values.contains(value);



  static String? resolve(String source, String type) {
    final fixed = forSource(source);
    if (fixed != null) return fixed;
    return isKnown(type) ? type : null;
  }
}
