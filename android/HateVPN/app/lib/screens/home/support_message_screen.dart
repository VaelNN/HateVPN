import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/l10n/locale_controller.dart';
import '../../services/support/support_message.dart';
import '../../services/support/support_nav.dart';
import '../../services/url_launcher.dart' as ul;
















class SupportMessageScreen extends StatefulWidget {
  const SupportMessageScreen({
    super.key,
    required this.feed,
    required this.message,
    required this.buildScreen,
    this.dryRun = false,
  });

  final SupportFeed feed;
  final SupportMessage message;



  final Widget? Function(SupportLinkAction action) buildScreen;



  final bool dryRun;

  @override
  State<SupportMessageScreen> createState() => _SupportMessageScreenState();
}

class _SupportMessageScreenState extends State<SupportMessageScreen> {
  Timer? _readTimer;
  late int _readLeft = widget.message.readDelaySeconds;

  @override
  void initState() {
    super.initState();
    if (_readLeft > 0) {
      _readTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        setState(() => _readLeft--);
        if (_readLeft <= 0) t.cancel();
      });
    }
  }

  @override
  void dispose() {
    _readTimer?.cancel();
    super.dispose();
  }

  Future<void> _gotIt() async {
    Navigator.of(context).pop();
    if (!widget.dryRun) {
      await SupportMessageService.I.markRead(widget.message);
    }
  }

  Future<void> _later() async {
    Navigator.of(context).pop();
    if (!widget.dryRun) {
      await SupportMessageService.I.snooze(widget.feed);
    }
  }


  void _openInternal(SupportLinkSpec spec, Widget target) {
    if (spec.markRead && !widget.dryRun) {
      unawaited(SupportMessageService.I.markRead(widget.message));
    }
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute<void>(builder: (_) => target));
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.message.contentFor(LocaleController.I.effectiveTag);


    final c = raw.expandLinks();
    final theme = Theme.of(context);


    final buttons = <Widget>[];
    for (final spec in c.links) {
      final action = SupportLinkAction.parse(spec.url);
      if (action == null) {
        buttons.add(FilledButton.tonal(
          onPressed: () => ul.UrlLauncher.open(spec.url),
          child: Text(spec.label),
        ));
        continue;
      }
      if (!isResolvableSupportAction(action)) continue;

      if (isInPlaceSupportAction(action)) {
        buttons.add(FilledButton.tonal(
          onPressed: () => unawaited(
              SharePlus.instance.share(ShareParams(text: action.payload))),
          child: Text(spec.label),
        ));
        continue;
      }
      final target = widget.buildScreen(action);
      if (target == null) continue;
      buttons.add(FilledButton.tonal(
        onPressed: () => _openInternal(spec, target),
        child: Text(spec.label),
      ));
    }

    return Scaffold(
      appBar: AppBar(


        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Text(c.title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 16),
            Text(c.message, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 28),
            for (final b in buttons) ...[b, const SizedBox(height: 10)],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _later,
                child: Text(getLocalText.s("Later")),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _readLeft > 0 ? null : _gotIt,
                child: Text(_readLeft > 0
                    ? getLocalText.s("Got it (%d)", _readLeft)
                    : getLocalText.s("Got it")),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
