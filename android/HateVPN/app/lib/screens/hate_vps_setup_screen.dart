import 'dart:async';

import 'package:flutter/material.dart';

import '../services/hate_vps_provisioner.dart';
import '../widgets/hate_desktop_style.dart';

class HateVpsSetupResult {
  const HateVpsSetupResult(this.host, this.config);

  final String host;
  final String config;
}

class HateVpsSetupScreen extends StatefulWidget {
  const HateVpsSetupScreen({super.key});

  @override
  State<HateVpsSetupScreen> createState() => _HateVpsSetupScreenState();
}

class _HateVpsSetupScreenState extends State<HateVpsSetupScreen> {
  final _endpoint = TextEditingController();
  final _user = TextEditingController(text: 'root');
  final _secret = TextEditingController();
  bool _busy = false;
  bool _showSecret = false;
  bool _keyMode = false;
  String? _status;
  String? _error;

  @override
  void dispose() {
    _endpoint.dispose();
    _user.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<bool> _approveHost(String type, String fingerprint) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: HateColors.card,
            title: const Text(
              'Проверка сервера',
              style: TextStyle(color: HateColors.text),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Сверьте SSH-отпечаток с данными вашего VPS:',
                  style: TextStyle(color: HateColors.muted),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  '$type\n$fingerprint',
                  style: const TextStyle(color: HateColors.text, fontSize: 13),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Продолжить настройку и передать SSH-доступ?',
                  style: TextStyle(color: HateColors.muted),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Отмена'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Продолжить'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _continue() async {
    if (_busy) return;
    final endpoint = _endpoint.text.trim();
    final parts = endpoint.split(':');
    if (parts.length > 2 || parts.first.isEmpty) {
      setState(
        () =>
            _error = 'Введите IP-адрес или домен VPS и, если нужно, порт SSH.',
      );
      return;
    }
    final port = parts.length == 2 ? int.tryParse(parts[1]) : 22;
    if (port == null || port < 1 || port > 65535) {
      setState(() => _error = 'Порт SSH должен быть от 1 до 65535.');
      return;
    }
    final credentials = HateVpsCredentials(
      host: parts.first,
      port: port,
      user: _user.text.trim(),
      secret: _secret.text,
    );
    if (_keyMode && !credentials.usesPrivateKey) {
      setState(
        () => _error = 'Вставьте закрытый SSH-ключ целиком, включая BEGIN/END.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Подготовка подключения…';
    });
    try {
      final config = await const HateVpsProvisioner().install(
        credentials,
        approveHostKey: _approveHost,
        onProgress: (message) {
          if (mounted) {
            setState(() => _status = message);
          }
        },
      );
      _secret.clear();
      if (mounted) {
        Navigator.of(context).pop(HateVpsSetupResult(credentials.host, config));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is FormatException
              ? e.message
              : e is StateError
              ? e.message
              : 'Не удалось настроить VPS: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  Widget _accessChoice(String label, bool key) {
    final selected = _keyMode == key;
    return Material(
      color: selected ? const Color(0xFF2A3035) : HateColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? const Color(0xFFBBC5CC) : HateColors.cardBorder,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _busy
            ? null
            : () => setState(() {
                _keyMode = key;
                _secret.clear();
                _error = null;
              }),
        child: SizedBox(
          height: 40,
          child: Center(
            child: Text(
              '${selected ? '✓  ' : ''}$label',
              style: const TextStyle(color: HateColors.text, fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    String? hint,
    bool secret = false,
    TextInputType? keyboardType,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.fromLTRB(15, 12, 12, 8),
    decoration: BoxDecoration(
      color: HateColors.card,
      border: Border.all(color: HateColors.cardBorder),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: HateColors.muted, fontSize: 11),
        ),
        TextField(
          controller: controller,
          enabled: !_busy,
          keyboardType: keyboardType,
          obscureText: secret && !_keyMode && !_showSecret,
          maxLines: secret && _keyMode ? 5 : 1,
          style: const TextStyle(color: HateColors.text, fontSize: 15),
          cursorColor: HateColors.text,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF839099)),
            border: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.fromLTRB(0, 10, 0, 9),
            suffixIcon: secret && !_keyMode
                ? IconButton(
                    tooltip: _showSecret ? 'Скрыть' : 'Показать',
                    onPressed: () => setState(() => _showSecret = !_showSecret),
                    icon: Icon(
                      _showSecret ? Icons.visibility_off : Icons.visibility,
                      color: HateColors.muted,
                      size: 20,
                    ),
                  )
                : null,
          ),
          onSubmitted: secret ? (_) => unawaited(_continue()) : null,
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      backgroundColor: HateColors.sheet,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: HateBrandHeader(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: 'Назад',
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.arrow_back,
                        color: HateColors.text,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Настроить ваш сервер',
                    style: TextStyle(color: HateColors.text, fontSize: 27),
                  ),
                  const SizedBox(height: 22),
                  _field(
                    label: 'IP-адрес[:порт] сервера',
                    controller: _endpoint,
                    hint: '255.255.255.255:22',
                    keyboardType: TextInputType.url,
                  ),
                  _field(
                    label: 'Имя пользователя SSH',
                    controller: _user,
                    hint: 'root',
                  ),
                  Row(
                    children: [
                      Expanded(child: _accessChoice('Пароль SSH', false)),
                      const SizedBox(width: 9),
                      Expanded(child: _accessChoice('SSH-ключ', true)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _field(
                    label: _keyMode ? 'Закрытый ключ SSH' : 'Пароль SSH',
                    controller: _secret,
                    secret: true,
                  ),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: HateColors.card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: HateColors.muted,
                          size: 18,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Для SSH-ключа поддерживаются ED25519 и RSA в формате PEM / OpenSSH. Вставьте ключ целиком, включая BEGIN/END.',
                            style: TextStyle(
                              color: HateColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_status != null) ...[
                    const Center(
                      child: CircularProgressIndicator(color: HateColors.text),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _status!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: HateColors.muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFE9B6B6),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  HatePrimaryButton(
                    label: _busy ? 'Настраиваем…' : 'Продолжить',
                    onPressed: _busy ? null : () => unawaited(_continue()),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Данные SSH используются только во время настройки и не сохраняются.',
                    style: TextStyle(color: HateColors.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
