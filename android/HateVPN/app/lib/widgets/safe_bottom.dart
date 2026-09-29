import 'package:flutter/material.dart';













extension SafeBottomInset on EdgeInsets {
  EdgeInsets withSafeBottom(BuildContext context) =>
      copyWith(bottom: bottom + MediaQuery.paddingOf(context).bottom);
}



extension SafeBottomInsetGeometry on EdgeInsetsGeometry {
  EdgeInsetsGeometry withSafeBottom(BuildContext context) =>
      add(EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom));
}
