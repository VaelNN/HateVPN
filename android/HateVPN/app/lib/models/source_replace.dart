







library;

import 'package:collection/collection.dart';

import 'direction.dart';


enum ReplaceMode {

  manual,


  auto,


  both;



  static ReplaceMode fromWire(Object? raw) =>
      ReplaceMode.values.firstWhereOrNull((m) => m.name == raw) ??
      ReplaceMode.manual;
}

class SourceReplace {
  const SourceReplace({
    required this.mode,
    required this.tag,
    this.auto,
  });

  final ReplaceMode mode;


  final String tag;



  final DirectionAuto? auto;


  bool get hasAuto => mode != ReplaceMode.manual;


  bool get hasSelector => mode != ReplaceMode.auto;


  DirectionAuto get autoOrDefault => auto ?? const DirectionAuto();



  String get autoTag =>
      mode == ReplaceMode.both ? '${tag.trim()}$kDirectionAutoSuffix' : tag.trim();



  List<String> get names {
    final t = tag.trim();
    if (t.isEmpty) return const [];
    return [t, if (mode == ReplaceMode.both) '$t$kDirectionAutoSuffix'];
  }

  SourceReplace copyWith({
    ReplaceMode? mode,
    String? tag,
    DirectionAuto? auto,
  }) =>
      SourceReplace(
        mode: mode ?? this.mode,
        tag: tag ?? this.tag,
        auto: auto ?? this.auto,
      );

  static const _eq = DeepCollectionEquality();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SourceReplace &&
          mode == other.mode &&
          tag == other.tag &&
          _eq.equals(auto?.toJson(), other.auto?.toJson()));

  @override
  int get hashCode => Object.hash(mode, tag, _eq.hash(auto?.toJson()));
}
