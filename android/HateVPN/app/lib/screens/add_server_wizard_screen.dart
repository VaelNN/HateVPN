import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import '../controllers/subscription_controller.dart';
import '../models/node_spec.dart';
import '../models/server_list.dart';
import '../models/template_vars.dart';
import '../models/tls_spec.dart';
import '../services/parser/uri_utils.dart' show newUuidV4;
import '../services/ui_helpers.dart';
import '../widgets/emoji_picker_button.dart';
import '../widgets/lx_code_editor.dart';
import '../services/l10n/locale_controller.dart';
import '../services/subscription/subscription_identity.dart';
import '../widgets/safe_bottom.dart';
import '../models/tailscale_bundle.dart';




final TemplateVars _emptyVars = TemplateVars.empty;
















class AddServerWizardScreen extends StatefulWidget {
  const AddServerWizardScreen({
    super.key,
    required this.subController,
    required this.onAdded,
  });

  final SubscriptionController subController;
  final Future<void> Function() onAdded;

  @override
  State<AddServerWizardScreen> createState() => _AddServerWizardScreenState();
}

class _AddServerWizardScreenState extends State<AddServerWizardScreen>
    with SingleTickerProviderStateMixin, SnackHelper {
  late final TabController _tab;


  static const _kDefaultSocksTag = 'local-socks5-out';
  static const _kDefaultHttpTag = 'local-http-out';









  final _socksTag = TextEditingController();
  final _socksHost = TextEditingController(text: '127.0.0.1');
  final _socksPort = TextEditingController(text: '1080');
  final _socksUser = TextEditingController();
  final _socksPass = TextEditingController();
  final _socksFormKey = GlobalKey<FormState>();


  final _httpTag = TextEditingController();
  final _httpHost = TextEditingController(text: '127.0.0.1');
  final _httpPort = TextEditingController(text: '8080');
  final _httpUser = TextEditingController();
  final _httpPass = TextEditingController();
  final _httpFormKey = GlobalKey<FormState>();
  bool _httpTls = false;



  final _uriCtrl = CodeLineEditingController();


  final _jsonCtrl = CodeLineEditingController();





  static const _kDefaultTailscaleTag = 'tailscale';
  final _tsTag = TextEditingController();
  final _tsAuthKey = TextEditingController();
  final _tsControlUrl = TextEditingController();
  final _tsHostname = TextEditingController();
  final _tsExitNode = TextEditingController();
  final _tsFormKey = GlobalKey<FormState>();
  bool _tsEphemeral = false;
  bool _tsAcceptRoutes = false;
  bool _tsShowKey = false;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
    _tab.addListener(() => setState(() {}));


    _tsHostname.text =
        defaultTailscaleHostname(SubscriptionIdentity.effectiveDeviceModel);
  }

  @override
  void dispose() {
    _tab.dispose();
    _socksTag.dispose();
    _socksHost.dispose();
    _socksPort.dispose();
    _socksUser.dispose();
    _socksPass.dispose();
    _httpTag.dispose();
    _httpHost.dispose();
    _httpPort.dispose();
    _httpUser.dispose();
    _httpPass.dispose();
    _uriCtrl.dispose();
    _jsonCtrl.dispose();
    _tsTag.dispose();
    _tsAuthKey.dispose();
    _tsControlUrl.dispose();
    _tsHostname.dispose();
    _tsExitNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      switch (_tab.index) {
        case 0:
          await _submitSocks();
        case 1:
          await _submitHttp();
        case 2:
          await _submitInput(_uriCtrl.text);
        case 3:
          await _submitInput(_jsonCtrl.text);
        case 4:
          await _submitTailscale();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }







  Future<void> _submitTailscale() async {
    if (!(_tsFormKey.currentState?.validate() ?? false)) return;
    final tagInput = _tsTag.text.trim();
    final tag = tagInput.isNotEmpty ? tagInput : _kDefaultTailscaleTag;
    final controlUrl = _tsControlUrl.text.trim();
    final hostname = _tsHostname.text.trim();
    final exitNode = _tsExitNode.text.trim();

    final spec = TailscaleSpec(
      id: newUuidV4(),
      tag: tag,
      label: tag,
      body: {
        'auth_key': _tsAuthKey.text.trim(),
        if (controlUrl.isNotEmpty) 'control_url': controlUrl,
        if (hostname.isNotEmpty) 'hostname': hostname,
        if (_tsEphemeral) 'ephemeral': true,
        if (_tsAcceptRoutes) 'accept_routes': true,
        if (exitNode.isNotEmpty) 'exit_node': exitNode,
      },
    );

    final us = UserServer(
      id: newUuidV4(),
      name: '',
      enabled: true,
      tagPrefix: '',
      detourPolicy: DetourPolicy.defaults,
      origin: UserSource.manual,
      rawBody: spec.toUri(),
      nodes: [spec],
    );
    await widget.subController.addUserServer(us);
    await _afterAdd(addedTag: tag);
  }

  Future<void> _submitSocks() async {
    if (!(_socksFormKey.currentState?.validate() ?? false)) return;

    final tagInput = _socksTag.text.trim();
    final tag = tagInput.isNotEmpty ? tagInput : _kDefaultSocksTag;
    final host = _socksHost.text.trim();



    final port = int.tryParse(_socksPort.text.trim()) ?? 0;
    if (port < 1 || port > 65535) {
      showSnack(getLocalText.s("Invalid port"));
      return;
    }
    final user = _socksUser.text;
    final pass = _socksPass.text;





    final spec = SocksSpec(
      id: newUuidV4(),
      tag: tag,
      label: tag,
      server: host,
      port: port,
      rawSource: '',
      username: user,
      password: pass,
    );





    final outboundJson = spec.emit(_emptyVars).map;
    final us = UserServer(
      id: newUuidV4(),
      name: '',
      enabled: true,
      tagPrefix: '',
      detourPolicy: DetourPolicy.defaults,
      origin: UserSource.manual,
      rawBody: jsonEncode(outboundJson),
      nodes: [spec],
    );
    await widget.subController.addUserServer(us);
    await _afterAdd(addedTag: tag);
  }



  Future<void> _submitHttp() async {
    if (!(_httpFormKey.currentState?.validate() ?? false)) return;

    final tagInput = _httpTag.text.trim();
    final tag = tagInput.isNotEmpty ? tagInput : _kDefaultHttpTag;
    final host = _httpHost.text.trim();
    final port = int.tryParse(_httpPort.text.trim()) ?? 0;
    if (port < 1 || port > 65535) {
      showSnack(getLocalText.s("Invalid port"));
      return;
    }

    final spec = HttpSpec(
      id: newUuidV4(),
      tag: tag,
      label: tag,
      server: host,
      port: port,
      rawSource: '',
      username: _httpUser.text,
      password: _httpPass.text,

      tls: _httpTls
          ? TlsSpec(enabled: true, serverName: host)
          : TlsSpec.disabled,
    );

    final outboundJson = spec.emit(_emptyVars).map;
    final us = UserServer(
      id: newUuidV4(),
      name: '',
      enabled: true,
      tagPrefix: '',
      detourPolicy: DetourPolicy.defaults,
      origin: UserSource.manual,
      rawBody: jsonEncode(outboundJson),
      nodes: [spec],
    );
    await widget.subController.addUserServer(us);
    await _afterAdd(addedTag: tag);
  }

  Future<void> _submitInput(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      showSnack(getLocalText.s("Input is empty"));
      return;
    }
    await widget.subController.addFromInput(trimmed);
    await _afterAdd(addedTag: null);
  }









  Future<void> _afterAdd({String? addedTag}) async {
    if (!mounted) return;
    final err = widget.subController.lastError;
    if (err != null) {
      showSnack(err.render());
      return;
    }
    await widget.onAdded();
    if (!mounted) return;

    final msg = widget.subController.lastCommentsRemoved
        ? getLocalText.s("Comments were removed.")
        : addedTag != null && addedTag.isNotEmpty
            ? getLocalText.s("Added: %s", addedTag)
            : getLocalText.s("Added");
    showSnack(msg);
    Navigator.of(context).pop();
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(getLocalText.s("Add server")),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(getLocalText.s("Cancel")),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(getLocalText.s("Add")),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: getLocalText.s("SOCKS5")),
            Tab(text: getLocalText.s("HTTP")),
            Tab(text: getLocalText.s("Paste URI")),
            Tab(text: getLocalText.s("Paste JSON")),


            const Tab(text: 'Tailscale'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildSocksForm(context),
          _buildHttpForm(context),
          _buildUriPaste(context),
          _buildJsonPaste(context),
          _buildTailscaleForm(context),
        ],
      ),
    );
  }


  void _insertTailscaleTagEmoji(String emoji) {
    final text = _tsTag.text;
    final sel = _tsTag.selection;
    final start =
        (sel.start >= 0 && sel.start <= text.length) ? sel.start : text.length;
    final end = (sel.end >= 0 && sel.end <= text.length) ? sel.end : start;
    final insert = '$emoji ';
    _tsTag.value = TextEditingValue(
      text: text.replaceRange(start, end, insert),
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
    setState(() {});
  }




  Widget _buildTailscaleForm(BuildContext context) {
    final hintStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32).withSafeBottom(context),
      child: Form(
        key: _tsFormKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _label(getLocalText.s("Tag (optional)")),
            TextFormField(
              controller: _tsTag,
              decoration: _input(_kDefaultTailscaleTag).copyWith(
                suffixIcon: EmojiPickerButton(onPick: _insertTailscaleTagEmoji),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              getLocalText.s("Shown as the server title in the Servers list. If empty, \"%s\" is used.", _kDefaultTailscaleTag),
              style: hintStyle,
            ),
            const SizedBox(height: 12),
            _label(getLocalText.s("Auth key")),
            TextFormField(
              controller: _tsAuthKey,
              obscureText: !_tsShowKey,
              autocorrect: false,
              enableSuggestions: false,
              decoration: _input('tskey-auth-…').copyWith(
                suffixIcon: IconButton(
                  tooltip: _tsShowKey
                      ? getLocalText.s("Hide")
                      : getLocalText.s("Show"),
                  icon: Icon(
                    _tsShowKey ? Icons.visibility_off : Icons.visibility,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _tsShowKey = !_tsShowKey),
                ),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? getLocalText.s("Auth key required")
                  : null,
            ),
            const SizedBox(height: 6),
            Text(
              getLocalText.s("A one-time key is consumed on the first login; the device identity then lives in the state directory. Clearing the app data registers a new device."),
              style: hintStyle,
            ),
            const SizedBox(height: 12),
            _label(getLocalText.s("Control URL (optional)")),
            TextFormField(
              controller: _tsControlUrl,
              decoration: _input('https://controlplane.tailscale.com'),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            _label(getLocalText.s("Hostname (optional)")),
            TextFormField(
              controller: _tsHostname,
              decoration: _input(''),
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(getLocalText.s("Ephemeral")),
              subtitle: Text(getLocalText.s("The device is removed from the tailnet when it goes offline")),
              value: _tsEphemeral,
              onChanged: (v) => setState(() => _tsEphemeral = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(getLocalText.s("Accept routes")),
              subtitle: Text(getLocalText.s("Use subnet routes advertised by other tailnet devices")),
              value: _tsAcceptRoutes,
              onChanged: (v) => setState(() => _tsAcceptRoutes = v),
            ),
            const SizedBox(height: 12),
            _label(getLocalText.s("Exit node (optional)")),
            TextFormField(
              controller: _tsExitNode,
              decoration: _input(''),
              autocorrect: false,
            ),
            const SizedBox(height: 6),
            Text(
              getLocalText.s("Tailscale IP or machine name of a peer that advertises an exit node; pick this node as the Direction on Home to route your internet through it. Leave empty for tailnet access only — the node will not appear in Directions"),
              style: hintStyle,
            ),
          ],
        ),
      ),
    );
  }


  void _insertSocksTagEmoji(String emoji) {
    final text = _socksTag.text;
    final sel = _socksTag.selection;
    final start =
        (sel.start >= 0 && sel.start <= text.length) ? sel.start : text.length;
    final end = (sel.end >= 0 && sel.end <= text.length) ? sel.end : start;
    final insert = '$emoji ';
    _socksTag.value = TextEditingValue(
      text: text.replaceRange(start, end, insert),
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
    setState(() {});
  }

  Widget _buildSocksForm(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32).withSafeBottom(context),
      child: Form(
        key: _socksFormKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [


            _label(getLocalText.s("Tag (optional)")),
            TextFormField(
              controller: _socksTag,
              decoration: _input(_kDefaultSocksTag).copyWith(
                suffixIcon: EmojiPickerButton(onPick: _insertSocksTagEmoji),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              getLocalText.s("Shown as the server title in the Servers list. If empty, \"%s\" is used.", _kDefaultSocksTag),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            _label(getLocalText.s("Host")),
            TextFormField(
              controller: _socksHost,
              decoration: _input('127.0.0.1'),
              keyboardType: TextInputType.url,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? getLocalText.s("Host required")
                  : null,
            ),
            const SizedBox(height: 12),
            _label(getLocalText.s("Port")),
            TextFormField(
              controller: _socksPort,
              decoration: _input('1080'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                if (n == null || n < 1 || n > 65535) {
                  return getLocalText.s("Port 1..65535");
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _label(getLocalText.s("Username (optional)")),
            TextFormField(
              controller: _socksUser,
              decoration: _input(''),
            ),
            const SizedBox(height: 12),
            _label(getLocalText.s("Password (optional)")),
            TextFormField(
              controller: _socksPass,
              decoration: _input(''),
              obscureText: true,
            ),
          ],
        ),
      ),
    );
  }


  void _insertHttpTagEmoji(String emoji) {
    final text = _httpTag.text;
    final sel = _httpTag.selection;
    final start =
        (sel.start >= 0 && sel.start <= text.length) ? sel.start : text.length;
    final end = (sel.end >= 0 && sel.end <= text.length) ? sel.end : start;
    final insert = '$emoji ';
    _httpTag.value = TextEditingValue(
      text: text.replaceRange(start, end, insert),
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
    setState(() {});
  }

  Widget _buildHttpForm(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32).withSafeBottom(context),
      child: Form(
        key: _httpFormKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [


            _label(getLocalText.s("Tag (optional)")),
            TextFormField(
              controller: _httpTag,
              decoration: _input(_kDefaultHttpTag).copyWith(
                suffixIcon: EmojiPickerButton(onPick: _insertHttpTagEmoji),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              getLocalText.s("Shown as the server title in the Servers list. If empty, \"%s\" is used.", _kDefaultHttpTag),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            _label(getLocalText.s("Host")),
            TextFormField(
              controller: _httpHost,
              decoration: _input('127.0.0.1'),
              keyboardType: TextInputType.url,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? getLocalText.s("Host required")
                  : null,
            ),
            const SizedBox(height: 12),
            _label(getLocalText.s("Port")),
            TextFormField(
              controller: _httpPort,
              decoration: _input('8080'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                if (n == null || n < 1 || n > 65535) {
                  return getLocalText.s("Port 1..65535");
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _label(getLocalText.s("Username (optional)")),
            TextFormField(
              controller: _httpUser,
              decoration: _input(''),
            ),
            const SizedBox(height: 12),
            _label(getLocalText.s("Password (optional)")),
            TextFormField(
              controller: _httpPass,
              decoration: _input(''),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(getLocalText.s("HTTPS (TLS to proxy)")),
              subtitle: Text(getLocalText.s("Connect to the proxy over TLS. Advanced TLS options (SNI, ALPN) can be edited later via node JSON.")),
              value: _httpTls,
              onChanged: (v) => setState(() => _httpTls = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUriPaste(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(getLocalText.s("Paste a proxy URL")),
          Expanded(
            child: LxCodeEditor(
              controller: _uriCtrl,
              fontSize: 13,
              hint:
                  'vless://… / vmess://… / trojan://… / socks5://… / proxy-http://… / wireguard://…',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            getLocalText.s("Supported: vless / vmess / trojan / ss / hy2 / tuic / socks5 / proxy-http(s) / wireguard URLs"),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildJsonPaste(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(getLocalText.s("Paste a sing-box outbound JSON")),
          Expanded(
            child: LxCodeEditor(
              controller: _jsonCtrl,
              fontSize: 13,
              hint: '{"type": "vless", "tag": "…", …}',
              language: LxCodeLanguage.json,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            getLocalText.s("Single object or array of outbounds. WireGuard routes to endpoints[] automatically."),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                )),
      );

  InputDecoration _input(String hint) => InputDecoration(
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      );
}
