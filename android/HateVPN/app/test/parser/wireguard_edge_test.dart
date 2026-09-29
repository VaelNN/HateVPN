import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/node_spec.dart';
import 'package:lxbox/models/template_vars.dart';
import 'package:lxbox/services/contract/registry.dart';
import 'package:lxbox/services/parser/engine/section_loader.dart';
import 'package:lxbox/services/parser/json_parsers.dart';
import 'package:lxbox/services/parser/mappers/draft_sections.dart';
import 'package:lxbox/services/parser/uri_utils.dart';
import 'parse_link_as.dart';






const _testPub = 'QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVowMTIzNDU=';

const _testPrivSlash = 'Bw4VHCMqMTg/Rk1UW2JpcHd+hYyTmqGor7a9xMvS2eA=';


void main() {


  setUpAll(() async {
    await ContractRegistry.I.loadFromDirectory('assets/contract');
    await MapperSections.I
        .loadDrafts(dir: 'assets/contract_draft', files: kDraftFiles);
  });

  group('§106 — raw `/` в private key (userInfo)', () {
    test('сырой `/` в ключе → парсится, privateKey восстановлен', () {
      final spec = parseLinkAs<WireguardSpec>(
          'wireguard://$_testPrivSlash@'
          'h.example:51820?publickey=$_testPub&address=10.0.0.2/32');
      expect(spec, isNotNull, reason: 'раньше → null (rejected)');
      expect(spec!.privateKey, _testPrivSlash);
    });

    test('уже-`%2F`-энкоден → без двойного декода', () {
      final encoded = _testPrivSlash.replaceAll('/', '%2F');
      final spec = parseLinkAs<WireguardSpec>(
          'wireguard://$encoded@h.example:51820'
          '?publickey=$_testPub&address=10.0.0.2/32');
      expect(spec!.privateKey, _testPrivSlash);
    });

    test('encodeUserInfoSlashes — query со `/` не трогает', () {
      const uri = 'wireguard://K/EY@h:51820?address=10.0.0.2/32';
      final out = encodeUserInfoSlashes(uri);
      expect(out, 'wireguard://K%2FEY@h:51820?address=10.0.0.2/32');
    });
  });

  group('§106 — bare IP → CIDR', () {
    test('ensureCidr helper', () {
      expect(ensureCidr('172.16.0.2'), '172.16.0.2/32');
      expect(ensureCidr('::1'), '::1/128');
      expect(ensureCidr('10.0.0.2/32'), '10.0.0.2/32');
      expect(ensureCidr('fd00::1/64'), 'fd00::1/64');
      expect(ensureCidr(''), '');
    });

    test('URI: bare address + bare allowed_ips → CIDR в emit', () {
      final spec = parseLinkAs<WireguardSpec>(
          'wireguard://$_testPub@h.example:51820?publickey=$_testPub&'
          'address=172.16.0.2&allowedips=10.0.0.5,fd00::2');
      expect(spec!.localAddresses, ['172.16.0.2/32']);
      expect(spec.peers.first.allowedIps, ['10.0.0.5/32', 'fd00::2/128']);
      final m = spec.emit(TemplateVars.empty).map;
      expect(m['address'], ['172.16.0.2/32']);
      expect((m['peers'] as List).first['allowed_ips'],
          ['10.0.0.5/32', 'fd00::2/128']);
    });

    test('JSON endpoint: bare address/allowed_ips → CIDR', () {
      final spec = parseSingboxEntry({
        'type': 'wireguard',
        'tag': 'wg',
        'private_key': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaA=',
        'address': ['172.16.0.2'],
        'peers': [
          {
            'address': 'h.example',
            'port': 51820,
            'public_key': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbA=',
            'allowed_ips': ['172.16.0.5', '::1'],
          }
        ],
      }) as WireguardSpec;
      expect(spec.localAddresses, ['172.16.0.2/32']);
      expect(spec.peers.first.allowedIps, ['172.16.0.5/32', '::1/128']);
    });
  });
}
