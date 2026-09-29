import '../../context.dart';
import '../../contract/errors.dart';
import '../pipeline.dart';
import '../request.dart';
import '../response.dart';






Future<DebugResponse> hostCheck(
  DebugRequest req,
  DebugContext ctx,
  Next next,
) async {
  final raw = req.header('host') ?? '';
  final host = raw.split(':').first.toLowerCase();
  if (host != '127.0.0.1' && host != 'localhost') {
    throw const InvalidHost();
  }
  return next();
}
