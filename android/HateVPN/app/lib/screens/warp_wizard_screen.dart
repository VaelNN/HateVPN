import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/subscription_controller.dart';
import '../services/ui_helpers.dart';
import '../services/warp/masquerade_params.dart';
import '../services/warp/warp_account.dart';
import '../services/warp/masque_account.dart';
import '../services/warp/warp_endpoint_picker.dart';
import '../services/warp/scan/scan_pool.dart';
import '../services/settings_storage.dart';
import 'folder_detail_screen.dart';
import 'warp_experiment_screen.dart';
import '../services/l10n/locale_controller.dart';
import '../widgets/safe_bottom.dart';








class WarpWizardScreen extends StatefulWidget {
  const WarpWizardScreen({
    super.key,
    required this.subController,
    required this.onAdded,
  });

  final SubscriptionController subController;
  final Future<void> Function() onAdded;

  @override
  State<WarpWizardScreen> createState() => _WarpWizardScreenState();
}

class _WarpWizardScreenState extends State<WarpWizardScreen> with SnackHelper {
  final _license = TextEditingController();
  final _endpoint =
      TextEditingController(text: WarpAccount.defaultEndpoint);


  final _sni = TextEditingController();
  List<String> _sniPool = const [];
  List<String> _masqueSniPool = const [];

  String _masqIp = 'quic';
  String _masqIb = 'chrome';
  final _jc = TextEditingController(text: '4');
  final _jmin = TextEditingController(text: '40');
  final _jmax = TextEditingController(text: '70');



  final _keepalive = TextEditingController(text: '25');

  bool _forceNew = false;
  bool _busy = false;
  WarpAccount? _result;



  String _transport = 'wireguard';




  String _masqueNetwork = 'auto';
  final _masqueSni = TextEditingController();


  final _masqueIdle = TextEditingController();
  final _masqueKeepAlive = TextEditingController();



  final _masqueIp = TextEditingController();
  final _masquePort = TextEditingController();

  bool get _isMasque => _transport == 'masque';


  bool _obfuscate = false;


  bool? _includeReserved;

  WarpEndpointPicker? _picker;
  bool _endpointAutoFilled = false;



  String _lastAutoEndpoint = '';

  List<String> _endpointsPreset = const [];

  bool _ipv6Enabled = false;



  String _masqueRegServer = MasqueAccount.defaultServer;

  @override
  void initState() {
    super.initState();

    _endpoint.addListener(() {
      if (_endpointAutoFilled && _endpoint.text != _lastAutoEndpoint) {
        setState(() => _endpointAutoFilled = false);
      }
    });

    SettingsStorage.getVar('ipv6_enabled', 'false').then((v) {
      if (mounted) setState(() => _ipv6Enabled = v.toLowerCase() == 'true');
    });

    SettingsStorage.getMasqueAccount().then((acc) {
      if (mounted && acc != null) {
        setState(() => _masqueRegServer = acc.server);
      }
    });

    WarpEndpointPicker.load().then((p) {
      if (!mounted) return;
      setState(() {
        _picker = p;
        _sniPool = p.sniPool;
        _masqueSniPool = p.masqueSniPool;
        _endpointsPreset = p.endpointsPreset;


        if (_sni.text.trim().isEmpty) _sni.text = p.randomSni();



        if (_masqueSni.text.trim().isEmpty) {
          _masqueSni.text = p.randomMasqueSni();
        }

        _syncDefaultMasquePort(p);
      });

      if (_obfuscate && _endpointReplaceable) _fillRandomEndpoint();
    });
  }



  void _fillRandomEndpoint() {
    final ep = _picker?.randomEndpoint(allowV6: _ipv6Enabled);
    if (ep != null) {
      setState(() {


        _lastAutoEndpoint = ep;
        _endpoint.text = ep;
        _endpointAutoFilled = true;
      });
    }
  }


  void _fillRandomSni() {
    final sni = _picker?.randomSni();
    if (sni != null && sni.isNotEmpty) {
      setState(() => _sni.text = sni);
    }
  }


  void _fillRandomMasqueSni() {
    final sni = _picker?.randomMasqueSni();
    if (sni != null && sni.isNotEmpty) {
      setState(() => _masqueSni.text = sni);
    }
  }




  void _syncDefaultMasquePort([WarpEndpointPicker? picker]) {
    final ports = (picker ?? _picker)?.masquePortsFor(_masqueNetwork) ??
        const <int>[];
    if (ports.isEmpty) return;
    final cur = int.tryParse(_masquePort.text.trim());
    if (cur == null || !ports.contains(cur)) {
      _masquePort.text = '${ports.first}';
    }
  }



  List<String> get _masqueHostsForNetwork =>
      _picker?.masqueHostsFor(_masqueNetwork) ?? const <String>[];





  void _syncMasqueHostForNetwork() {
    final cur = _masqueIp.text.trim();
    if (cur.isEmpty) return;
    final known = _picker?.masqueH3Hosts ?? const <String>[];
    if (known.contains(cur) && !_masqueHostsForNetwork.contains(cur)) {
      _masqueIp.clear();
    }
  }



  void _fillRandomMasqueIp() {

    final ip = _picker?.randomMasqueIp(network: _masqueNetwork);
    if (ip == null) return;
    final port = _picker?.randomMasquePortFor(_masqueNetwork);
    setState(() {
      _masqueIp.text = ip;
      if (port != null) _masquePort.text = '$port';
    });
  }




  DropdownMenuEntry<String> _presetEntry(String value, String recommended) =>
      warpPresetEntry(value, recommended, getLocalText.s("(recommended)"));



  bool get _endpointReplaceable {
    final v = _endpoint.text.trim();
    return v.isEmpty || v == WarpAccount.defaultEndpoint || _endpointAutoFilled;
  }





  void _resetObfuscationFields() {
    setState(() {
      if (_endpointAutoFilled) {
        _endpoint.text = WarpAccount.defaultEndpoint;
        _endpointAutoFilled = false;
      }
      _includeReserved = null;
      _sni.text = _picker?.randomSni() ?? '';
      _masqIp = 'quic';
      _masqIb = 'chrome';
      _jc.text = '4';
      _jmin.text = '40';
      _jmax.text = '70';
    });
  }

  @override
  void dispose() {
    _license.dispose();
    _endpoint.dispose();
    _sni.dispose();
    _masqueSni.dispose();
    _masqueIdle.dispose();
    _masqueKeepAlive.dispose();
    _masqueIp.dispose();
    _masquePort.dispose();
    _jc.dispose();
    _jmin.dispose();
    _jmax.dispose();
    _keepalive.dispose();
    super.dispose();
  }






  Future<void> _runGenerate() async {
    if (_picker?.scan == null || _busy) return;


    final exp = await Navigator.of(context).push<({int count, ScanPool pool})>(
      MaterialPageRoute(builder: (_) => const WarpExperimentScreen()),
    );
    if (exp == null || !mounted) return;

    setState(() => _busy = true);
    int? folderIdx;
    try {
      folderIdx = await widget.subController.generateWarp(
          seedCount: exp.count, poolOverride: exp.pool);
    } catch (e) {
      if (mounted) {
        showSnack(getLocalText.s("Generation failed — no WARP account."));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;

    if (folderIdx == null) {
      showSnack(widget.subController.lastScanNote ??
          getLocalText.s("Generation failed — no WARP account."));
      return;
    }

    final note = widget.subController.lastScanNote;
    if (note != null) showSnack(note);



    final entry = widget.subController.entries[folderIdx];
    await Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => FolderDetailScreen(
        entry: entry,
        controller: widget.subController,
      ),
    ));
  }




  QuicParams _buildQuicParams() {
    return QuicParams(
      sni: _sni.text.trim(),
      ip: _masqIp,
      ib: _masqIb,
      jc: int.tryParse(_jc.text.trim()) ?? 4,
      jmin: int.tryParse(_jmin.text.trim()) ?? 40,
      jmax: int.tryParse(_jmax.text.trim()) ?? 70,
    );
  }

  Future<void> _register() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_isMasque) {
        await _registerMasque();
        return;
      }
      final endpoint = _endpoint.text.trim().isEmpty
          ? WarpAccount.defaultEndpoint
          : _endpoint.text.trim();
      final license = _license.text.trim();

      final account = await widget.subController.addWarp(
        licenseKey: license.isEmpty ? null : license,
        endpoint: endpoint,
        forceNew: _forceNew,
        obfuscate: _obfuscate,
        quicParams: _buildQuicParams(),
        includeReserved: _includeReserved,

        persistentKeepalive: int.tryParse(_keepalive.text.trim()),
      );

      if (!mounted) return;
      final err = widget.subController.lastError;
      if (account == null || err != null) {
        showSnack(err != null
            ? err.render()
            : getLocalText.s("WARP registration failed"));
        return;
      }
      setState(() => _result = account);
      await widget.onAdded();
      if (!mounted) return;
      showSnack(account.warpPlus
          ? getLocalText.s("Added WARP+ node")
          : getLocalText.s("Added WARP node"));
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  Future<void> _registerMasque() async {
    final sni = _masqueSni.text.trim();
    final ip = _masqueIp.text.trim();
    final account = await widget.subController.addMasque(
      vhttp: _masqueNetwork,
      sni: sni.isEmpty ? null : sni,
      idleTimeout: _durationOrNull(_masqueIdle.text, 'm'),
      keepAlive: _durationOrNull(_masqueKeepAlive.text, 's'),

      server: ip.isEmpty ? null : ip,
      port: int.tryParse(_masquePort.text.trim()),
      forceNew: _forceNew,
    );
    if (!mounted) return;
    final err = widget.subController.lastError;
    if (account == null || err != null) {
      showSnack(err != null
          ? err.render()
          : getLocalText.s("MASQUE registration failed"));
      return;
    }
    await widget.onAdded();
    if (!mounted) return;
    showSnack(getLocalText.s("Added MASQUE node"));
    Navigator.of(context).pop();
  }



  String? _durationOrNull(String raw, String unit) {
    final n = int.tryParse(raw.trim());
    if (n == null || n <= 0) return null;
    return '$n$unit';
  }



  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(getLocalText.s("Get WARP")),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(getLocalText.s("Cancel")),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32).withSafeBottom(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [




            Builder(builder: (context) {
              final w = MediaQuery.of(context).size.width;
              final logoW = (w * 0.40).clamp(120.0, 200.0);
              return Image.asset('assets/icons/cloudflare.png',
                  width: logoW, fit: BoxFit.contain);
            }),
            const SizedBox(height: 16),
            Text(

              'Cloudflare WARP',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              getLocalText.s("Registers a free WireGuard tunnel on Cloudflare. The private key is generated on this device and never leaves it."),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),


            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'wireguard',

                    label: Text('WireGuard'),
                    icon: Icon(Icons.vpn_key_outlined)),
                ButtonSegment(
                    value: 'masque',

                    label: Text('MASQUE'),
                    icon: Icon(Icons.hub_outlined)),
              ],
              selected: {_transport},
              onSelectionChanged: _busy
                  ? null
                  : (sel) => setState(() => _transport = sel.first),
            ),


            if (_picker?.scan != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _runGenerate,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.science_outlined),
                label: Text(getLocalText.s("Make experiment")),
              ),
            ],
            const SizedBox(height: 16),


            if (_isMasque) ...[
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        getLocalText.s("MASQUE tunnels IP over HTTP/3 (QUIC) to Cloudflare — standard HTTPS transport, and the exit IP is often in another country."),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _label('Transport'),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _masqueNetwork,
                              isDense: true,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                              items: const [
                                DropdownMenuItem(
                                    value: 'auto',

                                    child: Text('Auto (h3 → h2)')),
                                DropdownMenuItem(
                                    value: 'h3',

                                    child: Text('HTTP/3 (QUIC)')),
                                DropdownMenuItem(
                                    value: 'h2',

                                    child: Text('HTTP/2 (TCP)')),
                              ],
                              onChanged: _busy
                                  ? null
                                  : (v) => setState(() {
                                        _masqueNetwork = v ?? 'auto';


                                        _syncDefaultMasquePort();
                                        _syncMasqueHostForNetwork();
                                      }),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _masqueNetwork == 'h2'
                            ? getLocalText.s("HTTP/2 over TCP — use where QUIC/UDP is blocked.")
                            : _masqueNetwork == 'auto'
                                ? getLocalText.s("Tries HTTP/3 first, falls back to HTTP/2 where QUIC/UDP is blocked — best for hop chains.")
                                : getLocalText.s("HTTP/3 over QUIC — the default, fastest path."),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),



                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [


                          Expanded(
                            flex: 3,
                            child: LayoutBuilder(
                              builder: (ctx, c) => DropdownMenu<String>(
                                controller: _masqueIp,
                                enabled: !_busy,
                                width: c.maxWidth,
                                requestFocusOnTap: true,
                                menuHeight: 280,
                                label: Text(getLocalText.s("Endpoint IP")),
                                hintText: _masqueRegServer,
                                dropdownMenuEntries: [
                                  for (final h in _masqueHostsForNetwork)
                                    _presetEntry(h,
                                        _picker?.recommendedMasqueHost ?? ''),
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.casino_outlined),
                            tooltip: getLocalText.s("Pick another random IP:port"),
                            onPressed: _busy ? null : _fillRandomMasqueIp,
                          ),
                          const SizedBox(width: 8),


                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(


                              initialValue: _masquePort.text.isEmpty
                                  ? null
                                  : _masquePort.text,
                              isExpanded: true,
                              decoration: _input('443').copyWith(
                                labelText: getLocalText.s("Port"),
                              ),
                              items: [
                                for (final p in (_picker
                                        ?.masquePortsFor(_masqueNetwork) ??
                                    const <int>[]))
                                  DropdownMenuItem(
                                      value: '$p', child: Text('$p')),
                              ],
                              onChanged: _busy
                                  ? null
                                  : (v) => setState(
                                      () => _masquePort.text = v ?? ''),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        getLocalText.s("Leave IP empty to use the server from registration. HTTP/3 only works on a few Cloudflare addresses, HTTP/2 works across the whole block."),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 12),
                      _label('SNI'),





                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: LayoutBuilder(
                              builder: (ctx, c) => DropdownMenu<String>(
                                controller: _masqueSni,
                                enabled: !_busy,
                                width: c.maxWidth,
                                requestFocusOnTap: true,
                                menuHeight: 280,
                                hintText: getLocalText.s("Leave empty for the default SNI"),
                                dropdownMenuEntries: [
                                  for (final s in _masqueSniPool)
                                    _presetEntry(s,
                                        _picker?.recommendedMasqueSni ?? ''),
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.casino_outlined),
                            tooltip: getLocalText.s("Pick another random domain"),
                            onPressed: _busy ? null : _fillRandomMasqueSni,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _masqueIdle,
                              enabled: !_busy,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              decoration: _input('5').copyWith(
                                labelText: getLocalText.s("Idle timeout (min)"),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _masqueKeepAlive,


                              enabled: !_busy && _masqueNetwork != 'h2',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              decoration: _input('30').copyWith(
                                labelText: getLocalText.s("Keep-alive (sec)"),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        getLocalText.s("Idle timeout suspends the tunnel after inactivity to save battery (default 5 min). Keep-alive pings the QUIC link (default 30 sec, HTTP/3 only). Leave empty for defaults."),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _forceNew,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _forceNew = v ?? false),
                        title: Text(getLocalText.s("Re-register (force new account)")),
                        subtitle: Text(getLocalText.s("Ignore the cached account and register a fresh one.")),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (!_isMasque)
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  CheckboxListTile(
                    value: _obfuscate,
                    onChanged: _busy
                        ? null
                        : (v) {
                            final on = v ?? false;
                            setState(() => _obfuscate = on);
                            if (on) {



                              if (_endpointReplaceable) _fillRandomEndpoint();
                            } else {



                              _resetObfuscationFields();
                            }
                          },
                    title: Text(getLocalText.s("Add Amnezia obfuscation")),
                    subtitle: Text(getLocalText.s("Adds padding traffic so the WireGuard handshake carries no fixed size signature. Enable if the plain tunnel does not connect.")),
                  ),


                  if (_obfuscate)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        getLocalText.s("Junk traffic masquerades as a real protocol. Pick protocol/domain in Advanced."),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ),
                ],
              ),
            ),


            if (!_isMasque) ...[
            const SizedBox(height: 16),
            ExpansionPanelList.radio(
              elevation: 0,
              expandedHeaderPadding: EdgeInsets.zero,
              children: [
                ExpansionPanelRadio(
                  value: 'advanced',
                  canTapOnHeader: true,
                  headerBuilder: (_, _) =>
                      ListTile(title: Text(getLocalText.s("Advanced"))),
                  body: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _label('WARP+ license key'),
                        TextField(
                          controller: _license,
                          enabled: !_busy,
                          decoration: _input('Leave empty for free WARP'),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          getLocalText.s("WARP+ adds Argo Smart Routing (lower latency). Privacy is the same as free. Leave empty for free WARP."),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 12),
                        _label('Endpoint'),



                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: LayoutBuilder(
                                builder: (ctx, c) => DropdownMenu<String>(
                                  controller: _endpoint,
                                  enabled: !_busy,
                                  width: c.maxWidth,
                                  requestFocusOnTap: true,
                                  menuHeight: 280,
                                  hintText: WarpAccount.defaultEndpoint,
                                  dropdownMenuEntries: [
                                    for (final e in _endpointsPreset)
                                      _presetEntry(e,
                                          _picker?.recommendedEndpoint ?? ''),
                                  ],
                                ),
                              ),
                            ),


                            if (_obfuscate)
                              IconButton(
                                icon: const Icon(Icons.casino_outlined),
                                tooltip: getLocalText.s("Pick another random IP:port"),
                                onPressed: _busy ? null : _fillRandomEndpoint,
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          getLocalText.s("host:port of the Cloudflare peer. With obfuscation a random working IP:port is filled in — tap the dice to reroll, or type your own to pin a specific one."),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                        ),



                        const SizedBox(height: 12),
                        _label('Persistent keepalive (s)'),
                        TextField(
                          controller: _keepalive,
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          decoration: _input('25'),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          getLocalText.s("Keeps the tunnel alive while idle so it doesn't rot to timeouts (default 25). 0 = off."),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                        ),


                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _includeReserved ?? !_obfuscate,
                          onChanged: _busy
                              ? null
                              : (v) =>
                                  setState(() => _includeReserved = v),
                          title: Text(getLocalText.s("Bind to this device (reserved)")),
                          subtitle: Text(getLocalText.s("Sends the Cloudflare client_id. Off for obfuscation (the device binding tends to get blocked).")),
                        ),

                        if (_obfuscate) ...[
                          const SizedBox(height: 16),

                          Row(
                            children: [
                              _label('Masquerade protocol'),
                              const SizedBox(width: 16),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _masqIp,
                                  isDense: true,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                  ),
                                  items: const [
                                    DropdownMenuItem(

                                        value: 'quic', child: Text('QUIC')),
                                    DropdownMenuItem(

                                        value: 'dns', child: Text('DNS')),
                                    DropdownMenuItem(

                                        value: 'stun', child: Text('STUN')),
                                    DropdownMenuItem(

                                        value: 'sip', child: Text('SIP')),
                                  ],
                                  onChanged: _busy
                                      ? null
                                      : (v) => setState(
                                          () => _masqIp = v ?? 'quic'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _masqIp == 'dns' || _masqIp == 'sip'


                                ? getLocalText.s("Domain (below) is visible on the wire as the %s.", _masqIp == 'dns' ? 'DNS QNAME' : 'SIP host')
                                : getLocalText.s("QUIC/STUN decoy carries no hostname — the domain below is cosmetic for this protocol."),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          _label('Masquerade domain (id)'),





                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (ctx, c) => DropdownMenu<String>(
                                    controller: _sni,
                                    enabled: !_busy,
                                    width: c.maxWidth,
                                    requestFocusOnTap: true,
                                    menuHeight: 280,
                                    dropdownMenuEntries: [
                                      for (final s in _sniPool)
                                        DropdownMenuEntry(value: s, label: s),
                                    ],
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.casino_outlined),
                                tooltip: getLocalText.s("Pick another random domain"),
                                onPressed: _busy ? null : _fillRandomSni,
                              ),
                            ],
                          ),

                          if (_masqIp == 'quic') ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                _label('Browser (ib)'),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _masqIb,
                                    isDense: true,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'chrome',

                                          child: Text('Chrome')),
                                      DropdownMenuItem(
                                          value: 'firefox',

                                          child: Text('Firefox')),
                                      DropdownMenuItem(
                                          value: 'curl',

                                          child: Text('cURL')),
                                    ],
                                    onChanged: _busy
                                        ? null
                                        : (v) => setState(
                                            () => _masqIb = v ?? 'chrome'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _numField(_jc, 'Jc'),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _numField(_jmin, 'Jmin'),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _numField(_jmax, 'Jmax'),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _forceNew,
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _forceNew = v ?? false),
                          title: Text(getLocalText.s("Re-register (force new account)")),
                          subtitle: Text(getLocalText.s("Ignore the cached account and register a fresh one.")),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _register,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bolt),
              label: Text(_busy
                  ? getLocalText.s("Registering…")
                  : getLocalText.s("Register")),
            ),
            if (_result != null) ...[
              const SizedBox(height: 16),
              _StatusCard(account: _result!),
            ],
          ],
        ),
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


  Widget _numField(TextEditingController c, String label) => TextField(
        controller: c,
        enabled: !_busy,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
      );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.account});
  final WarpAccount account;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                account.warpPlus
                    ? getLocalText.s("Registered: WARP+")
                    : getLocalText.s("Registered: WARP"),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _row('Account', account.accountId),
            _row('Device', account.deviceId),
            _row('Address', account.clientV4),
            _row('Endpoint', account.endpoint),
            if (account.awg != null) _row('Obfuscation', 'Amnezia 1.5'),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(width: 80, child: Text(k)),
            Expanded(
              child: Text(v,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12)),
            ),
          ],
        ),
      );
}







DropdownMenuEntry<String> warpPresetEntry(
    String value, String recommended, String mark) {
  final marked = recommended.isNotEmpty && value == recommended;
  return DropdownMenuEntry(
    value: value,
    label: value,
    labelWidget: marked ? Text('$value $mark') : null,
  );
}
