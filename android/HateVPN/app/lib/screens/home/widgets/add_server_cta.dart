import 'package:flutter/material.dart';

import '../../../controllers/home_controller.dart';
import '../../../controllers/subscription_controller.dart';
import '../../../services/subscription/auto_updater.dart';
import '../../subscriptions_screen.dart';

/// Гайд пустого состояния главного экрана (нет конфига/нод): заголовок, FAB
/// «Add a server» → [SubscriptionsScreen] и ссылка restore-from-backup
/// ([onRestoreFromBackup] живёт в `_HomeScreenState` — это async flow с
/// file-picker'ом и ScaffoldMessenger).
class AddServerCta extends StatelessWidget {
  const AddServerCta({
    super.key,
    required this.controller,
    required this.subController,
    required this.autoUpdater,
    required this.onRestoreFromBackup,
  });

  final HomeController controller;
  final SubscriptionController subController;
  final AutoUpdater autoUpdater;
  final VoidCallback onRestoreFromBackup;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    void openConnections() => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SubscriptionsScreen(
              subController: subController,
              homeController: controller,
              autoUpdater: autoUpdater,
            ),
          ),
        );
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 56),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/icons/hatevpn.png', width: 82, height: 82),
            const SizedBox(height: 28),
            Text(
              'HateVPN',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              'Подключитесь по ссылке подписки или приглашению от друга.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: openConnections,
                icon: const Icon(Icons.add_link),
                label: const Text('Добавить подключение'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
