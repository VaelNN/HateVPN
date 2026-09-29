











import 'package:flutter/material.dart';

import '../../controllers/subscription_controller.dart';
import '../../models/direction.dart';
import '../../models/direction_tag_prefix.dart';
import '../../services/direction_mutations.dart';
import '../../services/l10n/locale_controller.dart';


class TagPrefixCascadeOutcome {
  const TagPrefixCascadeOutcome({
    required this.healed,
    required this.ambiguous,
  });

  static const none = TagPrefixCascadeOutcome(healed: [], ambiguous: []);


  final List<Direction> healed;



  final List<Direction> ambiguous;

  bool get isEmpty => healed.isEmpty && ambiguous.isEmpty;
}









Future<TagPrefixCascadeOutcome> applyTagPrefixCascade({
  required List<Direction> directions,
  required String oldPrefix,
  required String newPrefix,
  SubscriptionController? sub,
}) async {
  final cascade = analyzeTagPrefixChange(
    directions: directions,
    oldPrefix: oldPrefix,
    newPrefix: newPrefix,
  );
  if (cascade.isEmpty) return TagPrefixCascadeOutcome.none;

  final healed = <Direction>[];
  final ambiguous = <Direction>[];
  for (final impact in cascade.impacts) {
    final next = impact.healed;
    if (next != null) {
      await DirectionMutations.update(next, sub);
      healed.add(next);
    }


    if (impact.ambiguous) ambiguous.add(impact.direction);
  }
  return TagPrefixCascadeOutcome(healed: healed, ambiguous: ambiguous);
}




String? tagPrefixCascadeMessage(TagPrefixCascadeOutcome outcome) {
  if (outcome.isEmpty) return null;
  String names(List<Direction> ds) => ds.map((d) => d.displayLabel).join(', ');
  final parts = <String>[
    if (outcome.healed.isNotEmpty)
      getLocalText.s('Direction filters updated to the new prefix: %s',
          names(outcome.healed)),
    if (outcome.ambiguous.isNotEmpty)
      getLocalText.s(
          'Check the filter of: %s — the old prefix is part of a regex '
          'construct there and was left as is.',
          names(outcome.ambiguous)),
  ];
  return parts.join(' ');
}



void showTagPrefixCascadeSnackBar(
    BuildContext context, TagPrefixCascadeOutcome outcome) {
  final msg = tagPrefixCascadeMessage(outcome);
  if (msg == null) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), duration: const Duration(seconds: 6)),
  );
}
