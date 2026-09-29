import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/home_controller.dart';
import '../../controllers/subscription_controller.dart';
import '../../models/home_state.dart';
import '../../models/node_spec.dart';
import '../../models/template_vars.dart';
import '../../services/contract/body_sanitizer.dart'
    show carriesPrivateKeyByRegistry;
import '../../services/tag_resolver.dart';
import '../outbound_view_screen.dart';
import '../../services/l10n/locale_controller.dart';
import '../../vpn/cc_channel.dart' show CcEndpointState;








void _showTagMissing(BuildContext context, String tag) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(getLocalText.s("Not found: %s", tag))),
  );
}



void viewOutboundJson(
  BuildContext context,
  String tag,
  HomeState state, {
  required SubscriptionController subController,
  required HomeController homeController,
  bool openDependents = false,
  bool openNetwork = false,
}) {


  if (state.configRaw.isEmpty && state.runningConfigRaw == null) {
    _showTagMissing(context, tag);
    return;
  }



  final intro = state.activeModel;
  final chain = intro.outboundChain(tag);
  if (chain.isEmpty) {
    _showTagMissing(context, tag);
    return;
  }

  final payload = chain.length == 1 ? chain.first : chain;
  final json = const JsonEncoder.withIndent('  ').convert(payload);
  final detourCount = chain.length - 1;
  Navigator.push(context, MaterialPageRoute(
    builder: (_) => OutboundViewScreen(
      tag: tag,
      kind: intro.kindOf(tag),
      json: json,
      detourCount: detourCount,
      config: intro,
      subController: subController,
      homeController: homeController,
      openDependents: openDependents,
      openNetwork: openNetwork,

      onCopy: (mode) => copyNodeJson(context, tag, state, mode),
    ),
  ));
}

void copyNodeJson(
    BuildContext context, String tag, HomeState state, String mode) {
  if (state.configRaw.isEmpty && state.runningConfigRaw == null) {
    _showTagMissing(context, tag);
    return;
  }


  final intro = state.activeModel;
  final Map<String, dynamic>? server = intro.rawOf(tag);
  Map<String, dynamic>? detour;
  if (server != null) {
    final detourTag = intro.detourOf(tag);
    if (detourTag != null) detour = intro.rawOf(detourTag);
  }



  if (server == null) {
    _showTagMissing(context, tag);
    return;
  }

  Object toCopy;
  String label;
  switch (mode) {
    case 'detour':
      if (detour == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(getLocalText.s("No detour for this node"))),
          );
        }
        return;
      }
      toCopy = Map<String, dynamic>.from(detour)..remove('detour');
      label = 'Detour copied';
    case 'both':


      final chain = intro.outboundChain(tag);
      final n = chain.length - 1;
      if (n <= 0) {
        toCopy = Map<String, dynamic>.from(server)..remove('detour');
        label = 'Server copied';
      } else {
        toCopy = [
          for (final m in chain) Map<String, dynamic>.from(m)..remove('detour'),
        ];
        label = 'Server + $n detour${n > 1 ? "s" : ""} copied';
      }
    default:
      toCopy = Map<String, dynamic>.from(server)..remove('detour');
      label = 'Server copied';
  }

  final json = const JsonEncoder.withIndent('  ').convert(toCopy);
  Clipboard.setData(ClipboardData(text: json));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label)));
  }
}





NodeSpec? _findNodeByDisplayTag(
    String displayTag, SubscriptionController subController) {
  for (final e in subController.entries) {
    final base = TagResolver.stripPrefix(displayTag, e.tagPrefix);
    for (final n in e.list.nodes) {
      if (n.tag == base) return n;



      for (var hop = n.chained; hop != null; hop = hop.chained) {
        if (hop.tag == base) return hop;
      }
    }
  }
  return null;
}



Future<bool> _confirmPrivateKeyInLink(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(getLocalText.s("Link contains a private key")),
      content: Text(getLocalText.s(
          "Anyone who gets this link can use the key. Copy it only to move "
          "the node to your own device.")),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(getLocalText.s("Cancel")),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(getLocalText.s("Copy anyway")),
        ),
      ],
    ),
  );
  return ok ?? false;
}

Future<void> copyNodeUri(BuildContext context, String tag,
    SubscriptionController subController) async {
  final node = _findNodeByDisplayTag(tag, subController);
  if (node == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(getLocalText.s("No source URI for this node"))),
      );
    }
    return;
  }









  if (carriesPrivateKeyByRegistry(node.emit(TemplateVars.empty).map)) {
    if (!context.mounted) return;
    final ok = await _confirmPrivateKeyInLink(context);
    if (!ok) return;
  }
  final uri = node.toUri();
  if (uri.isEmpty) return;
  await Clipboard.setData(ClipboardData(text: uri));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(getLocalText.s("URI copied"))),
    );
  }
}




Future<void> toggleEndpoint(
    BuildContext context, HomeController controller, String tag) async {
  final enable =
      controller.state.endpointStates[tag] == CcEndpointState.disabled;
  final code = await controller.setEndpointEnabled(tag, enable);
  if (code == null || !context.mounted) return;
  final text = switch (code) {
    'not_found' => getLocalText.s("The running config has no node %s.", tag),
    'invalid_argument' =>
      getLocalText.s("Only WireGuard and AmneziaWG nodes can be turned off."),
    'failed_precondition' =>
      getLocalText.s("VPN is not running or is restarting. Try again."),
    'unavailable' => getLocalText.s(
        "The node did not wake up. The next connection through it will retry."),
    _ => enable
        ? getLocalText.s("Could not turn the node on.")
        : getLocalText.s("Could not turn the node off."),
  };
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
