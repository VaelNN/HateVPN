import 'package:flutter/material.dart';

import '../../models/direction.dart';
import '../../services/l10n/locale_controller.dart';












class NewDirectionRequest {
  const NewDirectionRequest({required this.tag, required this.label});


  final String tag;



  final String label;
}





Future<NewDirectionRequest?> showNewDirectionDialog(
  BuildContext context, {
  required List<String> existingTags,
}) {
  return showDialog<NewDirectionRequest>(
    context: context,
    builder: (ctx) => _NewDirectionDialog(existingTags: existingTags),
  );
}

class _NewDirectionDialog extends StatefulWidget {
  const _NewDirectionDialog({required this.existingTags});

  final List<String> existingTags;

  @override
  State<_NewDirectionDialog> createState() => _NewDirectionDialogState();
}

class _NewDirectionDialogState extends State<_NewDirectionDialog> {
  late final TextEditingController _tagCtrl;
  late final TextEditingController _labelCtrl;

  @override
  void initState() {
    super.initState();
    _tagCtrl = TextEditingController(text: nextDirectionTag(widget.existingTags))
      ..addListener(_onChange);
    _labelCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _tagCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  void _onChange() => setState(() {});


  String? _tagError() {
    final code = directionTagConflict(_tagCtrl.text, widget.existingTags);
    return switch (code) {
      null => null,
      'empty' => getLocalText.s("Tag cannot be empty"),
      'reserved' => getLocalText.s("This tag is reserved by the config"),
      'duplicate' => getLocalText.s("A direction with this tag already exists"),
      _ => getLocalText.s("This tag collides with an auto twin (<tag>-auto)"),
    };
  }

  @override
  Widget build(BuildContext context) {
    final error = _tagError();
    return AlertDialog(
      title: Text(getLocalText.s("New direction")),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _tagCtrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: getLocalText.s("Tag"),
              helperText: getLocalText.s("System id, cannot be changed later"),
              helperMaxLines: 2,
              errorText: error,
              errorMaxLines: 2,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _labelCtrl,
            decoration: InputDecoration(
              labelText: getLocalText.s("Title"),
              hintText: getLocalText.s("optional — defaults to the tag"),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(getLocalText.s("Cancel")),
        ),
        TextButton(
          onPressed: error != null
              ? null
              : () => Navigator.pop(
                    context,
                    NewDirectionRequest(
                      tag: _tagCtrl.text.trim(),
                      label: _labelCtrl.text.trim(),
                    ),
                  ),
          child: Text(getLocalText.s("Create")),
        ),
      ],
    );
  }
}
