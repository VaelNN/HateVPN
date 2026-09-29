part of '../post_steps.dart';








String? templateDnsServerTag(Map<String, dynamic> entry) {
  final server = entry['server'];
  if (server is! Map) return null;
  final tag = server['tag'];
  return (tag is String && tag.isNotEmpty) ? tag : null;
}



Map<String, Map<String, dynamic>> templateDnsServersByTag(
  List<Map<String, dynamic>> templateServers,
) {
  return {
    for (final s in templateServers)
      if (templateDnsServerTag(s) != null) templateDnsServerTag(s)!: s,
  };
}






















Map<String, dynamic>? resolveTemplateDnsServerBody(
  Map<String, dynamic> wrapper, {
  Map<String, dynamic> varValues = const {},
  Map<String, String> globalVars = const {},
  List<String>? unknownVarsOut,
}) {
  final server = wrapper['server'];
  if (server is! Map) return null;
  final body = deepCopyJson(Map<String, dynamic>.from(server));
  final varsMap = <String, dynamic>{};
  for (final d
      in (wrapper['vars'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()) {
    final name = d['name']?.toString();
    if (name == null || name.isEmpty) continue;
    final user = varValues[name]?.toString().trim();
    if (user != null && user.isNotEmpty) {
      varsMap[name] = user;
    } else {
      final def = d['default_value']?.toString() ?? '';
      varsMap[name] = def.isEmpty ? null : def;
    }
  }
  for (final e in globalVars.entries) {
    varsMap.putIfAbsent(e.key, () => e.value.isEmpty ? null : e.value);
  }
  final result = walk(body, (name) {
    if (!varsMap.containsKey(name)) {
      unknownVarsOut?.add(name);
      return Dropped.instance;
    }
    final v = varsMap[name];
    return v ?? Dropped.instance;
  });
  return result is Map<String, dynamic> ? result : null;
}
























Future<List<DnsServerRef>> resolveDnsServersList({
  required List<Map<String, dynamic>> templateServers,
  required Map<String, Map<String, dynamic>> presetServersByTag,
  Map<String, String> presetIdByTag = const {},
}) async {
  final stored = await SettingsStorage.getDnsServers();


  final templateByTag = templateDnsServersByTag(templateServers);


  final result = <DnsServerRef>[];
  final seen = <String>{};
  for (final entry in stored) {
    if (seen.contains(entry.tag)) continue;
    final keep = switch (entry) {
      DnsServerInline() => true,
      DnsServerTemplate() => templateByTag.containsKey(entry.tag),
      DnsServerPreset() => presetServersByTag.containsKey(entry.tag),
    };
    if (!keep) continue;
    result.add(entry);
    seen.add(entry.tag);
  }


  for (final tag in presetServersByTag.keys) {
    if (seen.contains(tag)) continue;
    result.add(DnsServerPreset(
        enabled: true, tag: tag, presetId: presetIdByTag[tag] ?? ''));
    seen.add(tag);
  }

  for (final s in templateServers) {
    final tag = templateDnsServerTag(s);
    if (tag == null) continue;
    if (seen.contains(tag)) continue;
    final enabled = s['enabled'] != false;
    result.add(DnsServerTemplate(enabled: enabled, tag: tag));
    seen.add(tag);
  }


  if (!const ListEquality<DnsServerRef>().equals(stored, result)) {
    await SettingsStorage.saveDnsServers(result);
  }
  return result;
}




































List<Map<String, dynamic>> resolveDnsServersBodies({
  required List<DnsServerRef> resolved,
  required Map<String, Map<String, dynamic>> templateByTag,
  required Map<String, Map<String, dynamic>> presetServersByTag,
  Set<String>? knownOutboundTags,
  Set<String> ruleReferencedTags = const {},
  List<String>? warningsOut,


  Set<String>? tailscaleEndpointTags,

  Set<String>? detourDroppedOut,

  Map<String, String> globalVars = const {},
}) {
  final out = <Map<String, dynamic>>[];
  final seen = <String>{};
  final detourDropped = <String>{};

  bool dropForDetour(Map<String, dynamic> body, String tag) {
    final dangling = normalizeDnsDetour(body, knownOutbounds: knownOutboundTags);
    if (dangling == null) return false;
    warningsOut?.add(
        'DNS server "$tag" dropped: its detour "$dangling" is not in the config.');
    detourDropped.add(tag);
    detourDroppedOut?.add(tag);
    return true;
  }

  for (final entry in resolved) {
    final tag = entry.tag;
    if (tag.isEmpty) continue;
    if (!entry.enabled &&
        !presetServersByTag.containsKey(tag) &&
        !ruleReferencedTags.contains(tag)) {
      continue;
    }
    if (seen.contains(tag)) continue;
    final unknownVars = <String>[];
    final Map<String, dynamic>? body = switch (entry) {
      DnsServerInline(:final body) => Map<String, dynamic>.from(body),
      DnsServerTemplate(:final varValues) => switch (templateByTag[tag]) {
          final t? => resolveTemplateDnsServerBody(t,
              varValues: varValues,
              globalVars: globalVars,
              unknownVarsOut: unknownVars),
          null => null,
        },
      DnsServerPreset() => switch (presetServersByTag[tag]) {
          final p? => Map<String, dynamic>.from(p),
          null => null,
        },
    };
    if (body == null) continue;
    for (final name in unknownVars.toSet()) {
      warningsOut?.add('DNS server "$tag": "@$name" is declared neither by '
          'the server nor by the template, the key with it is left out.');
    }
    body
      ..remove('enabled')
      ..remove('description')
      ..remove('_preset_label')
      ..remove('_preset_id')
      ..remove('_origin')
      ..remove('_overrides');
    body['tag'] = tag;




    if (entry is DnsServerTemplate && dnsServerMissingAddress(body)) {
      reportFragmentDropped(tag, 'dns.servers', 'server');
      continue;
    }
    seen.add(tag);
    if (dropForDetour(body, tag)) continue;
    out.add(body);
  }
  if (tailscaleEndpointTags != null) {
    _sanitizeTailscaleDnsServers(out, tailscaleEndpointTags, warningsOut);
  }
  _filterDnsGroupMembers(
    out,
    allRefTags: {
      for (final e in resolved)
        if (e.tag.isNotEmpty) e.tag,
    },
    detourDropped: detourDropped,
    detourDroppedOut: detourDroppedOut,
    warningsOut: warningsOut,
  );
  return out;
}







void _sanitizeTailscaleDnsServers(
  List<Map<String, dynamic>> out,
  Set<String> endpointTags,
  List<String>? warningsOut,
) {
  final usedEndpoints = <String>{};
  out.removeWhere((body) {
    if (body['type'] != 'tailscale') return false;
    final tag = body['tag']?.toString() ?? '';
    final ep = body['endpoint'];
    if (ep is! String || ep.isEmpty || !endpointTags.contains(ep)) {
      warningsOut?.add(
          'DNS server "$tag" dropped: its Tailscale endpoint "${ep ?? ''}" is not in the config.');
      return true;
    }
    if (!usedEndpoints.add(ep)) {
      warningsOut?.add(
          'DNS server "$tag" dropped: Tailscale endpoint "$ep" already has a DNS server (the core allows one per node).');
      return true;
    }
    return false;
  });
}
























void _filterDnsGroupMembers(
  List<Map<String, dynamic>> out, {
  required Set<String> allRefTags,
  Set<String> detourDropped = const {},
  Set<String>? detourDroppedOut,
  List<String>? warningsOut,
}) {
  final emittedTags = <String>{
    for (final b in out)
      if (b['tag'] is String) b['tag'] as String,
  };


  final dropped = {...detourDropped};
  for (var changed = true; changed;) {
    changed = false;
    for (final body in out) {
      final tag = body['tag'];
      if (body['type'] != 'group' || tag is! String) continue;
      if (dropped.contains(tag)) continue;
      final members = [
        for (final raw in (body['servers'] as List<dynamic>? ?? const []))
          raw?.toString() ?? '',
      ];
      final alive = members.any((m) =>
          m != tag &&
          allRefTags.contains(m) &&
          !dropped.contains(m) &&
          emittedTags.contains(m));
      if (!alive && members.any(dropped.contains)) {
        dropped.add(tag);
        changed = true;
      }
    }
  }
  out.removeWhere((body) {
    final tag = body['tag'];
    if (body['type'] != 'group' ||
        tag is! String ||
        !dropped.contains(tag) ||
        detourDropped.contains(tag)) {
      return false;
    }
    warningsOut?.add("DNS group '$tag' dropped: its members were dropped "
        '(dangling detour)');
    detourDroppedOut?.add(tag);
    return true;
  });
  for (final body in out) {
    if (body['type'] != 'group') continue;
    final selfTag = body['tag'] as String;
    final kept = <String>[];
    for (final raw in (body['servers'] as List<dynamic>? ?? const [])) {
      final m = raw?.toString() ?? '';
      final String? dropReason;
      if (m == selfTag) {
        dropReason = 'itself';
      } else if (kept.contains(m)) {
        dropReason = 'duplicate';
      } else if (m.isEmpty || !allRefTags.contains(m)) {

        dropReason = 'unknown';
      } else if (dropped.contains(m)) {
        dropReason = 'dangling detour';
      } else if (!emittedTags.contains(m)) {

        dropReason = 'disabled';
      } else {
        dropReason = null;
      }
      if (dropReason != null) {
        warningsOut?.add(
          "DNS group '$selfTag': member '$m' dropped ($dropReason)",
        );
      } else {
        kept.add(m);
      }
    }
    body['servers'] = kept;
  }
}
