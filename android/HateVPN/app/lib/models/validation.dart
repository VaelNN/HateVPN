


library;

import '../services/l10n/get_local_text.dart';
import '../services/l10n/locale_controller.dart';

enum Severity { fatal, warn }

sealed class ValidationIssue {
  const ValidationIssue();
  Severity get severity;





  String messageWith(GetLocalText t);


  String message() => messageWith(getLocalText);


  String renderEn() => messageWith(GetLocalText.en);



  List<Object?> get props => const [];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ValidationIssue &&
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

final class DanglingOutboundRef extends ValidationIssue {
  final String rule;
  final String tag;
  const DanglingOutboundRef(this.rule, this.tag);

  @override
  Severity get severity => Severity.fatal;

  @override
  List<Object?> get props => [rule, tag];

  @override
  String messageWith(GetLocalText t) =>
      t.s("Rule \"%1\$s\" references missing outbound \"%2\$s\".", rule, tag);
}





final class DanglingDetourRef extends ValidationIssue {
  final String owner;
  final String tag;
  const DanglingDetourRef(this.owner, this.tag);

  @override
  Severity get severity => Severity.fatal;

  @override
  List<Object?> get props => [owner, tag];

  @override
  String messageWith(GetLocalText t) => t.s(
    "Outbound \"%1\$s\" detour references missing outbound \"%2\$s\".",
    owner,
    tag,
  );
}





final class DanglingDnsServerRef extends ValidationIssue {
  final String field;
  final String tag;
  const DanglingDnsServerRef(this.field, this.tag);

  @override
  Severity get severity => Severity.fatal;

  @override
  List<Object?> get props => [field, tag];

  @override
  String messageWith(GetLocalText t) =>
      t.s("%1\$s references missing DNS server \"%2\$s\".", field, tag);
}







final class BadResolverServerType extends ValidationIssue {
  final String field;
  final String tag;
  final String serverType;
  const BadResolverServerType(this.field, this.tag, this.serverType);

  @override
  Severity get severity => Severity.fatal;

  @override
  List<Object?> get props => [field, tag, serverType];

  @override
  String messageWith(GetLocalText t) => t.s(
    "%1\$s cannot use \"%2\$s\": a \"%3\$s\" server is not allowed as a resolver.",
    field,
    tag,
    serverType,
  );
}






final class EmptyDnsGroup extends ValidationIssue {
  final String tag;
  const EmptyDnsGroup(this.tag);

  @override
  Severity get severity => Severity.fatal;

  @override
  List<Object?> get props => [tag];

  @override
  String messageWith(GetLocalText t) => t.s(
    "DNS group \"%s\" has no usable members — enable or add at least one server.",
    tag,
  );
}




final class BadDnsGroupMember extends ValidationIssue {
  final String group;
  final String member;
  final String memberType;
  const BadDnsGroupMember(this.group, this.member, this.memberType);

  @override
  Severity get severity => Severity.fatal;

  @override
  List<Object?> get props => [group, member, memberType];

  @override
  String messageWith(GetLocalText t) => t.s(
    "DNS group \"%1\$s\": member \"%2\$s\" of type \"%3\$s\" is not allowed in a group.",
    group,
    member,
    memberType,
  );
}




final class DnsGroupCycle extends ValidationIssue {


  final List<String> cycle;
  const DnsGroupCycle(this.cycle);

  @override
  Severity get severity => Severity.fatal;

  @override
  List<Object?> get props => [cycle.join('\u0000')];

  @override
  String messageWith(GetLocalText t) => t.s(
    "DNS group loop: %s — fix group membership to start the VPN.",
    '${cycle.join(" → ")} → ${cycle.first}',
  );
}











final class DetourCycle extends ValidationIssue {


  final List<String> cycle;




  final List<({String tag, String detour})> culprits;

  const DetourCycle(this.cycle, {this.culprits = const []});

  @override
  Severity get severity => Severity.fatal;

  @override
  List<Object?> get props => [

    cycle.join('\u0000'),
    culprits.map((c) => '${c.tag}\u0000${c.detour}').join('\u0001'),
  ];

  @override
  String messageWith(GetLocalText t) {
    if (culprits.isEmpty) {
      return t.s(
        "Routing loop between groups: %s — fix group membership to start the VPN.",
        '${cycle.join(" → ")} → ${cycle.first}',
      );
    }
    if (culprits.length == 1) {
      final c = culprits.single;
      return t.s(
        "Routing loop: \"%1\$s\" points back into \"%2\$s\" — change or remove its detour to start the VPN.",
        c.tag,
        c.detour,
      );
    }
    final tags = culprits.map((c) => '"${c.tag}"').join(', ');
    return t.plural(
      "Routing loop: %1\$d nodes point back into their own chain — change or remove their detours to start the VPN: %2\$s.",
      culprits.length,
      tags,
    );
  }
}

final class EmptyUrltestGroup extends ValidationIssue {
  final String tag;
  const EmptyUrltestGroup(this.tag);

  @override
  Severity get severity => Severity.fatal;

  @override
  List<Object?> get props => [tag];

  @override
  String messageWith(GetLocalText t) =>
      t.s("URL-test group \"%s\" has no outbounds.", tag);
}

final class InvalidDefault extends ValidationIssue {
  final String group;
  final String tag;
  const InvalidDefault(this.group, this.tag);

  @override
  Severity get severity => Severity.fatal;

  @override
  List<Object?> get props => [group, tag];

  @override
  String messageWith(GetLocalText t) => t.s(
    "Selector \"%1\$s\" default \"%2\$s\" is not in the options list.",
    group,
    tag,
  );
}

class ValidationResult {
  final List<ValidationIssue> issues;
  const ValidationResult(this.issues);

  bool get hasFatal => issues.any((i) => i.severity == Severity.fatal);
  bool get isOk => !hasFatal;

  List<ValidationIssue> get fatal =>
      issues.where((i) => i.severity == Severity.fatal).toList();
  List<ValidationIssue> get warnings =>
      issues.where((i) => i.severity == Severity.warn).toList();

  static const ok = ValidationResult([]);
}














class FatalValidationException implements Exception {
  final List<ValidationIssue> issues;
  const FatalValidationException(this.issues);

  @override
  String toString() =>
      'FatalValidationException(${issues.length}: '
      '${issues.map((i) => i.runtimeType).join(', ')})';
}
