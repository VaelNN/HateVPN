import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/node_warning.dart';
import 'package:lxbox/models/ui_msg.dart';
import 'package:lxbox/services/l10n/get_local_text.dart';
import 'package:lxbox/services/l10n/plural_resolver.dart';






GetLocalText _loadRu() {
  final raw = File('assets/l10n/ru/ui.json').readAsStringSync();
  final dict = jsonDecode(raw) as Map<String, dynamic>;
  return GetLocalText(dict, const RuPluralResolver());
}

void main() {
  final cyrillic = RegExp('[а-яА-ЯёЁ]');
  final ru = _loadRu();

  test('renderWith(ru) русеет, renderEn() неизменен', () {

    const warning = UnknownObfsWarning('salamander');
    const error = ErrMsg(ErrKey.failedToStartVpn);


    expect(warning.renderEn(), isNot(contains(cyrillic)));
    expect(error.renderEn(), 'Failed to start VPN');



    final warnRu = warning.messageWith(ru);
    expect(warnRu, contains(cyrillic));
    expect(warnRu, contains('salamander'));

    final errRu = error.renderWith(ru);
    expect(errRu, contains(cyrillic));
    expect(errRu, isNot(error.renderEn()));


    expect(warning.renderEn(), isNot(contains(cyrillic)));
    expect(error.renderEn(), 'Failed to start VPN');
  });
}
