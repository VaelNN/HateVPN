import 'package:flutter/material.dart';
























Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  Color? backgroundColor,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,



  bool keyboardInset = true,


  bool safeBottom = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    useSafeArea: useSafeArea,
    backgroundColor: backgroundColor,
    shape: shape,
    clipBehavior: clipBehavior,
    constraints: constraints,
    builder: (ctx) {
      Widget child = builder(ctx);
      if (safeBottom) child = SafeArea(top: false, child: child);
      if (keyboardInset) {



        child = Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: MediaQuery.removeViewInsets(
            context: ctx,
            removeBottom: true,
            child: child,
          ),
        );
      }
      return child;
    },
  );
}
