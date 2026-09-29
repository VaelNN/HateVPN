import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/parser_config.dart';
import 'outbound_picker.dart';
import 'var_values_model.dart';
import '../services/l10n/locale_controller.dart';



























class TemplateVarListView extends StatefulWidget {
  const TemplateVarListView({
    super.key,
    required this.vars,
    required this.model,
    required this.onChanged,
    this.sectionDescriptions = const {},
    this.showSectionHeaders = true,
    this.outboundOptions = const [],
    this.dnsServerTags = const [],
  });


  final List<WizardVar> vars;




  final VarValuesModel model;



  final void Function(String name, String value) onChanged;


  final Map<String, String> sectionDescriptions;




  final bool showSectionHeaders;



  final List<OutboundOption> outboundOptions;



  final List<String> dnsServerTags;

  @override
  State<TemplateVarListView> createState() => _TemplateVarListViewState();
}

class _TemplateVarListViewState extends State<TemplateVarListView> {
  late final Map<String, WizardVar> _byName;




  final Set<String> _emptyRequired = {};

  @override
  void initState() {
    super.initState();
    _byName = {for (final v in widget.vars) v.name: v};




    final repaired = <String, String>{};
    for (final v in widget.vars) {
      if (widget.model.get(v.name).isEmpty && _backfillDefaultOnEmpty(v)) {
        widget.model.set(v.name, v.defaultValue);
        repaired[v.name] = v.defaultValue;
      }
    }


    if (repaired.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        repaired.forEach(widget.onChanged);
      });
    }
  }




  bool _backfillDefaultOnEmpty(WizardVar v) =>
      v.required && v.defaultValue.isNotEmpty && v.type != 'secret';

  void _update(String name, String value) {
    final v = _byName[name];





    if (value.isEmpty && v != null && v.required && v.type != 'secret') {
      widget.model.set(name, value, markDirty: false);
      widget.model.unstage(name);
      setState(() => _emptyRequired.add(name));
      return;
    }
    widget.model.set(name, value);
    if (_emptyRequired.contains(name)) {
      setState(() => _emptyRequired.remove(name));
    }
    widget.onChanged(name, value);
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    String lastSection = '';

    for (final v in widget.vars) {
      if (widget.showSectionHeaders &&
          v.section.isNotEmpty &&
          v.section != lastSection) {
        lastSection = v.section;
        if (children.isNotEmpty) children.add(const SizedBox(height: 16));
        children.add(_buildSectionHeader(context, v.section));
      }
      children.add(_buildVarWidget(v));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return TemplateSectionHeader(
      title: title,
      description: widget.sectionDescriptions[title] ?? '',
    );
  }




  Widget _buildVarWidget(WizardVar v) => ValueListenableBuilder<String>(
        valueListenable: widget.model.notifier(v.name),
        builder: (_, value, _) => _buildControl(v, value),
      );

  Widget _buildControl(WizardVar v, String value) {

    if (v.type == 'text_list' && v.options.isNotEmpty) {
      return _LabelledField(
        label: v.title.isNotEmpty ? v.title : v.name,
        tooltip: v.tooltip,
        field: VarMultiSelect(
          key: ValueKey('multi-${v.name}'),
          v: v,
          value: value,
          onChanged: (val) => _update(v.name, val),
        ),
      );
    }
    switch (v.type) {
      case 'bool':
        return SwitchListTile(
          title: Text(v.title.isNotEmpty ? v.title : v.name),
          subtitle: v.tooltip.isNotEmpty
              ? Text(v.tooltip, style: const TextStyle(fontSize: 12))
              : null,
          value: value == 'true',
          onChanged: (val) => _update(v.name, val.toString()),
        );

      case 'enum':

        if (v.optionsOpen) return _buildTextField(v, value);
        return _buildOptionsDropdown(v, value);

      case 'secret':
        return VarTextField(
          key: ValueKey('secret-${v.name}'),
          value: value,
          obscure: true,
          label: v.title.isNotEmpty ? v.title : v.name,
          tooltip: v.tooltip,
          onChanged: (val) => _update(v.name, val),
          trailing: IconButton(
            tooltip: getLocalText.s("Generate random"),
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () {
              final rng = Random.secure();
              final bytes = List.generate(16, (_) => rng.nextInt(256));
              final hex =
                  bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
              _update(v.name, hex);
            },
          ),
        );

      case 'outbound':


        if (widget.outboundOptions.isEmpty) return _buildTextField(v, value);
        return _LabelledField(
          label: v.title.isNotEmpty ? v.title : v.name,
          tooltip: v.tooltip,
          field: OutboundPicker(
            value: value.isNotEmpty ? value : v.defaultValue,
            options: widget.outboundOptions,
            allowReject: false,
            onChanged: (val) => _update(v.name, val),
          ),
        );

      case 'dns_servers':

        if (widget.dnsServerTags.isEmpty) return _buildTextField(v, value);
        final currentTag = value.isNotEmpty ? value : v.defaultValue;
        final tags = widget.dnsServerTags.contains(currentTag)
            ? widget.dnsServerTags
            : [currentTag, ...widget.dnsServerTags];
        return _LabelledField(
          label: v.title.isNotEmpty ? v.title : v.name,
          tooltip: v.tooltip,
          field: DropdownButton<String>(
            isExpanded: true,
            value: currentTag,
            items: tags
                .map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(t, style: const TextStyle(fontSize: 13)),
                    ))
                .toList(),
            onChanged: (val) {
              if (val == null) return;
              _update(v.name, val);
            },
          ),
        );

      default:


        if (v.options.isNotEmpty &&
            !v.optionsOpen &&
            (v.type == 'text' || v.type == 'int')) {
          return _buildOptionsDropdown(v, value);
        }
        return _buildTextField(v, value);
    }
  }




  Widget _buildOptionsDropdown(WizardVar v, String value) {
    final values = v.optionValues;
    final shown = values.contains(value)
        ? value
        : (values.contains(v.defaultValue) ? v.defaultValue : values.first);
    return _LabelledField(
      label: v.title.isNotEmpty ? v.title : v.name,
      tooltip: v.tooltip,
      field: DropdownButton<String>(
        key: ValueKey('options-${v.name}'),
        isExpanded: true,
        value: shown,
        items: v.options
            .map((o) => DropdownMenuItem(
                  value: o.value,
                  child: Text(o.title),
                ))
            .toList(),
        onChanged: (val) {
          if (val == null) return;
          _update(v.name, val);
        },
      ),
    );
  }





  Widget _buildTextField(WizardVar v, String value) {
    final hasSuggestions = v.options.isNotEmpty;
    final isInt = v.type == 'int';
    return VarTextField(
      key: ValueKey('text-${v.name}'),
      value: value,
      width: hasSuggestions ? 220 : 180,
      label: v.title.isNotEmpty ? v.title : v.name,
      tooltip: v.tooltip,
      numeric: isInt,
      errorText: _emptyRequired.contains(v.name) ? 'Required' : null,
      suggestions: v.options.map((o) => o.value).toList(),
      onChanged: (val) => _update(v.name, isInt ? _clampUint16(val) : val),
    );
  }



  static String _clampUint16(String raw) {
    if (raw.isEmpty) return raw;
    final n = int.tryParse(raw);
    if (n == null) return raw;
    return n.clamp(0, 65535).toString();
  }
}





class TemplateSectionHeader extends StatelessWidget {
  const TemplateSectionHeader({
    super.key,
    required this.title,
    this.description = '',
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
          if (description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          const Divider(),
        ],
      ),
    );
  }
}










class VarTextField extends StatefulWidget {
  const VarTextField({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
    this.tooltip = '',
    this.obscure = false,
    this.width = 180,
    this.trailing,
    this.suggestions = const [],
    this.numeric = false,
    this.errorText,
    this.maxLines = 1,
    this.hintText,
  });

  final String value;
  final String label;
  final String tooltip;
  final void Function(String) onChanged;
  final bool obscure;
  final double width;
  final Widget? trailing;
  final List<String> suggestions;


  final bool numeric;



  final String? errorText;



  final int maxLines;


  final String? hintText;

  @override
  State<VarTextField> createState() => _VarTextFieldState();
}

class _VarTextFieldState extends State<VarTextField> {
  late final TextEditingController _ctrl;
  late bool _obscured;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
    _obscured = widget.obscure;
  }

  @override
  void didUpdateWidget(covariant VarTextField old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value && widget.value != _ctrl.text) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _applySuggestion(String v) {
    _ctrl.text = v;
    _ctrl.selection = TextSelection.collapsed(offset: v.length);
    widget.onChanged(v);
  }

  Widget? _buildSuffix() {
    if (widget.obscure) {
      return IconButton(
        icon: Icon(
          _obscured ? Icons.visibility_off : Icons.visibility,
          size: 18,
        ),
        onPressed: () => setState(() => _obscured = !_obscured),
      );
    }
    if (widget.suggestions.isEmpty) return null;
    return PopupMenuButton<String>(
      tooltip: getLocalText.s("Presets"),
      icon: const Icon(Icons.arrow_drop_down),
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      onSelected: _applySuggestion,
      itemBuilder: (ctx) => [
        for (final s in widget.suggestions)
          PopupMenuItem<String>(
            value: s,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: s == _ctrl.text
                      ? const Icon(Icons.check, size: 18)
                      : null,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    s,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _ctrl,
      obscureText: _obscured,
      maxLines: widget.obscure ? 1 : widget.maxLines,
      minLines: 1,
      keyboardType: widget.numeric
          ? TextInputType.number
          : (widget.maxLines > 1 ? TextInputType.multiline : null),
      inputFormatters: widget.numeric
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        hintText: widget.hintText,
        errorText: widget.errorText,
        errorStyle: const TextStyle(fontSize: 11),
        suffixIcon: _buildSuffix(),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 32,
          minHeight: 32,
        ),
      ),
      onChanged: widget.onChanged,
    );



    if (widget.label.isEmpty) return field;
    return _LabelledField(
      label: widget.label,
      tooltip: widget.tooltip,
      field: widget.trailing != null
          ? Row(children: [
              Expanded(child: field),
              widget.trailing!,
            ])
          : field,
    );
  }
}








class VarMultiSelect extends StatelessWidget {
  const VarMultiSelect({
    super.key,
    required this.v,
    required this.value,
    required this.onChanged,
  });

  final WizardVar v;
  final String value;
  final ValueChanged<String> onChanged;

  static List<String> _lines(String s) => s
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    final known = v.optionValues;
    final lines = _lines(value);
    final selected = lines.where(known.contains).toSet();
    final extra = lines.where((l) => !known.contains(l)).toList();

    String compose(Set<String> sel, List<String> own) => [
          for (final o in known)
            if (sel.contains(o)) o,
          if (v.optionsOpen)
            for (final l in own)
              if (!known.contains(l)) l,
        ].join('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final o in v.options)
              FilterChip(
                key: ValueKey('multi-${v.name}-${o.value}'),
                label: Text(o.title, style: const TextStyle(fontSize: 13)),
                selected: selected.contains(o.value),
                onSelected: (on) {
                  final next = {...selected};
                  on ? next.add(o.value) : next.remove(o.value);
                  onChanged(compose(next, extra));
                },
              ),
          ],
        ),
        if (v.optionsOpen) ...[
          const SizedBox(height: 8),
          VarTextField(
            key: ValueKey('multi-own-${v.name}'),
            value: extra.join('\n'),
            label: '',
            maxLines: 4,
            hintText: getLocalText.s("Other values, one per line"),
            onChanged: (raw) => onChanged(compose(selected, _lines(raw))),
          ),
        ],
      ],
    );
  }
}






class _LabelledField extends StatelessWidget {
  const _LabelledField({
    required this.label,
    required this.tooltip,
    required this.field,
  });

  final String label;
  final String tooltip;
  final Widget field;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: theme.textTheme.bodyLarge),
          if (tooltip.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              tooltip,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          field,
        ],
      ),
    );
  }
}
