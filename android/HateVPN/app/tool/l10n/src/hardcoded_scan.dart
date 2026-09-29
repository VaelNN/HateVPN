import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import 'sha256.dart';























const Set<String> _displayNamedArgs = {
  'tooltip', 'labelText', 'hintText', 'helperText',
};
const Map<String, Set<String>> _calleeNamed = {
  'SnackBarAction': {'label'},
  'Tab': {'text'},
};
const Map<String, Set<int>> _calleePositional = {
  'Text': {0},
};

final RegExp _letter = RegExp(r'\p{L}', unicode: true);



class DisplayHelper {
  DisplayHelper(this.positional, this.named);
  final Set<int> positional;
  final Set<String> named;
}


class HardcodedSite {
  HardcodedSite(this.file, this.line, this.hash, this.preview);
  final String file;
  final int line;


  final String hash;
  final String preview;
}




String? canonicalLiteral(Expression e) {
  if (e is SimpleStringLiteral) return e.value;
  if (e is AdjacentStrings) {
    final buf = StringBuffer();
    for (final s in e.strings) {
      final part = canonicalLiteral(s);
      if (part == null) return null;
      buf.write(part);
    }
    return buf.toString();
  }
  if (e is StringInterpolation) {
    final buf = StringBuffer();
    for (final el in e.elements) {
      if (el is InterpolationString) {
        buf.write(el.value);
      } else {
        buf.write('{}');
      }
    }
    return buf.toString();
  }
  return null;
}



List<HardcodedSite> scanForHardcodedStrings({
  required String path,
  required String content,
  Map<String, DisplayHelper> helpers = const {},
}) {
  final parsed =
      parseString(content: content, path: path, throwIfDiagnostics: false);
  final sites = <HardcodedSite>[];
  parsed.unit.accept(_ScanVisitor(
      path, parsed.lineInfo, content.split('\n'), helpers, sites));
  return sites;
}

class _ScanVisitor extends RecursiveAstVisitor<void> {
  _ScanVisitor(this.file, this.lineInfo, this.lines, this.helpers, this.sites);

  final String file;
  final LineInfo lineInfo;
  final List<String> lines;
  final Map<String, DisplayHelper> helpers;
  final List<HardcodedSite> sites;
  final Set<int> _seenOffsets = {};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _handleCall(node.methodName.name, node.argumentList);
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {

    final type = node.constructorName.type.toSource();
    _handleCall(type.split('<').first.split('.').last, node.argumentList);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitNamedExpression(NamedExpression node) {
    if (_displayNamedArgs.contains(node.name.label.name)) {
      _check(node.expression);
    }
    super.visitNamedExpression(node);
  }

  void _handleCall(String callee, ArgumentList args) {
    final positional = <int>{
      ...?_calleePositional[callee],
      ...?helpers[callee]?.positional,
    };
    final named = <String>{
      ...?_calleeNamed[callee],
      ...?helpers[callee]?.named,
    };
    if (positional.isEmpty && named.isEmpty) return;

    var idx = 0;
    for (final a in args.arguments) {
      if (a is NamedExpression) {
        if (named.contains(a.name.label.name)) _check(a.expression);
      } else {
        if (positional.contains(idx)) _check(a);
        idx++;
      }
    }
  }

  void _check(Expression e) {



    if (e is ParenthesizedExpression) {
      _check(e.expression);
      return;
    }
    if (e is ConditionalExpression) {
      _check(e.thenExpression);
      _check(e.elseExpression);
      return;
    }
    if (e is SwitchExpression) {
      for (final c in e.cases) {
        _check(c.expression);
      }
      return;
    }
    final text = canonicalLiteral(e);
    if (text == null || text.trim().isEmpty) return;
    if (!_letter.hasMatch(text)) return;
    if (!_seenOffsets.add(e.offset)) return;
    final line = lineInfo.getLocation(e.offset).lineNumber;
    if (_exempt(line)) return;
    final short = text.length > 60 ? '${text.substring(0, 57)}...' : text;
    sites.add(
        HardcodedSite(file, line, sha256Hex(text).substring(0, 12), short));
  }

  bool _exempt(int line) {
    bool has(int i) =>
        i >= 0 && i < lines.length && lines[i].contains('// l10n-exempt');
    return has(line - 1) || has(line - 2);
  }
}
