part of '../settings_storage.dart';












Future<WarpAccount?> _getWarpAccount() async {
  final data = await _load();
  final raw = data['warp_account'];
  if (raw is Map<String, dynamic>) {
    return WarpAccount.fromJson(raw);
  }
  return null;
}

Future<void> _setWarpAccount(WarpAccount? account, {bool flush = true}) async {
  final data = await _load();
  if (account == null) {
    data.remove('warp_account');
  } else {
    data['warp_account'] = account.toJson();
  }
  SettingsStorage._cache = data;


  if (flush) await _save();
}





Future<MasqueAccount?> _getMasqueAccount() async {
  final data = await _load();
  final raw = data['masque_account'];
  if (raw is Map<String, dynamic>) {
    return MasqueAccount.fromJson(raw);
  }
  return null;
}

Future<void> _setMasqueAccount(MasqueAccount? account, {bool flush = true}) async {
  final data = await _load();
  if (account == null) {
    data.remove('masque_account');
  } else {
    data['masque_account'] = account.toJson();
  }
  SettingsStorage._cache = data;
  if (flush) await _save();
}
