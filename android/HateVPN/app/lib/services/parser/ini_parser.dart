import '../../models/node_spec.dart';
import 'drop_verdict.dart';
import 'mappers/uri_pipeline.dart';




































WireguardSpec? parseWireguardIni(String config,
        {String? nameHint, XrayDropVerdict? dropped}) =>
    parseIniViaPipeline(config, 'wireguard',
            nameHint: nameHint, dropped: dropped)
        as WireguardSpec?;
