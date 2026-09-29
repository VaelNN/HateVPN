import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';

import '../../config/consts.dart';
import '../../models/custom_rule.dart';
import '../../models/dns_ref.dart';
import '../../models/parser_config.dart';
import '../../models/source_chain.dart' show kChainOutboundType;
import '../../models/node_warning.dart' show RegistryWarning;
import '../contract/body_edit.dart' show editBodyPath;
import '../contract/body_sanitizer.dart' show fieldAllowedOn;
import '../core_duration.dart';
import '../json_clone.dart';
import '../parser/uri_utils.dart' show isValidRealityPublicKey;
import '../parser/utls_fingerprint.dart';
import '../settings_storage.dart' show SettingsStorage, TunAppsConfig;
import 'detour_yields.dart' show yieldToBuildDetour;
import 'if_engine.dart' show Dropped, walk;
import 'preset_expand.dart';
import 'rule_set_registry.dart';













part 'post_steps/tls_transforms.dart';
part 'post_steps/tun_packages.dart';
part 'post_steps/dns_rules.dart';
part 'post_steps/custom_rules.dart';
part 'post_steps/dns_servers.dart';
part 'post_steps/heal_preset_tag_prefix.dart';
part 'post_steps/heal_dangling_resolve_servers.dart';
part 'post_steps/heal_dangling_dns_resolvers.dart';
part 'post_steps/heal_detour_dropped_dns.dart';
part 'post_steps/heal_legacy_dns_strategy.dart';
part 'post_steps/heal_unknown_utls_fingerprints.dart';
part 'post_steps/heal_invalid_reality.dart';
part 'post_steps/sanitize_outbound_graph.dart';
part 'post_steps/sanitize_urltest_timings.dart';
