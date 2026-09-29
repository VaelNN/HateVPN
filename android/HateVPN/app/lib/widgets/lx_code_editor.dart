import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

import '../services/l10n/locale_controller.dart';












class LxCodeEditor extends StatefulWidget {
  const LxCodeEditor({
    super.key,
    required this.controller,
    this.hint,
    this.fontSize = 12,
    this.readOnly = false,
    this.showLineNumbers = false,
    this.wordWrap = true,
    this.language,
    this.autofocus,
  });

  final CodeLineEditingController controller;
  final String? hint;
  final double fontSize;
  final bool readOnly;
  final bool showLineNumbers;
  final bool wordWrap;





  final LxCodeLanguage? language;




  final bool? autofocus;

  @override
  State<LxCodeEditor> createState() => _LxCodeEditorState();
}


enum LxCodeLanguage { json }

CodeHighlightTheme _highlightTheme(LxCodeLanguage language, Brightness b) {
  final base = b == Brightness.dark ? atomOneDarkTheme : atomOneLightTheme;
  final theme = Map<String, TextStyle>.of(base)..remove('root');
  final mode = switch (language) {
    LxCodeLanguage.json => CodeHighlightThemeMode(mode: langJson),
  };
  return CodeHighlightTheme(
    languages: {language.name: mode},
    theme: theme,
  );
}

class _LxCodeEditorState extends State<LxCodeEditor> {




  late final LxSelectionToolbarController _toolbar;






  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _toolbar = LxSelectionToolbarController();
    _focusNode = FocusNode(debugLabel: 'LxCodeEditor');
    widget.controller.addListener(_onSelectionChanged);
  }

  @override
  void didUpdateWidget(LxCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onSelectionChanged);
      widget.controller.addListener(_onSelectionChanged);
      _toolbar.hide(context);
    }
  }









  void _onSelectionChanged() {
    if (widget.controller.selection.isCollapsed && _toolbar.isShown) {
      _toolbar.hide(context);
    }
  }



  @override
  void deactivate() {
    _toolbar.hide(context);
    super.deactivate();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSelectionChanged);
    _toolbar.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;








    return CodeEditorTapRegion(
      onTapOutside: (_) => _toolbar.hide(context),
      child: CodeEditor(
        controller: widget.controller,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        readOnly: widget.readOnly,
        wordWrap: widget.wordWrap,
        hint: widget.hint,
        padding: const EdgeInsets.all(12),
        border: Border.all(color: cs.outline),
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        style: CodeEditorStyle(
          fontSize: widget.fontSize,
          fontFamily: 'monospace',
          textColor: cs.onSurface,
          hintTextColor: cs.onSurfaceVariant,
          codeTheme: widget.language == null
              ? null
              : _highlightTheme(widget.language!, Theme.of(context).brightness),
        ),
        toolbarController: _toolbar,
        indicatorBuilder: widget.showLineNumbers
            ? (context, editingController, chunkController, notifier) =>
                DefaultCodeLineNumber(
                  controller: editingController,
                  notifier: notifier,
                )
            : null,
      ),
    );
  }
}
































class LxSelectionToolbarController implements SelectionToolbarController {
  LxSelectionToolbarController();

  OverlayEntry? _entry;
  bool _disposed = false;


  bool get isShown => _entry != null;

  @override
  void hide(BuildContext context) {



    final entry = _entry;
    _entry = null;
    if (entry != null && entry.mounted) {
      entry.remove();
    }
  }



  void dispose() {
    final entry = _entry;
    _entry = null;
    _disposed = true;
    if (entry != null && entry.mounted) {
      entry.remove();
    }
  }

  @override
  void show({
    required BuildContext context,
    required CodeLineEditingController controller,
    required TextSelectionToolbarAnchors anchors,
    Rect? renderRect,
    required LayerLink layerLink,
    required ValueNotifier<bool> visibility,
  }) {






    hide(context);
    if (_disposed) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;



    final origin = renderRect?.topLeft ?? Offset.zero;
    final entry = OverlayEntry(
      builder: (_) => _LxToolbarOverlay(
        visibility: visibility,
        layerLink: layerLink,
        offset: anchors.primaryAnchor - origin,
        items: [
          _LxToolbarItem(getLocalText.s("Cut"), controller.cut),
          _LxToolbarItem(getLocalText.s("Copy"), controller.copy),
          _LxToolbarItem(getLocalText.s("Paste"), controller.paste),
          _LxToolbarItem(getLocalText.s("Select all"), controller.selectAll),
        ],
        onDismiss: () => hide(context),
      ),
    );
    overlay.insert(entry);
    _entry = entry;
  }
}


class _LxToolbarItem {
  const _LxToolbarItem(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;
}




class _LxToolbarOverlay extends StatelessWidget {
  const _LxToolbarOverlay({
    required this.visibility,
    required this.layerLink,
    required this.offset,
    required this.items,
    required this.onDismiss,
  });

  final ValueListenable<bool> visibility;
  final LayerLink layerLink;
  final Offset offset;
  final List<_LxToolbarItem> items;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return CodeEditorTapRegion(
      child: ValueListenableBuilder<bool>(
        valueListenable: visibility,
        builder: (context, visible, child) =>
            visible ? child! : const SizedBox.shrink(),
        child: CompositedTransformFollower(
          link: layerLink,
          showWhenUnlinked: false,
          offset: offset,
          child: _menu(context),
        ),
      ),
    );
  }

  Widget _menu(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        color: cs.surfaceContainerHighest,
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items)
              TextButton(
                onPressed: () {


                  item.onTap();
                  onDismiss();
                },
                child: Text(item.label,
                    style: TextStyle(fontSize: 13, color: cs.onSurface)),
              ),
          ],
        ),
      ),
    );
  }
}








class LxJsonView extends StatefulWidget {
  const LxJsonView({
    super.key,
    required this.text,
    this.height,
    this.fontSize = 12,
    this.showLineNumbers = false,
  });

  final String text;
  final double? height;
  final double fontSize;
  final bool showLineNumbers;

  @override
  State<LxJsonView> createState() => _LxJsonViewState();
}

class _LxJsonViewState extends State<LxJsonView> {
  late CodeLineEditingController _ctrl =
      CodeLineEditingController.fromText(widget.text);

  @override
  void didUpdateWidget(covariant LxJsonView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _ctrl.dispose();
      _ctrl = CodeLineEditingController.fromText(widget.text);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editor = LxCodeEditor(
      controller: _ctrl,
      readOnly: true,
      autofocus: false,
      fontSize: widget.fontSize,
      showLineNumbers: widget.showLineNumbers,
      language: LxCodeLanguage.json,
    );
    final h = widget.height;
    return h == null ? editor : SizedBox(height: h, child: editor);
  }
}
