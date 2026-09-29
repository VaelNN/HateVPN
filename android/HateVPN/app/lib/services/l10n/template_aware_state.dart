import 'package:flutter/widgets.dart';

import 'locale_controller.dart';



















mixin TemplateAwareState<T extends StatefulWidget> on State<T> {
  String? _templateLocaleTag;


  String? get templateLocaleTag => _templateLocaleTag;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();


    final tag = Localizations.maybeLocaleOf(context)?.languageCode ??
        LocaleController.I.effectiveTag;
    if (tag == _templateLocaleTag) return;
    final first = _templateLocaleTag == null;
    _templateLocaleTag = tag;
    onLocaleTemplateFetch(first: first);
  }



  void onLocaleTemplateFetch({required bool first});
}
