











library;

import '../../models/node_warning.dart';



const kWarningCodes = <Type, String>{
  UnsupportedProtocolWarning: 'protocol_unsupported',
  NaiveBuildTagWarning: 'naive_unavailable',
  UnknownFingerprintWarning: 'utls_fp_unknown',


  RealityFingerprintWarning: 'reality_fp_not_chrome',
  XhttpParamResetWarning: 'xhttp_param_reset',

  XhttpModeForcedPacketUpWarning: 'xhttp_mode_forced_packet_up',
  UnknownObfsWarning: 'obfs_unknown',
  MissingObfsPasswordWarning: 'obfs_password_missing',
  DetourCycleBrokenWarning: 'detour_cycle_broken',
  DetourTargetMissingWarning: 'detour_target_missing',
  DetourToGroupWarning: 'detour_to_group',
  DetourChainTooDeepWarning: 'detour_chain_too_deep',
  GroupMemberMissingWarning: 'group_member_missing',





  Awg3HeaderKeyInvalidWarning: 'awg3_header_key_invalid',
  Awg3PaddingTooShortWarning: 'awg3_padding_too_short',
  Awg3RandomTrailersWideHeadersWarning: 'awg3_random_trailers_wide_headers',
  PacketEncodingUnknownWarning: 'packet_encoding_unknown',


  DialerProxyUnusableWarning: 'dialer_proxy_unusable',






  DuplicateNodeWarning: 'duplicate',



  UnknownNodeTypeWarning: 'unknown_node_type',
};


String? warningCodeOf(NodeWarning w) =>
    w is RegistryWarning ? w.code : kWarningCodes[w.runtimeType];



















String? handwrittenWarningPath(NodeWarning w) => switch (w) {
      PacketEncodingUnknownWarning() => 'packet_encoding',
      UnknownFingerprintWarning() => 'tls.utls.fingerprint',
      RealityFingerprintWarning() => 'tls.utls.fingerprint',
      UnknownObfsWarning() => 'obfs.type',
      MissingObfsPasswordWarning() => 'obfs.password',



      XhttpParamResetWarning(:final field) => 'transport.$field',
      _ => null,
    };
