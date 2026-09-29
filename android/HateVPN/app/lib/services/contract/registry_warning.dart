









library;

import '../../models/node_warning.dart' show WarningSeverity;
import 'registry.dart';



enum RegistryLang { en, ru }


RegistryLang registryLangForTag(String tag) =>
    tag == 'ru' ? RegistryLang.ru : RegistryLang.en;



String registryTitle(
  String code,
  RegistryLang lang, {
  String? path,
  String? value,
  Map<String, String> params = const {},
}) {
  final text = ContractRegistry.I.textFor(code);
  if (text == null) return code;
  final raw = lang == RegistryLang.ru ? text.titleRu : text.titleEn;
  if (raw.isEmpty) return code;
  return _substitute(raw, path: path, value: value, params: params);
}



String registryText(
  String code,
  RegistryLang lang, {
  String? path,
  String? value,
  Map<String, String> params = const {},
}) {
  final text = ContractRegistry.I.textFor(code);
  if (text == null) return '';
  final raw = lang == RegistryLang.ru ? text.textRu : text.textEn;
  return _substitute(raw, path: path, value: value, params: params);
}




String? registryCause(
  String code,
  RegistryLang lang, {
  String? path,
  String? value,
  Map<String, String> params = const {},
}) {
  final text = ContractRegistry.I.textFor(code);
  if (text == null) return null;
  final raw = lang == RegistryLang.ru ? text.causeRu : text.causeEn;
  if (raw == null || raw.isEmpty) return null;
  return _substitute(raw, path: path, value: value, params: params);
}



List<String> registryFix(
  String code,
  RegistryLang lang, {
  String? path,
  String? value,
  Map<String, String> params = const {},
}) {
  final text = ContractRegistry.I.textFor(code);
  if (text == null) return const [];
  final raw = lang == RegistryLang.ru ? text.fixRu : text.fixEn;
  return [
    for (final step in raw)
      if (step.isNotEmpty)
        _substitute(step, path: path, value: value, params: params),
  ];
}


WarningSeverity registrySeverity(String code) {
  switch (ContractRegistry.I.textFor(code)?.severity) {
    case 'info':
      return WarningSeverity.info;
    case 'error':
      return WarningSeverity.error;
    default:
      return WarningSeverity.warning;
  }
}




String? maskRegistrySecretValue(String? path, String? value) {
  if (value == null || value.isEmpty || value == '***') return value;
  return registryFieldPathIsSecret(path) ? '***' : value;
}

bool registryFieldPathIsSecret(String? path) {
  if (path == null || path.isEmpty) return false;
  final leaf = path.split('.').last.replaceAll(RegExp(r'\[\]'), '');
  for (final type in ContractRegistry.I.protocolNames) {
    if (ContractRegistry.I.schemaFor(type)?.fields[leaf]?.secret == true) {
      return true;
    }
  }
  for (final shared in const ['tls', 'dialer', 'dialer.common', 'multiplex']) {
    if (ContractRegistry.I.sharedSchema(shared)?.fields[leaf]?.secret == true) {
      return true;
    }
  }
  return false;
}






String _substitute(
  String raw, {
  String? path,
  String? value,
  Map<String, String> params = const {},
}) {
  var out = raw;
  if (path != null) out = out.replaceAll('{path}', path);
  if (value != null) out = out.replaceAll('{value}', value);
  for (final e in params.entries) {
    out = out.replaceAll('{${e.key}}', e.value);
  }
  return out;
}
