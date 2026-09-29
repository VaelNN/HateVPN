

















typedef _Visit = void Function(String address, Map node, String field);

class TemplateOverlay {
  TemplateOverlay._();






  static void apply(
      Map<String, dynamic> templateJson, Map<String, String> overlay) {
    if (overlay.isEmpty) return;
    _walk(templateJson, (address, node, field) {
      final english = node[field] as String;
      final v = overlay[english];
      if (v == null || v.isEmpty) return;



      if (v.startsWith('@') || v.contains('{')) return;
      node[field] = v;
    });
  }





  static Map<String, String> extract(Map<String, dynamic> templateJson) {
    final out = <String, String>{};
    _walk(templateJson, (address, node, field) {
      final v = node[field] as String;
      out[v] = v;
    });
    return out;
  }





  static Map<String, String> parseLocaleFile(Map<String, dynamic> json) {
    final out = <String, String>{};
    json.forEach((key, value) {
      if (value is String) {
        out[key] = value;
      } else if (value is Map && value['value'] is String) {
        out[key] = value['value'] as String;
      }
    });
    return out;
  }












  static List<Map> conditionalBranches(dynamic item) {
    if (item is List) return [for (final x in item) ...conditionalBranches(x)];
    if (item is! Map) return const [];
    final cond = item['#if'];
    if (cond is! Map) return [item];
    return [
      for (final key in const ['#value', '#else'])
        ...conditionalBranches(cond[key]),
    ];
  }

  static void _walk(Map<String, dynamic> t, _Visit visit) {
    void str(dynamic node, String address, String field) {
      if (node is! Map) return;
      final v = node[field];
      if (v is String && v.isNotEmpty) visit(address, node, field);
    }




    void varNode(dynamic v, String base) {
      if (v is! Map || v['name'] is! String) return;
      str(v, '$base.title', 'title');
      str(v, '$base.tooltip', 'tooltip');
      final opts = v['options'];
      if (opts is List) {
        for (final o in opts) {
          if (o is Map && o['value'] is String) {
            str(o, '$base.option.${o['value']}', 'title');
          }
        }
      }
    }



    final sections = t['sections'];
    if (sections is List) {
      for (final s in sections) {
        if (s is! Map) continue;
        final id = s['id'];
        if (id is! String || id.isEmpty) continue;
        str(s, 'section.$id.name', 'name');
        str(s, 'section.$id.description', 'description');
        final vars = s['vars'];
        if (vars is List) {
          for (final v in vars) {
            if (v is Map && v['name'] is String) {
              varNode(v, 'var.${v['name']}');
            }
          }
        }
      }
    }




    final rules = t['selectable_rules'];
    if (rules is List) {
      for (final r in rules) {
        if (r is! Map) continue;
        final pid = r['preset_id'];
        if (pid is! String || pid.isEmpty) continue;
        str(r['ui'], 'preset.$pid.label', 'label');
        str(r['ui'], 'preset.$pid.description', 'description');
        final vars = r['vars'];
        if (vars is List) {
          for (final v in vars) {
            if (v is Map && v['name'] is String) {
              varNode(v, 'preset.$pid.var.${v['name']}');
            }
          }
        }
        final ds = r['dns_servers'];
        if (ds is List) {
          for (var i = 0; i < ds.length; i++) {





            for (final d in conditionalBranches(ds[i])) {
              final tag = d['tag'];
              str(
                  d,
                  tag is String
                      ? 'preset.$pid.dns_server.$tag.description'
                      : 'preset.$pid.dns_server.#$i.description',
                  'description');
            }
          }
        }
      }
    }


    final gt = t['group_templates'];
    if (gt is Map) {
      final magic = gt['magic_nodes'];
      if (magic is Map) {
        for (final e in magic.entries) {
          str(e.value, 'magic.${e.key}.title', 'title');
        }
      }
    }


    final directions = t['default_directions'];
    if (directions is List) {
      for (final c in directions) {
        if (c is Map && c['tag'] is String) {
          str(c, 'direction.${c['tag']}.label', 'label');
        }
      }
    }




    final dnsOptions = t['dns_options'];
    if (dnsOptions is Map) {
      final servers = dnsOptions['servers'];
      if (servers is List) {
        for (final s in servers) {
          if (s is! Map) continue;
          final server = s['server'];
          final tag = server is Map ? server['tag'] : null;
          if (tag is! String || tag.isEmpty) continue;
          str(s, 'dns_server.$tag.description', 'description');
          final vars = s['vars'];
          if (vars is List) {
            for (final v in vars) {
              if (v is Map && v['name'] is String) {
                varNode(v, 'dns_server.$tag.var.${v['name']}');
              }
            }
          }
        }
      }
    }



    final ping = t['ping_options'];
    if (ping is Map) {
      final presets = ping['presets'];
      if (presets is List) {
        for (final p in presets) {
          if (p is Map && p['id'] is String) {
            str(p, 'ping.${p['id']}.name', 'name');
          }
        }
      }
    }
    final speed = t['speed_test_options'];
    if (speed is Map) {
      final servers = speed['servers'];
      if (servers is List) {
        for (final s in servers) {
          if (s is Map && s['id'] is String) {
            str(s, 'speed.${s['id']}.name', 'name');
          }
        }
      }
    }
  }
}
