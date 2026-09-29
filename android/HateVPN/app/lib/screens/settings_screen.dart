import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/home_controller.dart';
import '../controllers/subscription_controller.dart';
import '../models/background_mode.dart';
import '../models/memory_limit_setting.dart';
import '../models/parser_config.dart';
import '../services/builder/if_engine.dart';
import '../services/l10n/template_aware_state.dart';
import '../services/settings_storage.dart';
import '../services/template_loader.dart';
import '../widgets/template_var_list.dart';
import '../widgets/var_values_model.dart';
import 'vpn_mode_tab.dart';
import '../services/l10n/locale_controller.dart';





















Widget dimmedWhenDisabled({required bool enabled, required Widget child}) {
  if (enabled) return child;
  return Opacity(opacity: kDisabledRowOpacity, child: child);
}


const double kDisabledRowOpacity = 0.38;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.subController,
    required this.homeController,
    this.initialTab = 0,
  });

  final SubscriptionController subController;
  final HomeController homeController;


  final int initialTab;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver, TemplateAwareState<SettingsScreen> {


  WizardTemplate? _template;













  VarValuesModel? _model;
  bool _loading = true;

  BackgroundMode _backgroundMode = BackgroundMode.never;
  bool _vpnLoaded = false;



  bool _interruptOnSwitch = false;
  String _idleSuspend = '';

  String _idleSuspendReachable = '';
  int _wgBuildMax = 5;
  bool _wgLazyBuild = true;
  bool _passiveCheck = true;

  String _memoryLimit = MemoryLimitSetting.auto;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

  }




  @override
  void onLocaleTemplateFetch({required bool first}) {
    if (first) {
      unawaited(_load());
    } else {
      unawaited(_refetchTemplate());
    }
  }

  Future<void> _refetchTemplate() async {
    final template = await TemplateLoader.load();
    if (!mounted) return;
    setState(() => _template = template);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);



    if (_model?.dirtyKeys.isNotEmpty ?? false) unawaited(_persist());
    _model?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused &&
        (_model?.dirtyKeys.isNotEmpty ?? false)) {
      unawaited(_persist());
    }
  }





  Future<void> _persist() async {
    final model = _model;
    if (model == null || model.dirtyKeys.isEmpty) return;

    final staged = {for (final k in model.dirtyKeys) k: model.get(k)};
    model.clearDirty();
    for (final e in staged.entries) {
      await SettingsStorage.setVar(e.key, e.value, flush: false);
    }
    await SettingsStorage.flushToDisk();

  }

  Future<void> _load() async {
    final template = await TemplateLoader.load();
    final storedVars = await SettingsStorage.getAllVars();
    _model = VarValuesModel({
      for (final v in template.vars)
        v.name: storedVars[v.name] ?? v.defaultValue,
    });

    final bgMode = BackgroundMode.fromNative(
        await SettingsStorage.getNativeBackgroundMode());
    final interruptOnSwitch = await SettingsStorage.getInterruptOnSwitch();
    final idleSuspend = await SettingsStorage.getIdleSuspend();
    final idleSuspendReachable =
        await SettingsStorage.getIdleSuspendReachable();
    final wgBuildMax = await SettingsStorage.getWgBuildMax();
    final wgLazyBuild = await SettingsStorage.getWgLazyBuild();
    final passiveCheck = await SettingsStorage.getPassiveCheck();
    final memoryLimit = await SettingsStorage.getNativeMemoryLimit();
    setState(() {
      _template = template;
      _backgroundMode = bgMode;
      _interruptOnSwitch = interruptOnSwitch;
      _idleSuspend = idleSuspend;
      _idleSuspendReachable = idleSuspendReachable;
      _wgBuildMax = wgBuildMax;
      _wgLazyBuild = wgLazyBuild;
      _passiveCheck = passiveCheck;
      _memoryLimit = memoryLimit;
      _vpnLoaded = true;
      _loading = false;
    });
  }



  void _toggleInterruptOnSwitch(bool val) {
    setState(() => _interruptOnSwitch = val);
    unawaited(SettingsStorage.setInterruptOnSwitch(val));
  }



  Future<void> _applyBackgroundMode(BackgroundMode? mode) async {
    if (mode == null || mode == _backgroundMode) return;
    setState(() => _backgroundMode = mode);

    await SettingsStorage.setNativeBackgroundMode(mode.wireValue);
    widget.homeController.markConfigChangedNeedRestart();
  }



  Future<void> _applyIdleSuspend(String value) async {
    if (value == _idleSuspend) return;
    setState(() => _idleSuspend = value);
    await SettingsStorage.saveIdleSuspend(value);
    widget.subController.configDirty = true;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(getLocalText.s("Applies on next connect.")),
        duration: const Duration(seconds: 3),
      ),
    );
  }






  bool get _idleSuspendReachableEnabled =>
      _vpnLoaded && _idleSuspend.isNotEmpty;




  bool get _wgLazyBuildEnabled => _vpnLoaded && _idleSuspend.isNotEmpty;



  bool get _wgBuildMaxEnabled => _wgLazyBuildEnabled && _wgLazyBuild;

  Future<void> _applyWgLazyBuild(bool value) async {
    if (value == _wgLazyBuild) return;
    setState(() => _wgLazyBuild = value);
    await SettingsStorage.saveWgLazyBuild(value);
    widget.subController.configDirty = true;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(getLocalText.s("Applies on next connect.")),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _applyWgBuildMax(int value) async {
    if (value == _wgBuildMax) return;
    setState(() => _wgBuildMax = value);
    await SettingsStorage.saveWgBuildMax(value);
    widget.subController.configDirty = true;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(getLocalText.s("Applies on next connect.")),
        duration: const Duration(seconds: 3),
      ),
    );
  }



  Future<void> _applyIdleSuspendReachable(String value) async {
    if (value == _idleSuspendReachable) return;
    setState(() => _idleSuspendReachable = value);
    await SettingsStorage.saveIdleSuspendReachable(value);
    widget.subController.configDirty = true;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(getLocalText.s("Applies on next connect.")),
        duration: const Duration(seconds: 3),
      ),
    );
  }


  Future<void> _applyPassiveCheck(bool value) async {
    if (value == _passiveCheck) return;
    setState(() => _passiveCheck = value);
    await SettingsStorage.savePassiveCheck(value);
    widget.subController.configDirty = true;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(getLocalText.s("Applies on next connect.")),
        duration: const Duration(seconds: 3),
      ),
    );
  }




  Future<void> _applyMemoryLimit(String value) async {
    if (value == _memoryLimit) return;
    setState(() => _memoryLimit = value);
    await SettingsStorage.setNativeMemoryLimit(value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(getLocalText.s("Applied.")),
        duration: const Duration(seconds: 3),
      ),
    );
  }





  void _onVarChanged(String name, String value) {
    widget.subController.configDirty = true;
    _applyOnChange(name);
  }







  void _applyOnChange(String name) {
    final model = _model;
    final template = _template;
    if (model == null || template == null) return;
    final node = template.vars.where((v) => v.name == name).firstOrNull;

    final set = node?.onChange?['#set'] ?? node?.onChange?['set'];
    if (set is! Map<String, dynamic>) return;
    final byName = {for (final v in template.vars) v.name: v};
    final resolve = makeResolver(model.snapshot, byName);
    set.forEach((target, ifNode) {
      final tName = target.startsWith('@') ? target.substring(1) : target;
      if (ifNode is! Map<String, dynamic>) return;
      final resolved = evalIfScalar(ifNode, resolve);
      if (resolved == null) return;
      if (model.set(tName, resolved)) {
        widget.subController.configDirty = true;
        _applyOnChange(tName);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(getLocalText.s("VPN Settings"))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final template = _template!;
    final editableVars = template
        .varsFor('core')
        .where((v) => v.isEditable)
        .toList();

    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab.clamp(0, 2),
      child: Scaffold(
        appBar: AppBar(
          title: Text(getLocalText.s("VPN Settings")),
          bottom: TabBar(
            tabs: [
              Tab(text: getLocalText.s("System")),
              Tab(text: getLocalText.s("Core")),
              Tab(text: getLocalText.s("Mode")),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildSystemTab(context),
            _buildCoreTab(context, template, editableVars),
            VpnModeTab(
              homeController: widget.homeController,
              subController: widget.subController,
              template: template,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemTab(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom + 24;
    return ListView(
      padding: EdgeInsets.fromLTRB(12, 12, 12, bottomPad),
      children: [


        SwitchListTile(
          title: Text(getLocalText.s("Interrupt connections on switch")),
          subtitle: Text(getLocalText.s("Drop active connections when you switch nodes, so traffic moves to the new node immediately")),
          secondary: const Icon(Icons.swap_horiz),
          value: _interruptOnSwitch,
          onChanged: _toggleInterruptOnSwitch,
        ),
        const Divider(height: 32),


        const TemplateSectionHeader(
          title: 'WireGuard connections',
          description:
              'Sleep WireGuard/AmneziaWG tunnels to save battery and memory. '
              'Sleeping tunnels wake automatically on first use.',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                getLocalText.s("Suspend idle tunnels"),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 2),
              Text(
                getLocalText.s("Put unreachable WireGuard tunnels to sleep after they sit idle, freeing memory and saving battery. They wake instantly on use. Only affects tunnels not on the active route."),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: DropdownButtonFormField<String>(
            initialValue: _idleSuspend,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              DropdownMenuItem<String>(
                  value: '', child: Text(getLocalText.s("Off"))),
              DropdownMenuItem<String>(
                  value: '30s',
                  child: Text(getLocalText.plural("%d seconds", 30))),
              DropdownMenuItem<String>(
                  value: '2m',
                  child: Text(getLocalText.plural("%d minutes", 2))),
              DropdownMenuItem<String>(
                  value: '5m',
                  child: Text(getLocalText.plural("%d minutes", 5))),
            ],
            onChanged: (String? v) {
              if (!_vpnLoaded || v == null) return;
              unawaited(_applyIdleSuspend(v));
            },
          ),
        ),












        dimmedWhenDisabled(
          enabled: _idleSuspendReachableEnabled,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  getLocalText.s("Suspend active-route tunnels"),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  getLocalText.s("Also put tunnels on the active route (pool members, the selected node) to sleep after a long quiet period — e.g. overnight. The first connection after sleep adds ~1 round trip. Keep this at or above the directions' idle timeout (30 min by default). Requires \"Suspend idle tunnels\" to be on."),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: DropdownButtonFormField<String>(
            initialValue: _idleSuspendReachable,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              isDense: true,


              enabled: _idleSuspendReachableEnabled,
            ),
            items: [
              DropdownMenuItem<String>(
                  value: '', child: Text(getLocalText.s("Off"))),
              DropdownMenuItem<String>(
                  value: '5m',
                  child: Text(getLocalText.plural("%d minutes", 5))),
              DropdownMenuItem<String>(
                  value: '15m',
                  child: Text(getLocalText.plural("%d minutes", 15))),
              DropdownMenuItem<String>(
                  value: '30m',
                  child: Text(getLocalText.plural("%d minutes", 30))),
              DropdownMenuItem<String>(
                  value: '1h',
                  child: Text(getLocalText.plural("%d hours", 1))),
            ],


            onChanged: !_idleSuspendReachableEnabled
                ? null
                : (String? v) {
                    if (v == null) return;
                    unawaited(_applyIdleSuspendReachable(v));
                  },
          ),
        ),


        SwitchListTile(
          value: _wgLazyBuild,
          onChanged: !_wgLazyBuildEnabled
              ? null
              : (bool v) => unawaited(_applyWgLazyBuild(v)),
          title: Text(getLocalText.s("Lazy tunnel build")),
          subtitle: Text(getLocalText.s("Build a WireGuard tunnel only on first use instead of at start. Saves memory with many nodes; the first connection to a node takes a moment longer.")),
        ),



        dimmedWhenDisabled(
          enabled: _wgBuildMaxEnabled,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  getLocalText.s("Built tunnels limit"),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  getLocalText.s("Keep at most this many WireGuard tunnels built at once; the rest are torn down and rebuilt on demand. 0 = no limit."),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: DropdownButtonFormField<int>(
            initialValue: const [0, 3, 5, 8, 12].contains(_wgBuildMax)
                ? _wgBuildMax
                : null,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              isDense: true,
              enabled: _wgBuildMaxEnabled,
            ),
            items: [
              DropdownMenuItem<int>(
                  value: 0, child: Text(getLocalText.s("0 (no limit)"))),
              for (final n in const [3, 5, 8, 12])
                DropdownMenuItem<int>(value: n, child: Text(n.toString())),
            ],
            onChanged: !_wgBuildMaxEnabled
                ? null
                : (int? v) {
                    if (v == null) return;
                    unawaited(_applyWgBuildMax(v));
                  },
          ),
        ),
        const Divider(height: 32),
        const TemplateSectionHeader(
          title: 'Optimization',
          description: 'Health checks, memory and VPN lifecycle',
        ),

        SwitchListTile(
          value: _passiveCheck,
          onChanged: (bool v) {
            if (!_vpnLoaded) return;
            unawaited(_applyPassiveCheck(v));
          },
          title: Text(getLocalText.s("Passive health check")),
          subtitle: Text(getLocalText.s("Skip periodic server probes while your own traffic already proves the connection works. Fewer wakeups and less battery; ping numbers refresh less often.")),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                getLocalText.s("Memory limit"),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 2),
              Text(
                getLocalText.s("Caps the VPN core's memory. A cap that is too low keeps the processor busy with garbage collection and heats the phone. Auto sizes the cap to this device's RAM; Off removes the cap but keeps low-memory monitoring. Applies immediately."),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: DropdownButtonFormField<String>(
            initialValue: _memoryLimit,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              DropdownMenuItem<String>(
                  value: MemoryLimitSetting.auto,
                  child: Text(getLocalText.s("Auto (recommended)"))),
              DropdownMenuItem<String>(
                  value: MemoryLimitSetting.off,
                  child: Text(getLocalText.s("Off"))),
              DropdownMenuItem<String>(
                  value: '200', child: Text(getLocalText.s("%d MB", 200))),
              DropdownMenuItem<String>(
                  value: '384', child: Text(getLocalText.s("%d MB", 384))),
              DropdownMenuItem<String>(
                  value: '512', child: Text(getLocalText.s("%d MB", 512))),
              DropdownMenuItem<String>(
                  value: '768', child: Text(getLocalText.s("%d MB", 768))),
            ],
            onChanged: (String? v) {
              if (!_vpnLoaded || v == null) return;
              unawaited(_applyMemoryLimit(v));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                getLocalText.s("Tunnel sleep mode"),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 2),
              Text(
                getLocalText.s("When to pause the tunnel to save battery. Takes effect on next VPN connect."),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        RadioGroup<BackgroundMode>(
          groupValue: _backgroundMode,
          onChanged: (BackgroundMode? m) {
            if (!_vpnLoaded) return;
            unawaited(_applyBackgroundMode(m));
          },
          child: Column(
            children: [
              RadioListTile<BackgroundMode>(
                value: BackgroundMode.never,
                title: Text(getLocalText.s("Never sleep (recommended)")),
                subtitle: Text(getLocalText.s("Tunnel is always active. Best reliability — pushes and long-lived sockets survive. Higher battery use.")),
              ),
              RadioListTile<BackgroundMode>(
                value: BackgroundMode.lazy,
                title: Text(getLocalText.s("Lazy sleep")),
                subtitle: Text(getLocalText.s("Pause only in deep Doze (screen off for a long time + no motion). Balanced.")),
              ),
              RadioListTile<BackgroundMode>(
                value: BackgroundMode.always,
                title: Text(getLocalText.s("Aggressive battery saving")),
                subtitle: Text(getLocalText.s("Pause tunnel whenever screen turns off. Max battery savings, but pushes, incoming calls and background sync stop until unlock.")),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCoreTab(
    BuildContext context,
    WizardTemplate template,
    List<WizardVar> editableVars,
  ) {
    if (editableVars.isEmpty) {
      return Center(child: Text(getLocalText.s("No configurable variables")));
    }
    final sectionDescriptions = {
      for (final s in template.sectionsFor('core')) s.title: s.description,
    };
    final bottomPad = MediaQuery.of(context).padding.bottom + 24;
    return ListView(
      padding: EdgeInsets.fromLTRB(12, 12, 12, bottomPad),
      children: [
        TemplateVarListView(
          vars: editableVars,
          model: _model!,
          sectionDescriptions: sectionDescriptions,
          onChanged: _onVarChanged,
        ),
      ],
    );
  }
}
