import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../contract/errors.dart';









class DebugRequest {
  DebugRequest({
    required this.method,
    required this.uri,
    required Map<String, List<String>> headers,
    required this.body,
    required this.receivedAt,
  }) : _headers = headers;


  final String method;


  final Uri uri;


  final Uint8List body;


  final DateTime receivedAt;

  final Map<String, List<String>> _headers;

  String get path => uri.path;
  Map<String, String> get query => uri.queryParameters;


  String? header(String name) {
    final list = _headers[name.toLowerCase()];
    if (list == null || list.isEmpty) return null;
    return list.first;
  }


  List<String> headersAll(String name) =>
      _headers[name.toLowerCase()] ?? const [];


  String? q(String name) => query[name];


  String requiredQuery(String name) {
    final v = query[name];
    if (v == null || v.isEmpty) {
      throw BadRequest('missing query param: $name');
    }
    return v;
  }


  int? qInt(String name) {
    final raw = query[name];
    if (raw == null) return null;
    final parsed = int.tryParse(raw);
    if (parsed == null) {
      throw BadRequest('query param "$name" must be int, got "$raw"');
    }
    return parsed;
  }


  bool qBool(String name, {bool defaultValue = false}) {
    final raw = query[name]?.toLowerCase();
    if (raw == null) return defaultValue;
    return raw == 'true' || raw == '1' || raw == 'yes';
  }



  Map<String, dynamic> jsonBodyAsMap() {
    if (body.isEmpty) return const {};
    try {
      final text = utf8.decode(body, allowMalformed: false);
      final parsed = jsonDecode(text);
      if (parsed is! Map<String, dynamic>) {
        throw const BadRequest('body must be JSON object');
      }
      return parsed;
    } on FormatException catch (e) {
      throw BadRequest('invalid JSON body: ${e.message}');
    }
  }



  static Future<DebugRequest> from(
    HttpRequest raw, {
    required int maxBodyBytes,
  }) async {
    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in raw) {
      total += chunk.length;
      if (total > maxBodyBytes) {
        throw PayloadTooLarge(maxBodyBytes);
      }
      builder.add(chunk);
    }
    final headers = <String, List<String>>{};
    raw.headers.forEach((name, values) {
      headers[name.toLowerCase()] = List<String>.from(values);
    });
    return DebugRequest(
      method: raw.method.toUpperCase(),
      uri: raw.uri,
      headers: headers,
      body: Uint8List.fromList(builder.takeBytes()),
      receivedAt: DateTime.now(),
    );
  }


  static DebugRequest forTest({
    String method = 'GET',
    String path = '/',
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
    List<int> body = const [],
  }) {
    final uri = Uri(path: path, queryParameters: query.isEmpty ? null : query);
    final h = <String, List<String>>{};
    for (final e in headers.entries) {
      h[e.key.toLowerCase()] = [e.value];
    }
    return DebugRequest(
      method: method.toUpperCase(),
      uri: uri,
      headers: h,
      body: Uint8List.fromList(body),
      receivedAt: DateTime.now(),
    );
  }
}
