import '../../contract/errors.dart';
import '../pipeline.dart';





Middleware auth({
  required String token,
  Set<String> unauthenticatedPaths = const {'/ping'},
}) {
  return (req, ctx, next) async {
    if (unauthenticatedPaths.contains(req.path)) return next();
    if (token.isEmpty) throw const Unauthorized();
    final header = req.header('authorization') ?? '';
    if (header != 'Bearer $token') throw const Unauthorized();
    return next();
  };
}
