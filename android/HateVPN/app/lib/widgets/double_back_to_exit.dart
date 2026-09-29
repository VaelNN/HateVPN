import 'dart:async';

import 'package:flutter/material.dart';

import '../services/l10n/locale_controller.dart';

















class DoubleBackToExit extends StatefulWidget {
  const DoubleBackToExit({
    super.key,
    required this.builder,
    this.window = const Duration(seconds: 2),
  });

  final Widget Function(
    BuildContext context,
    ValueChanged<bool> onDrawerChanged,
  )
  builder;


  final Duration window;

  @override
  State<DoubleBackToExit> createState() => _DoubleBackToExitState();
}

class _DoubleBackToExitState extends State<DoubleBackToExit> {
  bool _drawerOpen = false;
  bool _armed = false;
  Timer? _disarm;

  @override
  void dispose() {
    _disarm?.cancel();
    super.dispose();
  }

  void _onDrawerChanged(bool open) {
    if (open == _drawerOpen || !mounted) return;
    setState(() => _drawerOpen = open);
  }

  void _onBack(bool didPop, Object? _) {

    if (didPop || _drawerOpen) return;
    _disarm?.cancel();
    setState(() => _armed = true);
    _disarm = Timer(widget.window, () {
      if (mounted) setState(() => _armed = false);
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(getLocalText.s("Press back again to exit")),
          duration: widget.window,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: _drawerOpen || _armed,
      onPopInvokedWithResult: _onBack,
      child: widget.builder(context, _onDrawerChanged),
    );
  }
}
