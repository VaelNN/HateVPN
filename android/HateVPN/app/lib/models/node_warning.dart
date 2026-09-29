





library;

import '../services/contract/registry_warning.dart';
import '../services/l10n/get_local_text.dart';
import '../services/l10n/locale_controller.dart';

enum WarningSeverity { info, warning, error }

sealed class NodeWarning {
  const NodeWarning();

















  static NodeWarning byCode(
    String code, {
    required String path,
    required String value,
  }) =>
      switch (code) {







        'ech_ignored' => RegistryWarning(
            code: code,
            path: path,
            value: value,



            params: {'query_name': path},
          ),
        'ws_early_data_converted' => RegistryWarning(
            code: code,
            path: path,
            value: value,


            params: {'max_early_data': value},
          ),
        'naive_extra_headers_invalid' => RegistryWarning(
            code: code,
            path: path,
            value: value,
            params: {'entry': value},
          ),













        _ => RegistryWarning(code: code, path: path, value: value),
      };






  String messageWith(GetLocalText t);


  String message() => messageWith(getLocalText);



  String renderEn() => messageWith(GetLocalText.en);

  WarningSeverity get severity;





  String get ownerTag => '';




  bool get applied => true;




  List<Object?> get props => const [];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NodeWarning &&
          runtimeType == other.runtimeType &&
          _propsEqual(props, other.props));

  @override
  int get hashCode => Object.hashAll([runtimeType, ...props]);

  @override
  String toString() => '$runtimeType(${props.join(', ')})';
}

bool _propsEqual(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}



List<NodeWarning> sortedDropWarnings(List<NodeWarning> dropped) {
  final out = <NodeWarning>[];
  for (final level in const [
    WarningSeverity.error,
    WarningSeverity.warning,
    WarningSeverity.info,
  ]) {
    out.addAll(dropped.where((w) => w.severity == level));
  }
  return out;
}


List<NodeWarning> maskSecretDropWarnings(List<NodeWarning> dropped) {
  return [
    for (final w in dropped)
      if (w is RegistryWarning) w.withSecretValueMasked() else w,
  ];
}








List<NodeWarning> summaryDropped(List<NodeWarning> dropped) {
  if (dropped.isEmpty) return const [];
  final seen = <(NodeWarning, String)>{};
  final unique = [
    for (final w in dropped)
      if (seen.add((w, w.ownerTag))) w,
  ];
  return List.unmodifiable(
      maskSecretDropWarnings(sortedDropWarnings(unique)));
}




final class UnsupportedProtocolWarning extends NodeWarning {
  final String scheme;
  const UnsupportedProtocolWarning(this.scheme);

  @override
  List<Object?> get props => [scheme];

  @override
  String messageWith(GetLocalText t) => t.s("Protocol \"%s\" is not supported.", scheme);

  @override
  WarningSeverity get severity => WarningSeverity.error;
}


















final class NaiveBuildTagWarning extends NodeWarning {
  const NaiveBuildTagWarning();

  @override
  String messageWith(GetLocalText t) => t.s("NaïveProxy is not included in this libbox build (rebuild with -tags with_naive_outbound).");

  @override
  WarningSeverity get severity => WarningSeverity.error;
}






final class UnknownFingerprintWarning extends NodeWarning {
  final String value;
  const UnknownFingerprintWarning(this.value);

  @override
  List<Object?> get props => [value];

  @override
  String messageWith(GetLocalText t) => t.s("Unknown uTLS fingerprint \"%s\" replaced with \"chrome\" (would otherwise break the whole config).", value);

  @override
  WarningSeverity get severity => WarningSeverity.warning;
}














final class RealityFingerprintWarning extends NodeWarning {
  final String value;
  const RealityFingerprintWarning(this.value);

  @override
  List<Object?> get props => [value];

  @override
  String messageWith(GetLocalText t) => t.s("REALITY with uTLS fingerprint \"%s\": Xray servers since v26.9.8 reject this ClientHello. If the connection fails, try \"chrome\".", value);





  @override
  WarningSeverity get severity => registrySeverity('reality_fp_not_chrome');
}



enum XhttpResetReason {

  invalidEnumValue,


  invalidPlacementValue,


  placementRequiresPacketUp,


  getRequiresPacketUp,
}





final class XhttpParamResetWarning extends NodeWarning {
  final String field;
  final XhttpResetReason reason;


  final String value;

  const XhttpParamResetWarning(this.field, this.reason, {this.value = ''});

  @override
  List<Object?> get props => [field, reason, value];

  @override
  String messageWith(GetLocalText t) {
    final why = switch (reason) {
      XhttpResetReason.invalidEnumValue =>
        t.s("value \"%1\$s\" is not a valid %2\$s", value, field),
      XhttpResetReason.invalidPlacementValue =>
        t.s("value \"%s\" is not valid", value),
      XhttpResetReason.placementRequiresPacketUp =>
        t.s("header/cookie placement requires packet-up mode"),
      XhttpResetReason.getRequiresPacketUp => t.s("GET requires packet-up mode"),
    };
    return t.s("XHTTP \"%1\$s\" reset to default — %2\$s (would otherwise break the whole config).", field, why);
  }

  @override
  WarningSeverity get severity => WarningSeverity.warning;
}













final class XhttpModeForcedPacketUpWarning extends NodeWarning {
  const XhttpModeForcedPacketUpWarning();

  @override
  String messageWith(GetLocalText t) => t.s(
      "XHTTP mode was set to \"packet-up\": the link asks for header uplink data placement, which the core accepts only in that mode (the config would otherwise fail to load).");

  @override
  WarningSeverity get severity => WarningSeverity.warning;
}








final class UnknownObfsWarning extends NodeWarning {

  final String value;

  const UnknownObfsWarning(this.value);

  @override
  List<Object?> get props => [value];

  @override
  String messageWith(GetLocalText t) => t.s(
      "Unknown obfuscation type \"%s\" was dropped (the core supports salamander and gecko only, and would otherwise break the whole config). The node connects without obfuscation.",
      value);

  @override
  WarningSeverity get severity => WarningSeverity.warning;
}




final class MissingObfsPasswordWarning extends NodeWarning {

  final String type;

  const MissingObfsPasswordWarning(this.type);

  @override
  List<Object?> get props => [type];

  @override
  String messageWith(GetLocalText t) => t.s(
      "Obfuscation \"%s\" has no password, so it was dropped (the core requires one and would otherwise break the whole config). The node connects without obfuscation.",
      type);

  @override
  WarningSeverity get severity => WarningSeverity.warning;
}











final class DetourCycleBrokenWarning extends NodeWarning {

  final String target;

  const DetourCycleBrokenWarning(this.target);

  @override
  List<Object?> get props => [target];

  @override
  String messageWith(GetLocalText t) => t.s(
      "Chain to \"%s\" would loop back on itself, so it was dropped. The node connects directly.",
      target);

  @override
  WarningSeverity get severity => WarningSeverity.warning;
}



final class DetourTargetMissingWarning extends NodeWarning {
  final String target;

  const DetourTargetMissingWarning(this.target);

  @override
  List<Object?> get props => [target];

  @override
  String messageWith(GetLocalText t) => t.s(
      "Chain target \"%s\" was not found in the config. The node connects directly.",
      target);

  @override
  WarningSeverity get severity => WarningSeverity.warning;
}



final class DetourToGroupWarning extends NodeWarning {
  final String target;

  const DetourToGroupWarning(this.target);

  @override
  List<Object?> get props => [target];

  @override
  String messageWith(GetLocalText t) => t.s(
      "Chain target \"%s\" is a group, which cannot be used as a chain hop. The node connects directly.",
      target);

  @override
  WarningSeverity get severity => WarningSeverity.warning;
}



final class DetourChainTooDeepWarning extends NodeWarning {
  final int limit;

  const DetourChainTooDeepWarning(this.limit);

  @override
  List<Object?> get props => [limit];

  @override
  String messageWith(GetLocalText t) => t.s(
      "Chain is longer than %d hops and was truncated.", limit);

  @override
  WarningSeverity get severity => WarningSeverity.warning;
}























final class DialerProxyUnusableWarning extends NodeWarning {
  final String label;
  final String target;



  @override
  final String ownerTag;

  const DialerProxyUnusableWarning(this.label, this.target,
      {this.ownerTag = ''});

  @override
  List<Object?> get props => [label, target, ownerTag];

  @override
  String messageWith(GetLocalText t) => t.s(
      "Node \"%1\$s\" was dropped: its relay \"%2\$s\" is missing, unusable or loops. Connecting directly would have bypassed the relay.",
      label,
      target);

  @override
  WarningSeverity get severity => WarningSeverity.error;
}



final class GroupMemberMissingWarning extends NodeWarning {

  final int count;

  const GroupMemberMissingWarning(this.count);

  @override
  List<Object?> get props => [count];

  @override
  String messageWith(GetLocalText t) =>
      t.plural("%d group members could not be imported and were left out.", count);

  @override
  WarningSeverity get severity => WarningSeverity.warning;
}










































final class DuplicateNodeWarning extends NodeWarning {

  final String winner;

  const DuplicateNodeWarning({this.winner = ''});

  @override
  List<Object?> get props => [winner];

  @override
  String messageWith(GetLocalText t) => winner.isEmpty
      ? t.s("Duplicate entry: the same node is already in this subscription.")
      : t.s("Duplicate of %s", winner);

  @override
  WarningSeverity get severity => WarningSeverity.info;
}








final class UnknownNodeTypeWarning extends NodeWarning {

  final String type;

  const UnknownNodeTypeWarning(this.type);

  @override
  List<Object?> get props => [type];

  @override
  String messageWith(GetLocalText t) => t.s("Unknown node type");


  String detailWith(GetLocalText t) => t.s(
      "The app does not know this node type and does not check it. The node goes to the core as written.");

  @override
  WarningSeverity get severity => WarningSeverity.info;
}






















final class Awg3HeaderKeyInvalidWarning extends NodeWarning {
  const Awg3HeaderKeyInvalidWarning();

  @override
  String messageWith(GetLocalText t) => t.s(
      "AmneziaWG 3 header protection key is not a 32-byte base64 key, so the node was skipped: the handshake cannot succeed and the core would reject the whole config.");

  @override
  WarningSeverity get severity => WarningSeverity.error;
}





final class Awg3PaddingTooShortWarning extends NodeWarning {

  final String field;


  final int min;

  const Awg3PaddingTooShortWarning(this.field, this.min);

  @override
  List<Object?> get props => [field, min];

  @override
  String messageWith(GetLocalText t) => t.s(
      "AmneziaWG 3 padding \"%1\$s\" is below %2\$d, the minimum required by the header protection key, so the node was skipped: the core would reject the whole config.",
      field,
      min);

  @override
  WarningSeverity get severity => WarningSeverity.error;
}







final class Awg3RandomTrailersWideHeadersWarning extends NodeWarning {
  const Awg3RandomTrailersWideHeadersWarning();

  @override
  String messageWith(GetLocalText t) => t.s(
      "AmneziaWG 3 random trailers are combined with a wide magic-header range (65536 or more); the server may mistake some upload packets for handshakes and drop them.");

  @override
  WarningSeverity get severity => WarningSeverity.info;
}


















final class PacketEncodingUnknownWarning extends NodeWarning {
  final String value;

  const PacketEncodingUnknownWarning(this.value);

  @override
  List<Object?> get props => [value];

  @override
  String messageWith(GetLocalText t) => t.s(
      "Packet encoding \"%s\" is not one the core knows (xudp, packetaddr), so it was dropped — keeping it would crash the core.",
      value);

  @override
  WarningSeverity get severity => WarningSeverity.warning;
}













final class RegistryWarning extends NodeWarning {
  const RegistryWarning({
    required this.code,
    this.path,
    this.value,
    this.params = const {},
    this.ownerTag = '',
    this.applied = true,
  });


  final String code;



  final String? path;


  final String? value;


  final Map<String, String> params;










  @override
  final String ownerTag;



  @override
  final bool applied;


  RegistryWarning notApplied() => applied
      ? RegistryWarning(
          code: code,
          path: path,
          value: value,
          params: params,
          ownerTag: ownerTag,
          applied: false,
        )
      : this;


  RegistryWarning withSecretValueMasked() {
    final masked = maskRegistrySecretValue(path, value);
    if (masked == value) return this;
    return RegistryWarning(
      code: code,
      path: path,
      value: masked,
      params: params,
      ownerTag: ownerTag,
      applied: applied,
    );
  }

  @override
  List<Object?> get props => [
        code,
        path,
        value,
        ...params.entries.map((e) => '${e.key}=${e.value}'),
        if (!applied) 'applied=false',
      ];





  @override
  String messageWith(GetLocalText t) =>
      registryTitle(code, _langFor(t), path: path, value: value, params: params);


  String detailWith(GetLocalText t) =>
      registryText(code, _langFor(t), path: path, value: value, params: params);




  RegistryLang _langFor(GetLocalText t) => identical(t, GetLocalText.en)
      ? RegistryLang.en
      : registryLangForTag(LocaleController.I.effectiveTag);

  @override
  WarningSeverity get severity => registrySeverity(code);
}
