import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/home_controller.dart';
import '../controllers/subscription_controller.dart';
import '../models/node_spec.dart';
import '../models/server_list.dart';
import '../services/subscription/auto_updater.dart';
import '../services/tag_resolver.dart';
import '../widgets/hate_desktop_style.dart';
import 'chain_edit/chain_edit_flow.dart';
import 'home/source_lookup.dart';
import 'hate_vps_setup_screen.dart';

class HateConnectionsScreen extends StatefulWidget {
  const HateConnectionsScreen({
    super.key,
    required this.subController,
    required this.homeController,
    required this.autoUpdater,
    required this.selectedTag,
    required this.onSelected,
    required this.onSelectedDeleted,
  });

  final SubscriptionController subController;
  final HomeController homeController;
  final AutoUpdater autoUpdater;
  final String? selectedTag;
  final void Function(String tag, String name, String source) onSelected;
  final VoidCallback onSelectedDeleted;

  @override
  State<HateConnectionsScreen> createState() => _HateConnectionsScreenState();
}

class _HateConnectionsScreenState extends State<HateConnectionsScreen> {
  final _link = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _addLink() async {
    final value = _link.text.trim();
    if (value.isEmpty) {
      setState(() => _message = 'Вставьте ссылку подписки или приглашения.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final before = widget.subController.entries.map((e) => e.id).toSet();
    try {
      await widget.subController.addFromInput(value);
      if (!mounted) return;
      final error = widget.subController.lastError;
      if (error != null) {
        setState(() => _message = error.render());
        return;
      }
      final applied = await regenerateSourcesConfig(
        widget.subController,
        widget.homeController,
      );
      if (!mounted) return;
      if (applied == null) {
        setState(() => _message = 'Не удалось сохранить подключение.');
        return;
      }
      _link.clear();
      final added = widget.subController.entries
          .where((e) => !before.contains(e.id) && e.list.nodes.isNotEmpty)
          .firstOrNull;
      if (added != null) {
        _choose(added, added.list.nodes.first);
      } else {
        setState(() => _message = 'Подключение добавлено. Выберите сервер.');
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Не удалось добавить: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final value = data?.text?.trim() ?? '';
    setState(() {
      _link.text = value;
      _message = value.isEmpty ? 'В буфере нет ссылки.' : null;
    });
  }

  Future<void> _setupVps() async {
    final result = await Navigator.of(context).push<HateVpsSetupResult>(
      MaterialPageRoute(builder: (_) => const HateVpsSetupScreen()),
    );
    if (result == null || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final before = widget.subController.entries.map((e) => e.id).toSet();
    try {
      await widget.subController.addFromInput(
        result.config,
        nameHint: 'Мой сервер · ${result.host}',
      );
      if (!mounted) return;
      final error = widget.subController.lastError;
      if (error != null) {
        setState(() => _message = error.render());
        return;
      }
      final applied = await regenerateSourcesConfig(
        widget.subController,
        widget.homeController,
      );
      if (!mounted) return;
      if (applied == null) {
        setState(() => _message = 'Не удалось сохранить подключение.');
        return;
      }
      final added = widget.subController.entries
          .where((e) => !before.contains(e.id) && e.list.nodes.isNotEmpty)
          .firstOrNull;
      if (added != null) {
        _choose(added, added.list.nodes.first);
      } else {
        setState(() => _message = 'Сервер добавлен. Выберите подключение.');
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Не удалось добавить сервер: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _emittedTag(SubscriptionEntry entry, NodeSpec node) {
    final entries = widget.subController.entries;
    for (final configNode in widget.homeController.state.configModel.nodes) {
      if (configNode.isControl) continue;
      final owner = ownerOfTag(configNode.tag, entries);
      if (owner == null || entries[owner.entryIndex].id != entry.id) continue;
      final bare = TagResolver.stripPrefix(
        configNode.tag,
        entry.list.tagPrefix,
      );
      final original = bare.replaceFirst(RegExp(r'-\d+$'), '');
      if (bare == node.tag || original == node.tag) {
        return configNode.tag;
      }
    }
    return null;
  }

  void _choose(SubscriptionEntry entry, NodeSpec node) {
    final tag = _emittedTag(entry, node);
    if (tag == null) {
      setState(
        () => _message = 'Сервер не найден в конфигурации. Обновите подписку.',
      );
      return;
    }
    final name = node.label.isEmpty ? node.tag : node.label;
    widget.onSelected(tag, name, entry.displayName);
    Navigator.of(context).pop();
  }

  Future<void> _openEntry(SubscriptionEntry entry) async {
    final nodes = entry.list.nodes;
    if (nodes.isEmpty) {
      setState(
        () => _message = 'У подключения нет серверов. Обновите подписку.',
      );
      return;
    }
    if (nodes.length == 1) {
      _choose(entry, nodes.first);
      return;
    }
    final picked = await Navigator.of(context).push<NodeSpec>(
      MaterialPageRoute(
        builder: (_) => _HateSubscriptionServersScreen(
          title: entry.displayName,
          nodes: nodes,
          selectedTag: widget.selectedTag,
          emittedTagFor: (node) => _emittedTag(entry, node),
        ),
      ),
    );
    if (picked != null && mounted) _choose(entry, picked);
  }

  Future<void> _deleteSelected() async {
    final tag = widget.selectedTag;
    if (tag == null) return;
    final owner = ownerOfTag(tag, widget.subController.entries);
    if (owner == null) return;
    final entry = widget.subController.entries[owner.entryIndex];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: HateColors.card,
        title: const Text('Удалить подключение?'),
        content: Text(entry.displayName),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    await widget.subController.removeAt(owner.entryIndex);
    await regenerateSourcesConfig(widget.subController, widget.homeController);
    widget.onSelectedDeleted();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      widget.autoUpdater.resetAllFailCounts();
      await widget.autoUpdater.maybeUpdateAll(
        UpdateTrigger.manual,
        force: true,
      );
      await regenerateSourcesConfig(
        widget.subController,
        widget.homeController,
      );
      if (mounted) setState(() => _message = 'Список серверов обновлён.');
    } catch (e) {
      if (mounted) setState(() => _message = 'Не удалось обновить: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.subController,
    builder: (context, _) {
      final entries = widget.subController.entries;
      final selectedOwner = widget.selectedTag == null
          ? null
          : ownerOfTag(widget.selectedTag!, entries);
      return Scaffold(
        backgroundColor: HateColors.sheet,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: const HateBrandHeader(),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(28, 14, 28, 28),
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Подключения',
                            style: TextStyle(
                              color: HateColors.text,
                              fontSize: 29,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Назад',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.close,
                            color: HateColors.muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Выберите сервер или добавьте новую ссылку.',
                      style: TextStyle(color: HateColors.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0x20FFFFFF),
                        border: Border.all(color: const Color(0xFF637079)),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ДОБАВИТЬ ПО ССЫЛКЕ',
                            style: TextStyle(
                              color: Color(0xFFD6DEE3),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 9),
                          const Text(
                            'Одна ссылка — готовое подключение',
                            style: TextStyle(
                              color: HateColors.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            'Подписка или приглашение от друга. Тип ссылки определим сами.',
                            style: TextStyle(
                              color: HateColors.muted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _link,
                            style: const TextStyle(
                              color: HateColors.text,
                              fontSize: 13,
                            ),
                            cursorColor: HateColors.text,
                            decoration: InputDecoration(
                              hintText: 'Вставьте ссылку',
                              hintStyle: const TextStyle(
                                color: Color(0xFF89939B),
                              ),
                              filled: true,
                              fillColor: const Color(0xFF101316),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 13,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(11),
                                borderSide: const BorderSide(
                                  color: Color(0xFF4A535A),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(11),
                                borderSide: const BorderSide(
                                  color: Color(0xFFC4CDD3),
                                ),
                              ),
                            ),
                            onSubmitted: (_) => unawaited(_addLink()),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              SizedBox(
                                width: 102,
                                child: HateDarkButton(
                                  label: 'Вставить',
                                  onPressed: _busy
                                      ? null
                                      : () => unawaited(_paste()),
                                  height: 44,
                                ),
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: HatePrimaryButton(
                                  label: _busy ? 'Подождите…' : 'Добавить',
                                  onPressed: _busy
                                      ? null
                                      : () => unawaited(_addLink()),
                                  height: 44,
                                ),
                              ),
                            ],
                          ),
                          if (_message != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _message!,
                              style: const TextStyle(
                                color: Color(0xFFE9C7C7),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    HateConnectionCard(
                      title: 'Свой VPS',
                      subtitle: 'Настроить сервер прямо в приложении',
                      onTap: _busy ? () {} : () => unawaited(_setupVps()),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'МОИ ПОДКЛЮЧЕНИЯ',
                            style: TextStyle(
                              color: Color(0xFFADB7BF),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${entries.length}',
                          style: const TextStyle(
                            color: Color(0xFFA3ADB5),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 11),
                    if (entries.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 3, bottom: 18),
                        child: Text(
                          'Здесь появятся ваши подключения.',
                          style: TextStyle(
                            color: Color(0xFFA7B0B8),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    for (var i = 0; i < entries.length; i++) ...[
                      HateConnectionCard(
                        title: entries[i].displayName,
                        subtitle: entries[i].list is SubscriptionServers
                            ? '${entries[i].list.nodes.length} серверов'
                            : entries[i].list.nodes.isEmpty
                            ? 'Нет серверов'
                            : '${entries[i].list.nodes.first.server}:${entries[i].list.nodes.first.port}',
                        selected: selectedOwner?.entryIndex == i,
                        onTap: _busy
                            ? () {}
                            : () => unawaited(_openEntry(entries[i])),
                      ),
                      const SizedBox(height: 7),
                    ],
                    if (entries.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: HateDarkButton(
                              label: 'Обновить список',
                              onPressed: _busy
                                  ? null
                                  : () => unawaited(_refresh()),
                              height: 42,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 105,
                            child: HateDarkButton(
                              label: 'Удалить',
                              onPressed: selectedOwner == null || _busy
                                  ? null
                                  : () => unawaited(_deleteSelected()),
                              height: 42,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _HateSubscriptionServersScreen extends StatelessWidget {
  const _HateSubscriptionServersScreen({
    required this.title,
    required this.nodes,
    required this.selectedTag,
    required this.emittedTagFor,
  });

  final String title;
  final List<NodeSpec> nodes;
  final String? selectedTag;
  final String? Function(NodeSpec) emittedTagFor;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: HateColors.sheet,
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: const HateBrandHeader(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 14, 28, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.arrow_back,
                        color: HateColors.text,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Серверы подписки',
                        style: TextStyle(
                          color: HateColors.text,
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFCFD7DD),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${nodes.length} серверов',
                  style: const TextStyle(
                    color: Color(0xFF9FAAB2),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              itemCount: nodes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 7),
              itemBuilder: (context, index) {
                final node = nodes[index];
                return HateConnectionCard(
                  title: node.label.isEmpty ? node.tag : node.label,
                  subtitle: '${node.server}:${node.port}',
                  selected: selectedTag == emittedTagFor(node),
                  onTap: () => Navigator.of(context).pop(node),
                );
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(28, 12, 28, 18),
            child: Text(
              'Выберите сервер и подключитесь на главном экране.',
              style: TextStyle(color: HateColors.muted, fontSize: 11),
            ),
          ),
        ],
      ),
    ),
  );
}
