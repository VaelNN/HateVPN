import 'package:flutter/widgets.dart';



















class HomeReturnObserver extends NavigatorObserver {
  VoidCallback? _handler;



  void setHandler(VoidCallback handler) {
    _handler = handler;
  }

  void clearHandler() {
    _handler = null;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);



    if (previousRoute?.isFirst == true) {
      _handler?.call();
    }
  }
}

final HomeReturnObserver homeReturnObserver = HomeReturnObserver();
