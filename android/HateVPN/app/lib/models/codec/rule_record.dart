






















library;

import 'dart:convert';

import '../../config/consts.dart' show kDirectOutboundTag;
import '../custom_rule.dart';
import 'record_read.dart';



const Set<String> kRuleBodyKeys = {
  'domain',
  'domain_suffix',
  'domain_keyword',
  'ip_cidr',
  'port',
  'port_range',
  'package_name',
  'protocol',
  'network',
  'ip_is_private',
  'source_ip_cidr',
  'source_ip_is_private',
  'inbound',
  'wifi_ssid',
  'wifi_bssid',
  'outbound',
  'action',



};


const JsonEncoder _verbatimText = JsonEncoder.withIndent('  ');










List<CustomRule> splitJsonRuleArrays(
  Iterable<CustomRule> rules, {
  List<String>? notes,
}) {
  final out = <CustomRule>[];
  for (final r in rules) {
    final array = r is CustomRuleJson ? _arrayOf(r.json) : null;
    final items = array?.whereType<Map>().toList() ?? const <Map>[];
    if (items.isEmpty) {
      out.add(r);
      continue;
    }
    final skipped = array!.length - items.length;
    if (skipped > 0) {
      notes?.add('rule "${r.name}": $skipped non-object element(s) of the '
          'JSON array dropped');
    }
    for (var i = 0; i < items.length; i++) {
      out.add(CustomRuleJson(
        id: i == 0 ? r.id : null,
        name: i == 0 ? r.name : '${r.name} #${i + 1}',
        enabled: r.enabled,
        orderNum: r.orderNum,
        json: _verbatimText.convert(items[i]),
      ));
    }
  }
  return out;
}


List<dynamic>? _arrayOf(String text) {
  try {
    final decoded = jsonDecode(text);
    return decoded is List ? decoded : null;
  } on FormatException {
    return null;
  }
}


Map<String, dynamic> ruleToRecord(CustomRule r) {
  final out = <String, dynamic>{
    'kind': r is CustomRuleJson ? 'inline' : r.kind.name,
    'id': r.id,
    'name': r.name,
    'enabled': r.enabled,
    if (r.orderNum != null) 'num': r.orderNum,
  };
  switch (r) {
    case CustomRuleInline():
      out['body'] = _ruleBody(r, includeMatch: true);
    case CustomRuleSrs():


      out['refs'] = List<String>.of(r.srsUrls);
      if (r.updateIntervalHours != kDefaultSrsTtlHours) {
        out['update_interval_hours'] = r.updateIntervalHours;
      }
      out['body'] = _ruleBody(r, includeMatch: false);
    case CustomRulePreset():
      out['ref'] = r.presetId;
      if (r.varsValues.isNotEmpty) {
        out['vars'] = Map<String, String>.of(r.varsValues);
      }
    case CustomRuleJson():
      out['verbatim'] = true;
      final body = _objectOf(r.json);
      if (body != null) out['body'] = body;
  }
  if (r.dns != null) out['dns'] = r.dns!.toJson();
  if (r.resolve != null) out['resolve'] = r.resolve!.toJson();
  return out;
}

Map<String, dynamic> _ruleBody(CustomRule r, {required bool includeMatch}) {
  final b = <String, dynamic>{};
  if (includeMatch) {
    if (r.domains.isNotEmpty) b['domain'] = List<String>.of(r.domains);
    if (r.domainSuffixes.isNotEmpty) {
      b['domain_suffix'] = List<String>.of(r.domainSuffixes);
    }
    if (r.domainKeywords.isNotEmpty) {
      b['domain_keyword'] = List<String>.of(r.domainKeywords);
    }
    if (r.ipCidrs.isNotEmpty) b['ip_cidr'] = List<String>.of(r.ipCidrs);
  }


  final ports = r.intPorts;
  if (ports.isNotEmpty) b['port'] = ports;
  if (r.portRanges.isNotEmpty) b['port_range'] = List<String>.of(r.portRanges);
  if (r.packages.isNotEmpty) b['package_name'] = List<String>.of(r.packages);
  if (r.protocols.isNotEmpty) b['protocol'] = List<String>.of(r.protocols);
  if (r.network.isNotEmpty) b['network'] = List<String>.of(r.network);
  if (r.ipIsPrivate) b['ip_is_private'] = true;
  if (r.sourceIpCidrs.isNotEmpty) {
    b['source_ip_cidr'] = List<String>.of(r.sourceIpCidrs);
  }
  if (r.sourceIpIsPrivate) b['source_ip_is_private'] = true;
  if (r.inbounds.isNotEmpty) b['inbound'] = List<String>.of(r.inbounds);
  if (r.wifiSsids.isNotEmpty) b['wifi_ssid'] = List<String>.of(r.wifiSsids);
  if (r.wifiBssids.isNotEmpty) b['wifi_bssid'] = List<String>.of(r.wifiBssids);


  if (r.outbound == kOutboundReject) {
    b['action'] = 'reject';
  } else {
    b['outbound'] = r.outbound;
  }
  return b;
}








RecordRead<CustomRule> ruleFromRecord(
  Map<String, dynamic> j, {
  bool unknownAsVerbatim = false,
}) {
  final kind = j['kind'];
  if (kind is! String || kind.isEmpty) {
    return const RecordRead.drop('rule without kind');
  }
  final rawId = j['id'];
  final id = rawId is String && rawId.trim().isNotEmpty ? rawId : null;
  final rawName = j['name'];
  final name = rawName is String ? rawName : '';
  final enabled = j['enabled'] != false;
  final rawNum = j['num'];
  final orderNum = rawNum is num ? rawNum.toInt() : null;

  switch (kind) {
    case 'inline':
    case 'srs':
      final rawBody = j['body'];
      final body = rawBody is Map ? rawBody.cast<String, dynamic>() : null;
      if (rawBody != null && body == null) {
        return RecordRead.drop('rule "$name": body is not an object');
      }
      if (kind == 'inline' && j['verbatim'] == true) {
        return RecordRead.ok(CustomRuleJson(
          id: id,
          name: name,
          enabled: enabled,
          orderNum: orderNum,
          json: body == null ? '' : _verbatimText.convert(body),
        ));
      }
      final b = body ?? const <String, dynamic>{};
      final unknown = [
        for (final k in b.keys)
          if (!kRuleBodyKeys.contains(k)) k,




        if (b.containsKey('action') && b['action'] != 'reject') 'action',
      ]..sort();
      if (kind == 'inline' && unknownAsVerbatim && unknown.isNotEmpty) {
        return RecordRead.ok(
          CustomRuleJson(
            id: id,
            name: name,
            enabled: enabled,
            orderNum: orderNum,
            json: _verbatimText.convert(b),
          ),
          unknownKeys: unknown,
        );
      }
      final outbound = _outboundOf(b);
      final dns = RuleDns.fromJson(j['dns']);
      final resolve = RuleResolve.fromJson(j['resolve']);
      if (kind == 'inline') {
        return RecordRead.ok(
          CustomRuleInline(
            id: id,
            name: name,
            enabled: enabled,
            orderNum: orderNum,
            domains: _strList(b['domain']),
            domainSuffixes: _strList(b['domain_suffix']),
            domainKeywords: _strList(b['domain_keyword']),
            ipCidrs: _strList(b['ip_cidr']),
            ports: _portList(b['port']),
            portRanges: _strList(b['port_range']),
            packages: _strList(b['package_name']),
            protocols: _strList(b['protocol']),
            network: _strList(b['network']),
            ipIsPrivate: b['ip_is_private'] == true,
            sourceIpCidrs: _strList(b['source_ip_cidr']),
            sourceIpIsPrivate: b['source_ip_is_private'] == true,
            inbounds: _strList(b['inbound']),
            wifiSsids: _strList(b['wifi_ssid']),
            wifiBssids: _strList(b['wifi_bssid']),
            outbound: outbound,
            dns: dns,
            resolve: resolve,
          ),
          unknownKeys: unknown,
        );
      }
      final refs = _strList(j['refs']);
      final ref = j['ref'];
      return RecordRead.ok(
        CustomRuleSrs(
          id: id,
          name: name,
          enabled: enabled,
          orderNum: orderNum,

          srsUrls: refs.isNotEmpty ? refs : [if (ref is String) ref],
          updateIntervalHours:
              CustomRuleSrs.ttlHoursFrom(j['update_interval_hours']),
          ports: _portList(b['port']),
          portRanges: _strList(b['port_range']),
          packages: _strList(b['package_name']),
          protocols: _strList(b['protocol']),
          network: _strList(b['network']),
          ipIsPrivate: b['ip_is_private'] == true,
          sourceIpCidrs: _strList(b['source_ip_cidr']),
          sourceIpIsPrivate: b['source_ip_is_private'] == true,
          inbounds: _strList(b['inbound']),
          wifiSsids: _strList(b['wifi_ssid']),
          wifiBssids: _strList(b['wifi_bssid']),
          outbound: outbound,
          dns: dns,
          resolve: resolve,
        ),
        unknownKeys: unknown,
      );
    case 'preset':
      final ref = j['ref'];
      final vars = j['vars'];
      return RecordRead.ok(CustomRulePreset(
        id: id,
        name: name,
        enabled: enabled,
        orderNum: orderNum,
        presetId: ref is String ? ref : '',
        varsValues: vars is Map
            ? {
                for (final e in vars.entries)
                  e.key.toString(): e.value?.toString() ?? '',
              }
            : const {},
      ));
    default:
      return RecordRead.drop('rule "$name": unknown kind "$kind"');
  }
}



String _outboundOf(Map<String, dynamic> body) {
  if (body['action'] == 'reject') return kOutboundReject;
  final o = body['outbound'];
  return o is String ? o : kDirectOutboundTag;
}


Map<String, dynamic>? _objectOf(String text) {
  try {
    final decoded = jsonDecode(text);
    return decoded is Map ? decoded.cast<String, dynamic>() : null;
  } on FormatException {
    return null;
  }
}



List<String> _strList(Object? v) {
  if (v == null) return const [];
  if (v is List) return [for (final e in v) e.toString()];
  if (v is String) return v.isEmpty ? const [] : [v];
  return [v.toString()];
}



List<String> _portList(Object? v) => [
      for (final e in _strList(v))
        if (int.tryParse(e) case final p? when p >= 0 && p <= 65535) '$p',
    ];
