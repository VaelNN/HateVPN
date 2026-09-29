









sealed class DebugError implements Exception {
  const DebugError(
    this.message, {
    required this.status,
    required this.code,
  });

  final int status;
  final String code;
  final String message;

  Map<String, Object?> toJson() => {
        'error': {
          'code': code,
          'message': message,
        },
      };

  @override
  String toString() => '$runtimeType($code): $message';
}


class BadRequest extends DebugError {
  const BadRequest(super.message, {this.dropped}) : super(status: 400, code: 'bad_request');


  final List<Map<String, Object?>>? dropped;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        if (dropped != null) 'dropped': dropped,
      };
}


class Unauthorized extends DebugError {
  const Unauthorized()
      : super(
          'valid Bearer token required',
          status: 401,
          code: 'unauthorized',
        );
}


class InvalidHost extends DebugError {
  const InvalidHost()
      : super(
          'request host must be 127.0.0.1 or localhost',
          status: 403,
          code: 'invalid_host',
        );
}


class NotFound extends DebugError {
  const NotFound(super.message) : super(status: 404, code: 'not_found');
}



class Conflict extends DebugError {
  const Conflict(super.message) : super(status: 409, code: 'conflict');
}


class PayloadTooLarge extends DebugError {
  PayloadTooLarge(int limit)
      : super(
          'body exceeds $limit bytes',
          status: 413,
          code: 'payload_too_large',
        );
}


class UpstreamError extends DebugError {
  const UpstreamError(super.message) : super(status: 502, code: 'upstream_error');
}


class RequestTimeout extends DebugError {
  const RequestTimeout()
      : super('request timed out', status: 504, code: 'timeout');
}



class InternalError extends DebugError {
  const InternalError([String? detail])
      : super(
          detail ?? 'internal server error',
          status: 500,
          code: 'internal',
        );
}
