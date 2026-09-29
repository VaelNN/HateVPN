part of '../settings_storage.dart';

































Future<List<SourceChain>> _getChains() async => _chainsOf(
      await _load(),
      onCorrupt: (e) => AppLog.I.warning('Skipping unreadable chain record: $e'),
      onNote: _logStorageNoteOnce,
    );





List<SourceChain> _chainsOf(
  Map<String, dynamic> doc, {
  void Function(Object error)? onCorrupt,
  void Function(String note)? onNote,
}) =>
    [
      for (final e
          in _sourceEntriesOf(doc, onCorrupt: onCorrupt, onNote: onNote))
        if (e is ChainEntry) e.chain,
    ];







Future<void> _setChains(List<SourceChain> chains, {bool flush = true}) async =>
    _saveSourceEntries(
      _replaceKind<ChainEntry>(
        await _getSourceEntries(),
        [for (final c in chains) ChainEntry(c)],
      ),
      flush: flush,
    );















Future<SourceChain> _addChain({String? label, String? tag}) async {
  final chains = (await _getChains()).toList();
  final wanted = await _requireFreeChainTag(tag, chains);
  final chain = SourceChain(tag: wanted, label: label ?? wanted, enabled: true);
  chains.add(chain);
  await _setChains(chains);
  return chain;
}







Future<String> _requireFreeChainTag(String? tag, List<SourceChain> chains) async {
  final directions = await _getDirections();
  final used = [
    ...chains.map((c) => c.tag),
    ...directions.map((d) => d.tag),
  ];
  final wanted = (tag ?? nextChainTag(used)).trim();
  final conflict = directionTagConflict(wanted, used);
  if (conflict != null) {
    throw StateError('chain tag "$wanted" rejected: $conflict');
  }
  return wanted;
}










Future<SourceChain> _createChain(SourceChain chain) async {
  final chains = (await _getChains()).toList();



  final wanted = await _requireFreeChainTag(chain.tag, chains);
  final created = SourceChain(
    tag: wanted,
    label: chain.label,
    enabled: chain.enabled,
    hops: chain.hops,
    idleTimeout: chain.idleTimeout,
    stripEvasion: chain.stripEvasion,
    strip: chain.strip,
    rewrite: chain.rewrite,
  );
  chains.add(created);
  await _setChains(chains);
  return created;
}





Future<void> _updateChain(SourceChain chain) async {
  final chains = (await _getChains()).toList();
  final i = chains.indexWhere((c) => c.tag == chain.tag);
  if (i < 0) throw StateError('chain not found: ${chain.tag}');
  chains[i] = chain;
  await _setChains(chains);
}



Future<void> _reorderChains(List<SourceChain> chains) => _setChains(chains);






















Future<ChainHealResult> _deleteChain(String tag) async {
  final chains = (await _getChains()).toList()..removeWhere((c) => c.tag == tag);
  final healed = clearChainHopRefs(chains, tag);
  await _setChains(healed.chains);
  return healed;
}










Future<ChainHealResult> _healChainHops(String tag, {bool flush = true}) async {
  final chains = await _getChains();
  final healed = clearChainHopRefs(chains, tag);
  if (healed.positions == 0) return healed;
  await _setChains(healed.chains, flush: flush);
  return healed;
}
