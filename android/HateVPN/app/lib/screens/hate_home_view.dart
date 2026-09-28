import 'package:flutter/material.dart';

import '../models/home_state.dart';
import '../widgets/hate_desktop_style.dart';

class HateHomeView extends StatelessWidget {
  const HateHomeView({
    super.key,
    required this.state,
    required this.profileName,
    required this.profileCaption,
    required this.error,
    required this.onConnections,
    required this.onToggle,
    required this.onSettings,
  });

  final HomeState state;
  final String? profileName;
  final String? profileCaption;
  final String? error;
  final VoidCallback onConnections;
  final VoidCallback onToggle;
  final VoidCallback onSettings;

  static const _gray = <double>[
    .2126,
    .7152,
    .0722,
    0,
    0,
    .2126,
    .7152,
    .0722,
    0,
    0,
    .2126,
    .7152,
    .0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  @override
  Widget build(BuildContext context) {
    final connected = state.tunnelUp;
    final connecting = state.tunnel == TunnelStatus.connecting;
    final stopping = state.tunnel == TunnelStatus.stopping;
    final busy = state.busy || connecting || stopping;
    final title = connected
        ? 'Подключено'
        : connecting
        ? 'Подключаемся…'
        : stopping
        ? 'Отключаемся…'
        : 'Не подключено';
    final subtitle = connected
        ? 'Соединение с выбранным сервером установлено.'
        : profileName == null
        ? 'Добавьте подписку или настройте свой VPS.'
        : 'Нажмите «Подключиться», чтобы включить VPN.';

    return Scaffold(
      backgroundColor: HateColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ColorFiltered(
            colorFilter: const ColorFilter.matrix(_gray),
            child: Opacity(
              opacity: .58,
              child: Image.asset(
                'assets/images/obsidian-ribbon.png',
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, .42, .79, 1],
                colors: [
                  Color(0xD7080A0C),
                  Color(0x4D080A0C),
                  Color(0xF2080A0C),
                  Color(0xFF080A0C),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HateBrandHeader(onSettings: onSettings),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: connected
                              ? const Color(0xFFB4D6C5)
                              : const Color(0xFFB3BDC5),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'ВАШ ЛИЧНЫЙ VPN',
                        style: TextStyle(
                          color: Color(0xFFB3BDC5),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    style: const TextStyle(
                      color: HateColors.text,
                      fontSize: 34,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: HateColors.muted,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  if (error != null && error!.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: const Color(0xF5292F34),
                        border: Border.all(color: const Color(0xFF87939C)),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text(
                        error!,
                        style: const TextStyle(
                          color: Color(0xFFEBEFF2),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  HateConnectionCard(
                    title: profileName ?? 'Добавить подключение',
                    subtitle: profileCaption ?? 'Подписка или свой VPS',
                    onTap: onConnections,
                    leading: Container(
                      width: 35,
                      height: 35,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A3035),
                        border: Border.all(color: const Color(0xFF485159)),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.public,
                        size: 19,
                        color: Color(0xFFD4DBE0),
                      ),
                    ),
                  ),
                  const SizedBox(height: 13),
                  HatePrimaryButton(
                    height: 58,
                    label: connected ? 'Отключить' : 'Подключиться',
                    icon: Icons.power_settings_new,
                    onPressed: busy ? null : onToggle,
                  ),
                  if (busy) ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(
                      minHeight: 2,
                      color: Color(0xFFC4CDD3),
                      backgroundColor: Color(0xFF363D43),
                    ),
                  ],
                  const SizedBox(height: 32),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 12,
                        color: Color(0xFFAAB4BC),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'HateVPN · by DarkSide',
                        style: TextStyle(
                          color: Color(0xFFAFB8C0),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 17),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
