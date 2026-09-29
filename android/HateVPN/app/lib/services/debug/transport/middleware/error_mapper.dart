import '../../context.dart';
import '../../contract/errors.dart';
import '../pipeline.dart';
import '../request.dart';
import '../response.dart';









Future<DebugResponse> errorMapper(
  DebugRequest req,
  DebugContext ctx,
  Next next,
) async {
  try {
    return await next();
  } on DebugError catch (e) {
    return ErrorResponse(e);
  } catch (e, st) {
    ctx.log.error(
      'Debug API: unhandled ${req.method} ${req.path} — $e\n$st',
    );
    return ErrorResponse(InternalError('$e'));
  }
}
