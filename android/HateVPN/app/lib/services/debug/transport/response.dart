import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../contract/errors.dart';





sealed class DebugResponse {
  const DebugResponse();

  int get status;
  Map<String, String> get headers;



  Future<void> writeTo(HttpResponse out);

  void _applyHeaders(HttpResponse out) {
    out.statusCode = status;
    for (final e in headers.entries) {
      out.headers.set(e.key, e.value);
    }
  }
}


class JsonResponse extends DebugResponse {
  const JsonResponse(this.body, {this.status = 200, this.pretty = false});

  final Object? body;
  @override
  final int status;
  final bool pretty;

  @override
  Map<String, String> get headers =>
      const {'content-type': 'application/json; charset=utf-8'};

  @override
  Future<void> writeTo(HttpResponse out) async {
    _applyHeaders(out);
    final encoder =
        pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder();
    out.write(encoder.convert(body));
    await out.close();
  }
}




class RawJsonResponse extends DebugResponse {
  const RawJsonResponse(this.raw, {this.status = 200});

  final String raw;
  @override
  final int status;

  @override
  Map<String, String> get headers =>
      const {'content-type': 'application/json; charset=utf-8'};

  @override
  Future<void> writeTo(HttpResponse out) async {
    _applyHeaders(out);
    out.write(raw);
    await out.close();
  }
}


class BytesResponse extends DebugResponse {
  BytesResponse(
    this.bytes, {
    this.status = 200,
    this.contentType = 'application/octet-stream',
    this.filename,
    Map<String, String> extraHeaders = const {},
  }) : _extra = extraHeaders;

  final List<int> bytes;
  @override
  final int status;
  final String contentType;
  final String? filename;
  final Map<String, String> _extra;

  @override
  Map<String, String> get headers => {
        'content-type': contentType,
        'content-length': bytes.length.toString(),
        if (filename != null)
          'content-disposition': 'attachment; filename="$filename"',
        ..._extra,
      };

  @override
  Future<void> writeTo(HttpResponse out) async {
    _applyHeaders(out);
    out.add(bytes);
    await out.close();
  }
}







class SseResponse extends DebugResponse {
  SseResponse(this.events);


  final Stream<Map<String, Object?>> events;

  @override
  int get status => 200;

  @override
  Map<String, String> get headers => const {
        'content-type': 'text/event-stream; charset=utf-8',
        'cache-control': 'no-cache',
        'connection': 'keep-alive',
        'x-accel-buffering': 'no',
      };

  @override
  Future<void> writeTo(HttpResponse out) async {
    _applyHeaders(out);

    await out.flush();
    final completer = Completer<void>();
    final sub = events.listen(
      (e) {
        try {
          final ev = e['event']?.toString() ?? 'message';
          final data = jsonEncode(e['data'] ?? {});
          out.write('event: $ev\n');
          out.write('data: $data\n\n');
          out.flush();
        } catch (_) { }
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete();
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: false,
    );

    out.done.then((_) {
      sub.cancel();
      if (!completer.isCompleted) completer.complete();
    }).catchError((_) {
      sub.cancel();
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
    try {
      await out.close();
    } catch (_) {}
  }
}



class ErrorResponse extends DebugResponse {
  const ErrorResponse(this.error);

  final DebugError error;

  @override
  int get status => error.status;

  @override
  Map<String, String> get headers =>
      const {'content-type': 'application/json; charset=utf-8'};

  @override
  Future<void> writeTo(HttpResponse out) async {
    _applyHeaders(out);
    out.write(jsonEncode(error.toJson()));
    await out.close();
  }
}
