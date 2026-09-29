import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:json5/json5.dart';




String canonicalJsonForSingbox(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('Empty input');
  }
  final dynamic parsed = _json5DecodeNormalized(trimmed);
  return jsonEncode(_toJsonEncodable(parsed));
}






dynamic _json5DecodeNormalized(String text) {
  try {
    return json5Decode(text);
  } on FormatException {
    rethrow;
  } on Exception catch (e) {
    String msg;
    try {
      msg = (e as dynamic).message as String;
    } catch (_) {
      msg = e.toString();
    }
    throw FormatException(msg);
  }
}



String prettyJsonForDisplay(String raw) {
  try {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return raw;
    final dynamic parsed = json5Decode(trimmed);
    return const JsonEncoder.withIndent('  ').convert(_toJsonEncodable(parsed));
  } catch (_) {
    return raw;
  }
}




Future<String> prettyJsonForDisplayAsync(String raw) =>
    compute(prettyJsonForDisplay, raw);




({String? result, String? error}) _canonicalEntry(String text) {
  try {
    return (result: canonicalJsonForSingbox(text), error: null);
  } on FormatException catch (e) {
    return (result: null, error: e.message);
  }
}



Future<String> canonicalJsonForSingboxAsync(String text) async {
  final r = await compute(_canonicalEntry, text);
  if (r.error != null) throw FormatException(r.error!);
  return r.result!;
}

dynamic _toJsonEncodable(dynamic value) {
  if (value == null || value is num || value is String || value is bool) {
    return value;
  }
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), _toJsonEncodable(v)));
  }
  if (value is List) {
    return value.map(_toJsonEncodable).toList();
  }
  throw FormatException('Unsupported type: ${value.runtimeType}');
}
