import 'singbox_entry.dart';







class NodeEntries {
  final SingboxEntry main;
  final List<SingboxEntry> detours;

  const NodeEntries({required this.main, this.detours = const []});



  Iterable<SingboxEntry> get all sync* {
    yield main;
    yield* detours;
  }
}
