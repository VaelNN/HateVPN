























library;

import 'source_space.dart';






SourceSpace? lexUri(String text, {String formId = 'url'}) {
  final src = text.trim();
  if (src.isEmpty) return null;




  final colon = src.indexOf(':');
  if (colon <= 0) return null;
  final scheme = src.substring(0, colon);


  if (!_kScheme.hasMatch(scheme)) return null;

  var rest = src.substring(colon + 1);
  if (rest.startsWith('//')) rest = rest.substring(2);



  var fragment = '';
  final hash = rest.indexOf('#');
  if (hash >= 0) {
    fragment = rest.substring(hash + 1);
    rest = rest.substring(0, hash);
  }


  var queryRaw = '';
  final qm = rest.indexOf('?');
  if (qm >= 0) {
    queryRaw = rest.substring(qm + 1);
    rest = rest.substring(0, qm);
  }












  var path = '';
  final atInRest = rest.lastIndexOf('@');
  final slash = rest.indexOf('/', atInRest + 1);
  if (slash >= 0) {
    path = rest.substring(slash);
    rest = rest.substring(0, slash);
  }

  final authority = rest;



  var userinfo = '';
  var hostPort = authority;
  final at = authority.lastIndexOf('@');
  if (at >= 0) {
    userinfo = authority.substring(0, at);
    hostPort = authority.substring(at + 1);
  }



  String host;
  var portRaw = '';
  if (hostPort.startsWith('[')) {
    final close = hostPort.indexOf(']');
    if (close < 0) {

      host = hostPort.substring(1);
    } else {
      host = hostPort.substring(1, close);
      final tail = hostPort.substring(close + 1);
      if (tail.startsWith(':')) portRaw = tail.substring(1);
    }
  } else {


    final firstColon = hostPort.indexOf(':');
    if (firstColon < 0) {
      host = hostPort;
    } else if (hostPort.indexOf(':', firstColon + 1) >= 0) {
      host = hostPort;
    } else {
      host = hostPort.substring(0, firstColon);
      portRaw = hostPort.substring(firstColon + 1);
    }
  }

  return SourceSpace(
    formId: formId,
    scheme: scheme,
    authority: authority,
    userinfo: userinfo,
    host: host,



    port: int.tryParse(portRaw),
    portRaw: portRaw,
    path: path,
    fragment: fragment,
    query: lexQuery(queryRaw),
  );
}











QueryPairs lexQuery(String raw) {
  if (raw.isEmpty) return QueryPairs.empty;
  final out = <(String, String)>[];
  for (final part in raw.split('&')) {
    if (part.isEmpty) continue;
    final eq = part.indexOf('=');
    if (eq < 0) {


      out.add((part, ''));
    } else {
      out.add((part.substring(0, eq), part.substring(eq + 1)));
    }
  }
  return QueryPairs(out);
}

final RegExp _kScheme = RegExp(r'^[A-Za-z][A-Za-z0-9+\-.]*$');
