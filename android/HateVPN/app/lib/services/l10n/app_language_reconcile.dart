
















class AppLanguageNativeState {
  const AppLanguageNativeState({
    required this.applicationLocales,
    required this.lastPushedLocale,
  });



  final String applicationLocales;



  final String? lastPushedLocale;
}


sealed class AppLanguageReconcileDecision {
  const AppLanguageReconcileDecision();
}


class ReconcileNoop extends AppLanguageReconcileDecision {
  const ReconcileNoop();
}




class ReconcileSystemWins extends AppLanguageReconcileDecision {
  const ReconcileSystemWins(this.newSetting);
  final String newSetting;
}



class ReconcileStorageWins extends AppLanguageReconcileDecision {
  const ReconcileStorageWins();
}

const _supported = {'en', 'ru', 'zh'};




String _normalizeTags(String tags) {
  final first = tags.split(',').first.trim();
  if (first.isEmpty) return '';
  final lang = first.split('-').first.toLowerCase();
  return _supported.contains(lang) ? lang : '';
}


String _settingToTag(String setting) => setting == 'system' ? '' : setting;


String _tagToSetting(String tag) => tag.isEmpty ? 'system' : tag;



AppLanguageReconcileDecision reconcileAppLanguage({
  required String stored,
  required AppLanguageNativeState state,
}) {
  final current = _normalizeTags(state.applicationLocales);
  final storedTag = _settingToTag(stored);
  final rawPushed = state.lastPushedLocale;
  if (rawPushed == null) {



    if (current.isNotEmpty) return ReconcileSystemWins(_tagToSetting(current));
    return const ReconcileStorageWins();
  }
  final pushed = _normalizeTags(rawPushed);
  if (current != pushed) {

    return ReconcileSystemWins(_tagToSetting(current));
  }
  if (storedTag != current) {

    return const ReconcileStorageWins();
  }
  return const ReconcileNoop();
}
