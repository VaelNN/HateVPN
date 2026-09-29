import 'package:flutter/material.dart';

import '../../services/template_loader.dart';













class SpecialNodeDisplay {
  const SpecialNodeDisplay({required this.label, required this.icon});

  final String label;
  final IconData icon;
}



String? _roleForOutboundType(String? outboundType) {
  switch (outboundType) {
    case 'urltest':
      return 'auto';
    case 'direct':
      return 'direct';
    case 'block':
      return 'block';
    default:
      return null;
  }
}







SpecialNodeDisplay? specialNodeDisplayForType(String? outboundType) {
  final role = _roleForOutboundType(outboundType);
  if (role == null) return null;



  final title = TemplateLoader.cachedOrNull()?.groupTemplates.magicNodes[role]
      ?.title;
  switch (role) {
    case 'direct':
      return SpecialNodeDisplay(
          label: _orFallback(title, 'Direct'), icon: Icons.public);
    case 'auto':

      return SpecialNodeDisplay(
          label: _orFallback(title, 'Auto'), icon: Icons.auto_awesome);
    case 'block':
      return SpecialNodeDisplay(
          label: _orFallback(title, 'Block'), icon: Icons.block);
    default:
      return null;
  }
}

String _orFallback(String? title, String fallback) =>
    (title == null || title.isEmpty) ? fallback : title;
