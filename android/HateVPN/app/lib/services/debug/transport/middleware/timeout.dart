import 'dart:async';

import '../../contract/errors.dart';
import '../pipeline.dart';







Middleware timeoutMiddleware(Duration limit) {
  return (req, ctx, next) async {
    try {
      return await next().timeout(limit);
    } on TimeoutException {
      throw const RequestTimeout();
    }
  };
}
