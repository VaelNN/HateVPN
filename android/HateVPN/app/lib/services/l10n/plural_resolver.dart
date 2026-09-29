






abstract class PluralResolver {

  Set<String> get forms;




  String select(Map<String, String> forms, num n);
}


class EnPluralResolver implements PluralResolver {
  const EnPluralResolver();

  @override
  Set<String> get forms => const {'one', 'other'};

  @override
  String select(Map<String, String> forms, num n) =>
      forms[n == 1 ? 'one' : 'other'] ?? forms['other'] ?? '';
}







class RuPluralResolver implements PluralResolver {
  const RuPluralResolver();

  @override
  Set<String> get forms => const {'one', 'few', 'many', 'other'};

  @override
  String select(Map<String, String> forms, num n) {
    String pick;

    if (n is! int && n != n.truncate()) {
      pick = 'other';
    } else {
      final i = n.abs().truncate();
      final mod10 = i % 10;
      final mod100 = i % 100;
      if (mod10 == 1 && mod100 != 11) {
        pick = 'one';
      } else if (mod10 >= 2 && mod10 <= 4 && !(mod100 >= 12 && mod100 <= 14)) {
        pick = 'few';
      } else {
        pick = 'many';
      }
    }


    return forms[pick] ?? forms['other'] ?? forms['many'] ?? '';
  }
}





class ZhPluralResolver implements PluralResolver {
  const ZhPluralResolver();

  @override
  Set<String> get forms => const {'other'};

  @override
  String select(Map<String, String> forms, num n) =>
      forms['other'] ?? forms['many'] ?? forms['one'] ?? forms['few'] ?? '';
}
