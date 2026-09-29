
















import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/home_controller.dart';
import '../controllers/subscription_controller.dart';
import '../models/parser_config.dart' show WizardTemplate, WizardVar;
import '../services/settings_storage.dart'
    show SettingsStorage, VpnModeConfig, NativePrefsKeys;
import '../services/subscription/subscription_identity.dart'
    show generateProxyPassword;
import 'lazy_persist_mixin.dart';
import '../services/l10n/locale_controller.dart';

class VpnModeTab extends StatefulWidget {
  const VpnModeTab({
    super.key,
    required this.homeController,
    required this.subController,
    required this.template,
  });

  final HomeController homeController;
  final SubscriptionController subController;



  final WizardTemplate template;

  @override
  State<VpnModeTab> createState() => _VpnModeTabState();
}

class _VpnModeTabState extends State<VpnModeTab>
    with WidgetsBindingObserver, LazyPersistMixin<VpnModeTab> {
  VpnModeConfig _cfg = const VpnModeConfig.defaults();
  bool _loading = true;
  bool _showPassword = false;




  bool _keepOnExit = true;
  bool _allowBypass = false;
  bool _tunTogglesLoaded = false;

  late final TextEditingController _portCtl;
  late final TextEditingController _userCtl;
  late final TextEditingController _passCtl;
  late final TextEditingController _listenCtl;
  String _portError = '';
  String _listenError = '';




  late final WizardVar _vpnModeNode = _node('vpn_mode');
  late final WizardVar _proxyTypeNode = _node('proxy_type');
  late final WizardVar _listenNode = _node('proxy_listen');
  late final WizardVar _portNode = _node('proxy_port');
  late final WizardVar _userNode = _node('proxy_user');
  late final WizardVar _passNode = _node('proxy_pass');
  late final WizardVar _authNode = _node('proxy_auth');



  WizardVar _node(String name) =>
      widget.template.vars.firstWhere((v) => v.name == name);

  @override
  SubscriptionController get lazyController => widget.subController;

  @override
  void initState() {
    super.initState();
    _portCtl = TextEditingController();
    _userCtl = TextEditingController();
    _passCtl = TextEditingController();
    _listenCtl = TextEditingController();
    unawaited(_load());
  }

  @override
  void dispose() {
    _portCtl.dispose();
    _userCtl.dispose();
    _passCtl.dispose();
    _listenCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cfg = await SettingsStorage.getVpnMode();


    final keep =
        await SettingsStorage.getNativeBool(NativePrefsKeys.keepOnExit);
    final bypass =
        await SettingsStorage.getNativeBool(NativePrefsKeys.allowBypass);
    if (!mounted) return;
    setState(() {
      _cfg = cfg;
      _portCtl.text = cfg.proxyPort.toString();
      _userCtl.text = cfg.proxyUsername;
      _passCtl.text = cfg.proxyPassword;
      _listenCtl.text = cfg.proxyListen;
      _keepOnExit = keep;
      _allowBypass = bypass;
      _tunTogglesLoaded = true;
      _loading = false;
    });
  }



  void _toggleKeepOnExit(bool val) {
    setState(() => _keepOnExit = val);
    unawaited(
        SettingsStorage.setNativeBool(NativePrefsKeys.keepOnExit, val));
    widget.homeController.markConfigChangedNeedRestart();
  }


  void _toggleAllowBypass(bool val) {
    setState(() => _allowBypass = val);
    unawaited(
        SettingsStorage.setNativeBool(NativePrefsKeys.allowBypass, val));
    widget.homeController.markConfigChangedNeedRestart();
  }

  @override
  Future<void> stageChanges() async {
    await SettingsStorage.setVpnMode(_cfg, flush: false);
  }



  void _commit() {
    markDirty();
    widget.homeController.markConfigChangedNeedRestart();
  }

  void _setMode(String mode) {
    var next = _cfg.copyWith(mode: mode);


    if (next.hasMixed && next.effectiveAuth && next.proxyPassword.isEmpty) {
      final pass = generateProxyPassword();
      next = next.copyWith(proxyPassword: pass);
      _passCtl.text = pass;
    }
    setState(() => _cfg = next);


    unawaited(SettingsStorage.setNativeHasTun(next.hasTun));
    _commit();
  }

  void _setProtocol(String proto) {
    if (proto == _cfg.proxyProtocol) return;
    setState(() => _cfg = _cfg.copyWith(proxyProtocol: proto));
    _commit();
  }




  void _applyListen(String raw) {
    final addr = raw.trim();
    if (!VpnModeConfig.isValidListenAddr(addr)) {
      setState(() => _listenError = 'Enter a valid IPv4 (e.g. 127.0.0.1)');
      return;
    }
    if (addr == _cfg.proxyListen) {
      setState(() => _listenError = '');
      return;
    }
    var next = _cfg.copyWith(proxyListen: addr);

    if (next.effectiveAuth && next.proxyPassword.isEmpty) {
      final pass = generateProxyPassword();
      next = next.copyWith(proxyPassword: pass);
      _passCtl.text = pass;
    }
    setState(() {
      _listenError = '';
      _cfg = next;
    });
    _commit();
  }

  void _toggleAuth(bool enable) {
    var next = _cfg.copyWith(proxyAuthEnabled: enable);
    if (enable && next.proxyPassword.isEmpty) {
      final pass = generateProxyPassword();
      next = next.copyWith(proxyPassword: pass);
      _passCtl.text = pass;
    }
    setState(() => _cfg = next);
    _commit();
  }

  void _applyPort(String raw) {
    final port = int.tryParse(raw);
    if (port == null || port < 1024 || port > 65535) {
      setState(() => _portError = 'Port must be 1024..65535');
      return;
    }
    if (port == _cfg.proxyPort) {
      setState(() => _portError = '');
      return;
    }
    setState(() {
      _portError = '';
      _cfg = _cfg.copyWith(proxyPort: port);
    });
    _commit();
  }

  void _applyUsername(String raw) {
    final u = raw.trim();
    if (u == _cfg.proxyUsername) return;
    setState(() => _cfg = _cfg.copyWith(proxyUsername: u));
    _commit();
  }

  void _applyPassword(String raw) {
    if (raw == _cfg.proxyPassword) return;
    setState(() => _cfg = _cfg.copyWith(proxyPassword: raw));
    _commit();
  }

  void _regeneratePassword() {
    final pass = generateProxyPassword();
    setState(() {
      _cfg = _cfg.copyWith(proxyPassword: pass);
      _passCtl.text = pass;
    });
    _commit();
  }




  Widget _labelRow(WizardVar node, TextStyle? style, {double iconSize = 18}) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Flexible(child: Text(node.title, style: style)),
        if (node.tooltip.isNotEmpty) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: node.tooltip,
            triggerMode: TooltipTriggerMode.tap,
            child: Icon(Icons.info_outline,
                size: iconSize, color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }



  String _shortLabel(String title) {
    final i = title.indexOf(' — ');
    return i >= 0 ? title.substring(0, i) : title;
  }



  Widget _buildModeSegments() {
    return SegmentedButton<String>(
      segments: _vpnModeNode.options
          .map((o) => ButtonSegment(
                value: o.value,
                label: Text(_shortLabel(o.title)),
              ))
          .toList(),
      selected: {_cfg.mode},
      onSelectionChanged: (s) => _setMode(s.first),
    );
  }


  Widget _buildEnumDropdown(
    WizardVar node, {
    required String current,
    required ValueChanged<String> onSelected,
  }) {
    return DropdownMenu<String>(
      initialSelection: current,
      label: Text(node.title),
      expandedInsets: EdgeInsets.zero,
      dropdownMenuEntries: node.options
          .map((o) => DropdownMenuEntry(value: o.value, label: o.title))
          .toList(),
      onSelected: (v) {
        if (v != null) onSelected(v);
      },
    );
  }






  Widget _buildListenCombobox() {
    return Focus(
      onFocusChange: (has) {
        if (!has) _applyListen(_listenCtl.text);
      },
      child: DropdownMenu<String>(
        controller: _listenCtl,
        requestFocusOnTap: true,
        enableFilter: false,
        label: Text(_listenNode.title),
        expandedInsets: EdgeInsets.zero,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        errorText: _listenError.isEmpty ? null : _listenError,
        dropdownMenuEntries: _listenNode.options
            .map((o) => DropdownMenuEntry(value: o.value, label: o.title))
            .toList(),
        onSelected: (v) {
          if (v != null) {
            _listenCtl.text = v;
            _applyListen(v);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final bottomPad = MediaQuery.of(context).padding.bottom + 24;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
      children: [

        _labelRow(_vpnModeNode, tt.titleMedium),
        const SizedBox(height: 8),
        _buildModeSegments(),
        const SizedBox(height: 8),
        Text(
          _modeDescription(_cfg.mode),
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),




        if (_cfg.hasTun) ...[
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          Text(getLocalText.s("Tunnel options"), style: tt.titleMedium),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(getLocalText.s("Keep VPN on exit")),
            subtitle: Text(getLocalText.s("VPN stays active when app is closed")),
            secondary: const Icon(Icons.exit_to_app),
            value: _keepOnExit,
            onChanged: _tunTogglesLoaded ? _toggleKeepOnExit : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(getLocalText.s("Allow VPN bypass")),
            subtitle: Text(
              _allowBypass
                  ? getLocalText.s("Apps may use ConnectivityManager to bypass tun.")
                  : getLocalText.s("Strict tunnel — all traffic goes through tun."),
            ),
            secondary: const Icon(Icons.alt_route),
            value: _allowBypass,
            onChanged: _tunTogglesLoaded ? _toggleAllowBypass : null,
          ),
        ],

        if (_cfg.hasMixed) ...[
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          Text(getLocalText.s("Local proxy"), style: tt.titleMedium),
          const SizedBox(height: 12),


          _labelRow(_proxyTypeNode, tt.bodyMedium, iconSize: 16),
          const SizedBox(height: 6),
          _buildEnumDropdown(
            _proxyTypeNode,
            current: _cfg.proxyProtocol,
            onSelected: _setProtocol,
          ),
          const SizedBox(height: 16),


          _labelRow(_listenNode, tt.bodyMedium, iconSize: 16),
          const SizedBox(height: 6),
          _buildListenCombobox(),
          const SizedBox(height: 4),
          Text(
            _cfg.isPublicListen
                ? getLocalText.s("Reachable from other devices on the network — auth required.")
                : getLocalText.s("Reachable only from this device."),
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),


          TextField(
            controller: _portCtl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: _portNode.title,
              helperText: getLocalText.s("Range 1024..65535"),
              errorText: _portError.isEmpty ? null : _portError,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: _applyPort,
          ),
          const SizedBox(height: 16),


          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_authNode.title),
            subtitle: Text(
              _cfg.isPublicListen
                  ? getLocalText.s("Required for LAN-exposed proxy (cannot be disabled).")
                  : getLocalText.s("Recommended. Protects the local proxy port."),
            ),
            value: _cfg.effectiveAuth,

            onChanged: _cfg.isPublicListen ? null : _toggleAuth,
          ),

          if (_cfg.effectiveAuth) ...[
            const SizedBox(height: 8),

            TextField(
              controller: _userCtl,
              decoration: InputDecoration(
                labelText: _userNode.title,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: _applyUsername,
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _passCtl,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                labelText: _passNode.title,
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: _showPassword
                          ? getLocalText.s("Hide")
                          : getLocalText.s("Show"),
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                    IconButton(
                      tooltip: getLocalText.s("Regenerate"),
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: _regeneratePassword,
                    ),
                  ],
                ),
              ),
              onChanged: _applyPassword,
            ),
          ],
        ],
      ],
    );
  }

  String _modeDescription(String mode) {
    switch (mode) {
      case 'proxy':
        return 'Local HTTP+SOCKS proxy only. No system-wide tunnel, no VPN key '
            'icon. Point apps at the proxy manually.';
      case 'vpn_proxy':
        return 'System-wide tunnel AND a local proxy port at the same time.';
      default:
        return 'System-wide tunnel — all traffic goes through the VPN (default).';
    }
  }
}
