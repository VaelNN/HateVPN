import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../contract_paths.dart';
import 'package:lxbox/services/lx_backup.dart';
import 'package:lxbox/services/parser/uri_utils.dart'
    show kMaxDetourDepth, maxAmneziaLinkLength, maxURILength;
import 'package:lxbox/services/parser/utls_fingerprint.dart';










Map<String, dynamic> _loadAllowlists() {
  final file = File('$kRegistryRoot/registry/allowlists.json');
  final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return (data['allowlists'] as Map).cast<String, dynamic>();
}

List<String> _values(Map<String, dynamic> allowlists, String name) {
  final entry = allowlists[name];
  expect(entry, isNotNull, reason: 'в реестре нет списка "$name"');
  return ((entry as Map)['values'] as List).cast<String>();
}

void _checkAllowlist(String name, Set<String> code, Map<String, dynamic> reg) {
  final registry = _values(reg, name).toSet();
  final missingInRegistry = code.difference(registry).toList()..sort();
  final missingInCode = registry.difference(code).toList()..sort();

  expect(missingInRegistry, isEmpty,
      reason: '$name: код принимает значения, которых нет в реестре — '
          'реестр нормативен (D-020): либо внести, либо убрать из кода');
  expect(missingInCode, isEmpty,
      reason: '$name: реестр объявляет значения, которых код не принимает');
}








const _launcherOnlyBackupCodes = <String>{

  'backup_tag_mask_dropped',

  'backup_local_direction_dropped',



  'backup_direction_include_dropped',
};

Map<String, dynamic> _loadBackupWarnings() {
  final file = File('$kRegistryRoot/registry/backup_warnings.json');
  final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return (data['warnings'] as Map).cast<String, dynamic>();
}







const _codesInCode = <String>{
  kWarnUnknownOutbound,
  kWarnFinalDropped,
  kWarnUnknownPreset,
  kWarnVarSkipped,
  kWarnUnknownField,
  kWarnExtensionsDropped,
  kWarnFieldTypeMismatch,
  kWarnSourceFlagDropped,
  kWarnLabelDropped,
  kWarnSourceIdentityDropped,
  kWarnLocalOnlyDropped,
  kWarnDirectionExists,
  kWarnChainExists,
  kWarnDnsEntrySkipped,
  kWarnWarpSkipped,



  kWarnSectionRecordDropped,
  kWarnSourceKindUnsupported,
  kWarnGroupDegraded,
};

void main() {
  final allowlists = _loadAllowlists();

  group('contract registry sync', () {

    test('utls_fingerprints', () {
      _checkAllowlist('utls_fingerprints', kUtlsFingerprints, allowlists);
    });








    test('backup_warnings ↔ kWarn*', () {
      final registry = _loadBackupWarnings();
      final registryCodes = registry.keys.toSet();



      final missingInRegistry =
          _codesInCode.difference(registryCodes).toList()..sort();
      expect(missingInRegistry, isEmpty,
          reason: 'коды эмитятся приложением, но реестр их не знает — '
              'внести в registry/backup_warnings.json или убрать из кода');



      final missingInCode = registryCodes
          .difference(_codesInCode)
          .difference(_launcherOnlyBackupCodes)
          .toList()
        ..sort();
      expect(missingInCode, isEmpty,
          reason: 'реестр объявляет коды, которых LxBox не эмитит и которые '
              'не отнесены к стороне лаунчера — либо реализовать, либо '
              'внести в _launcherOnlyBackupCodes с обоснованием');



      final staleForeign =
          _launcherOnlyBackupCodes.intersection(_codesInCode).toList()..sort();
      expect(staleForeign, isEmpty,
          reason: 'код объявлен «стороной лаунчера», но LxBox его эмитит');



      final unknownForeign =
          _launcherOnlyBackupCodes.difference(registryCodes).toList()..sort();
      expect(unknownForeign, isEmpty,
          reason: 'в _launcherOnlyBackupCodes код, которого нет в реестре');
    });


    test('значения вне словаря отвергаются', () {
      expect(normalizeUtlsFingerprintValue('garbage').junk, isTrue);
    });








    test('лимиты реестра совпадают с константами кода', () {
      final file = File('$kRegistryRoot/registry/limits.json');
      final limits = ((jsonDecode(file.readAsStringSync())
              as Map<String, dynamic>)['limits'] as Map)
          .cast<String, dynamic>();
      int value(String name) {
        final e = limits[name];
        expect(e, isNotNull, reason: 'в реестре нет лимита "$name"');
        return ((e as Map)['value'] as num).toInt();
      }

      expect(maxURILength, value('max_uri_length'),
          reason: 'предел длины ссылки разошёлся с реестром: у сторон он '
              'общий с контракта 1.1.50, и расхождение означает, что длинная '
              'валидная ссылка принимается одним приложением и отбивается '
              'другим');
      expect(maxAmneziaLinkLength, value('amnezia_link_max_bytes'),
          reason: 'потолок сырой vpn://-ссылки разошёлся с реестром');
      expect(kMaxDetourDepth, value('max_detour_chain'),
          reason: 'предел длины цепочки релеев разошёлся с реестром');
    });
  });
}
