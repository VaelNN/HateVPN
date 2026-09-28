import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/settings_storage.dart';
import '../widgets/hate_desktop_style.dart';

class HateSettingsScreen extends StatefulWidget {
  const HateSettingsScreen({super.key});

  @override
  State<HateSettingsScreen> createState() => _HateSettingsScreenState();
}

class _HateSettingsScreenState extends State<HateSettingsScreen> {
  bool _autoUpdate = true;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final update = await SettingsStorage.getAutoUpdateSubs();
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _autoUpdate = update;
        _version = info.version;
      });
    }
  }

  Future<void> _setAutoUpdate(bool value) async {
    setState(() => _autoUpdate = value);
    await SettingsStorage.setAutoUpdateSubs(value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: HateColors.sheet,
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const HateBrandHeader(),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Настройки',
                    style: TextStyle(
                      color: HateColors.text,
                      fontSize: 29,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Закрыть',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: HateColors.muted),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Сделайте HateVPN удобным для себя.',
              style: TextStyle(color: HateColors.muted),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: HateColors.card,
                border: Border.all(color: HateColors.cardBorder),
                borderRadius: BorderRadius.circular(16),
              ),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Автообновление подписок'),
                subtitle: const Text('Обновлять список серверов в фоне'),
                value: _autoUpdate,
                onChanged: (value) => _setAutoUpdate(value),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'HateVPN $_version',
              style: const TextStyle(color: Color(0xFF8F9AA3), fontSize: 11),
            ),
          ],
        ),
      ),
    ),
  );
}
