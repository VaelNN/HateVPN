import 'dart:async';

import 'package:flutter/material.dart';

import '../models/dns_ref.dart';
import '../services/ui_helpers.dart';
import '../widgets/outbound_picker.dart';
import 'dns_server_edit/edit_controller.dart';

export 'dns_server_edit/edit_controller.dart' show DnsMemberOption;

export '../services/dns/tailscale_endpoint_options.dart' show TailscaleEndpointOption;
import '../services/dns/tailscale_endpoint_options.dart' show TailscaleEndpointOption;
import 'dns_server_edit/tabs/json_tab.dart';
import 'dns_server_edit/tabs/params_tab.dart';
import 'dns_settings_screen/resolved_server.dart';
import '../services/l10n/locale_controller.dart';










class DnsServerEditScreen extends StatefulWidget {
  const DnsServerEditScreen({
    super.key,
    required this.initialRef,
    this.resolved,
    this.templateWrapper,
    this.canonicalDescription = '',
    this.outboundOptions = const [],
    this.dnsServerTags = const [],
    this.dnsMemberOptions = const [],
    this.tailscaleEndpoints = const [],
    this.existingTags = const {},
  });


  final DnsServerRef initialRef;


  final ResolvedServer? resolved;


  final Map<String, dynamic>? templateWrapper;


  final String canonicalDescription;

  final List<OutboundOption> outboundOptions;
  final List<String> dnsServerTags;



  final List<DnsMemberOption> dnsMemberOptions;


  final List<TailscaleEndpointOption> tailscaleEndpoints;


  final Set<String> existingTags;

  @override
  State<DnsServerEditScreen> createState() => _DnsServerEditScreenState();
}

class _DnsServerEditScreenState extends State<DnsServerEditScreen> {
  late final DnsServerEditController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = DnsServerEditController(
      initialRef: widget.initialRef,
      resolved: widget.resolved,
      templateWrapper: widget.templateWrapper,
      canonicalDescription: widget.canonicalDescription,
      outboundOptions: widget.outboundOptions,
      dnsServerTags: widget.dnsServerTags,
      dnsMemberOptions: widget.dnsMemberOptions,
      tailscaleEndpoints: widget.tailscaleEndpoints,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }



  Future<void> _save() async {
    if (_ctrl.kind == ServerKind.inline) {
      final tag = _ctrl.tagCtrl.text.trim();
      if (tag.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(getLocalText.s("Tag is required"))),
        );
        return;
      }
      if (_ctrl.jsonError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(getLocalText.s("Fix body JSON first: %s", '${_ctrl.jsonError}'))),
        );
        return;
      }



      if (_ctrl.serverMode != null &&
          !_ctrl.isGroup &&
          !_ctrl.isTailscale &&
          _ctrl.addressCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(getLocalText.s("Server address is required"))),
        );
        return;
      }


      if (_ctrl.isTailscale && _ctrl.tailscaleEndpoint.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(getLocalText.s("Tailscale node is required"))),
        );
        return;
      }


      if (!_ctrl.isNew &&
          tag != (widget.resolved?.tag ?? '') &&
          widget.existingTags.contains(tag)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(getLocalText.s("Tag \"%s\" is already in use", tag))),
        );
        return;
      }


      if (_ctrl.isNew && widget.existingTags.contains(tag)) {
        final replace = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(getLocalText.s("Tag \"%s\" exists", tag)),
            content: Text(getLocalText.s("Replace the existing server with this one?")),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(getLocalText.s("Cancel")),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(getLocalText.s("Replace")),
              ),
            ],
          ),
        );
        if (replace != true || !mounted) return;
      }
    }
    if (!mounted) return;
    Navigator.pop(context, DnsServerEditResult.saved(_ctrl.snapshot()));
  }

  Future<void> _delete() async {
    final tag = widget.resolved?.tag ?? '';
    final confirmed = await showDeleteConfirmDialog(
      context,
      title: getLocalText.s("Delete DNS server?"),
      message: getLocalText.s("Remove \"%s\" permanently?", tag),
    );
    if (confirmed == true && mounted) {
      Navigator.pop(context, DnsServerEditResult.deleted());
    }
  }



  Future<void> _resetToCanonical() async {
    final overrides = _ctrl.overrides;
    final resolved = widget.resolved;

    if (overrides == null || overrides == ServerKind.inline || resolved == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(getLocalText.s("Reset to default?")),
        content: Text(getLocalText.s("Discard the override and restore the %1\$s definition of \"%2\$s\"?", overrides.name, resolved.tag)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(getLocalText.s("Cancel")),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(getLocalText.s("Reset")),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.pop(
      context,
      DnsServerEditResult.saved(overrides == ServerKind.preset
          ? DnsServerPreset(
              enabled: _ctrl.enabled,
              tag: resolved.tag,
              presetId: resolved.presetId)
          : DnsServerTemplate(enabled: _ctrl.enabled, tag: resolved.tag)),
    );
  }

  Future<void> _handleBack() async {
    if (!_ctrl.isDirty()) {
      Navigator.pop(context);
      return;
    }
    final action = await showUnsavedChangesDialog(context);
    if (!mounted) return;
    if (action == 'save') {
      unawaited(_save());
    } else if (action == 'discard') {
      Navigator.pop(context);
    }

  }



  @override
  Widget build(BuildContext context) {
    final canDelete = !_ctrl.isNew && _ctrl.isUserOnly && !_ctrl.locked;
    final canReset = !_ctrl.isNew && _ctrl.overrides != null;

    return DnsServerEditScope(
      notifier: _ctrl,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          unawaited(_handleBack());
        },
        child: DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(_ctrl.isNew
                  ? getLocalText.s("Add DNS Server")
                  : getLocalText.s("Edit DNS Server")),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _handleBack,
              ),
              actions: [
                if (canReset)
                  IconButton(
                    tooltip: getLocalText.s("Reset to default"),
                    icon: const Icon(Icons.restart_alt),
                    onPressed: _resetToCanonical,
                  ),
                if (canDelete)
                  IconButton(
                    tooltip: getLocalText.s("Delete server"),
                    icon: Icon(Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error),
                    onPressed: _delete,
                  ),
                _SaveIconButton(controller: _ctrl, onPressed: _save),
              ],
              bottom: TabBar(
                tabs: [
                  Tab(text: getLocalText.s("Params")),
                  Tab(text: getLocalText.s("JSON")),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                DnsServerParamsTab(onSave: _save),
                const DnsServerJsonTab(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}



class _SaveIconButton extends StatelessWidget {
  const _SaveIconButton({required this.controller, required this.onPressed});

  final DnsServerEditController controller;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (ctx, _) {
        final dirty = controller.isDirty();
        return IconButton(
          tooltip: getLocalText.s("Save"),
          icon: Icon(Icons.save,
              color: dirty ? Theme.of(ctx).colorScheme.primary : null),
          onPressed: onPressed,
        );
      },
    );
  }
}


class DnsServerEditResult {
  const DnsServerEditResult._({this.saved, this.wasDeleted = false});


  final DnsServerRef? saved;
  final bool wasDeleted;

  factory DnsServerEditResult.saved(DnsServerRef ref) =>
      DnsServerEditResult._(saved: ref);
  factory DnsServerEditResult.deleted() =>
      const DnsServerEditResult._(wasDeleted: true);
}



Future<DnsServerEditResult?> openDnsServerEditor(
  BuildContext context, {
  required DnsServerRef initialRef,
  ResolvedServer? resolved,
  Map<String, dynamic>? templateWrapper,
  String canonicalDescription = '',
  List<OutboundOption> outboundOptions = const [],
  List<String> dnsServerTags = const [],
  List<DnsMemberOption> dnsMemberOptions = const [],
  List<TailscaleEndpointOption> tailscaleEndpoints = const [],
  Set<String> existingTags = const {},
}) {
  return Navigator.push<DnsServerEditResult>(
    context,
    MaterialPageRoute(
      builder: (_) => DnsServerEditScreen(
        initialRef: initialRef,
        resolved: resolved,
        templateWrapper: templateWrapper,
        canonicalDescription: canonicalDescription,
        outboundOptions: outboundOptions,
        dnsServerTags: dnsServerTags,
        dnsMemberOptions: dnsMemberOptions,
        tailscaleEndpoints: tailscaleEndpoints,
        existingTags: existingTags,
      ),
    ),
  );
}
