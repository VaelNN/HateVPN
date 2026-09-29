import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/codec/source_record.dart';
import 'package:lxbox/models/node_spec.dart';
import 'package:lxbox/models/server_list.dart';
import 'package:lxbox/models/template_vars.dart';
import 'package:lxbox/services/parser/uri_utils.dart' show newUuidV4;











void main() {
  test('SocksSpec → JSON outbound → UserServer.fromJson preserves tag', () {



    const userTag = 'my-socks-out';
    final spec = SocksSpec(
      id: newUuidV4(),
      tag: userTag,
      label: userTag,
      server: '127.0.0.1',
      port: 1080,
      rawSource: '',
      username: '',
      password: '',
    );
    final outboundMap = spec.emit(TemplateVars.empty).map;
    final us = UserServer(
      id: newUuidV4(),
      name: 'My Local SOCKS',
      enabled: true,
      tagPrefix: '',
      detourPolicy: DetourPolicy.defaults,
      origin: UserSource.manual,
      rawBody: jsonEncode(outboundMap),
      nodes: [spec],
    );


    final restored =
        sourceFromRecord(sourceToRecord(us)).value! as UserServer;


    expect(restored, us);
    expect(restored.name, '');
    expect(restored.nodes.length, 1);
    final node = restored.nodes.first;
    expect(node, isA<SocksSpec>());
    expect(node.tag, userTag,
        reason: 'tag должен survive round-trip — иначе routing rules '
            'ссылающиеся на my-socks-out сломаются');
    final socks = node as SocksSpec;
    expect(socks.server, '127.0.0.1');
    expect(socks.port, 1080);
  });

  test('SocksSpec with credentials → round-trip preserves user/pass', () {
    final spec = SocksSpec(
      id: newUuidV4(),
      tag: 'proxy-with-auth',
      label: 'proxy-with-auth',
      server: '10.0.0.1',
      port: 2080,
      rawSource: '',
      username: 'alice',
      password: 's3cret',
    );
    final us = UserServer(
      id: newUuidV4(),
      name: 'Authenticated',
      enabled: true,
      tagPrefix: '',
      detourPolicy: DetourPolicy.defaults,
      origin: UserSource.manual,
      rawBody: jsonEncode(spec.emit(TemplateVars.empty).map),
      nodes: [spec],
    );
    final restored =
        sourceFromRecord(sourceToRecord(us)).value! as UserServer;
    final socks = restored.nodes.first as SocksSpec;
    expect(socks.tag, 'proxy-with-auth');
    expect(socks.username, 'alice');
    expect(socks.password, 's3cret');
  });
}
