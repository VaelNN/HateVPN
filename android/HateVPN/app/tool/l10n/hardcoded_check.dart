import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import 'src/check_common.dart';
import 'src/hardcoded_scan.dart';
import 'src/sha256.dart';
































const String _baselinePath = 'tool/l10n/hardcoded_baseline.json';
const String _helpersPath = 'tool/l10n/l10n_helpers.json';
const String _renderAllowlistPath = 'tool/l10n/render_allowlist.json';



const String _modelsDir = 'lib/models/';

class _RenderAllowlist {
  _RenderAllowlist(this.renderEn);
  final List<String> renderEn;

  static _RenderAllowlist load() {
    final raw = jsonDecode(File(_renderAllowlistPath).readAsStringSync())
        as Map<String, dynamic>;
    return _RenderAllowlist(
      ((raw['renderEn'] as List?) ?? const []).cast<String>(),
    );
  }

  static bool _match(List<String> prefixes, String file) =>
      prefixes.any((p) => p.endsWith('/') ? file.startsWith(p) : file == p);

  bool renderEnAllowed(String file) =>
      file.startsWith(_modelsDir) || _match(renderEn, file);
}

Map<String, DisplayHelper> _loadHelpers() {
  final raw = jsonDecode(File(_helpersPath).readAsStringSync())
      as Map<String, dynamic>;
  final helpers = raw['helpers'] as Map<String, dynamic>;
  return helpers.map((name, cfg) {
    final m = cfg as Map<String, dynamic>;
    return MapEntry(
      name,
      DisplayHelper(
        ((m['positional'] as List?) ?? const []).cast<int>().toSet(),
        ((m['named'] as List?) ?? const []).cast<String>().toSet(),
      ),
    );
  });
}



class _LocalityVisitor extends RecursiveAstVisitor<void> {
  _LocalityVisitor(this.file, this.lineInfo, this.allow, this.r);

  final String file;
  final LineInfo lineInfo;
  final _RenderAllowlist allow;
  final CheckReporter r;

  int _line(AstNode e) => lineInfo.getLocation(e.offset).lineNumber;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'renderEn') {
      if (!allow.renderEnAllowed(file)) {
        r.fail('$file:${_line(node)}: `renderEn(` outside the machine-surface '
            'allowlist (tool/l10n/render_allowlist.json) — English render is '
            'reserved for automation/AppLog/Debug API/notification surfaces');
      }
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {



    if (node.prefix.name == 'GetLocalText' &&
        node.identifier.name == 'en' &&
        !file.startsWith(_modelsDir)) {
      r.fail('$file:${_line(node)}: direct `GetLocalText.en` — go through '
          'renderEn() (only $_modelsDir* may reference the pinned English '
          'renderer directly)');
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {



    final templateFields = <String>[];
    for (final m in node.members) {
      if (m is FieldDeclaration &&
          m.fields.type?.toSource() == 'WizardTemplate?') {
        for (final v in m.fields.variables) {
          templateFields.add(v.name.lexeme);
        }
      }
    }
    if (templateFields.isNotEmpty) {
      for (final m in node.members) {
        if (m is MethodDeclaration && m.name.lexeme == 'initState') {
          final body = m.body.toSource();
          for (final f in templateFields) {
            if (RegExp('$f\\s*=[^=]').hasMatch(body) ||
                body.contains('$f = ')) {
              r.fail('$file:${_line(m)}: `WizardTemplate? $f` assigned in '
                  'initState — move the template fetch to '
                  'didChangeDependencies keyed on Localizations.localeOf '
                  '(survives locale switches)');
            }
          }
        }
      }
    }
    super.visitClassDeclaration(node);
  }
}

Map<String, int> _multiset(Iterable<String> items) {
  final m = <String, int>{};
  for (final i in items) {
    m[i] = (m[i] ?? 0) + 1;
  }
  return m;
}

void main(List<String> args) {
  ensureAppCwd();
  sha256SelfTest();
  final writeBaseline = args.contains('--write-baseline');

  final r = CheckReporter('hardcoded_check', strict: parseStrict(args));

  final helpers = _loadHelpers();
  final renderAllow = _RenderAllowlist.load();
  final files = dartFilesUnder('lib', excludeDirs: ['lib/l10n/gen']);
  final sitesByFile = <String, List<HardcodedSite>>{};
  for (final path in files) {
    final content = File(path).readAsStringSync();

    final sites = scanForHardcodedStrings(
        path: path, content: content, helpers: helpers);

    final parsed =
        parseString(content: content, path: path, throwIfDiagnostics: false);
    parsed.unit.accept(_LocalityVisitor(path, parsed.lineInfo, renderAllow, r));
    if (sites.isNotEmpty) sitesByFile[path] = sites;
  }
  final total =
      sitesByFile.values.fold<int>(0, (a, b) => a + b.length);

  if (writeBaseline) {
    final out = <String, Object?>{
      for (final e in sitesByFile.entries)
        e.key: (e.value.map((s) => s.hash).toList()..sort()),
    };
    File(_baselinePath).writeAsStringSync(canonicalJson(out));
    stdout.writeln('wrote $_baselinePath: $total site(s) in '
        '${sitesByFile.length} file(s)');
  } else {
    final Map<String, dynamic> baselineRaw;
    try {
      baselineRaw = jsonDecode(File(_baselinePath).readAsStringSync())
          as Map<String, dynamic>;
    } catch (e) {
      r.fail('$_baselinePath unreadable: $e — regenerate with --write-baseline');
      exit(r.finish());
    }
    for (final e in sitesByFile.entries) {
      final base = ((baselineRaw[e.key] as List?) ?? const []).cast<String>();
      if (e.value.length <= base.length) continue;
      final remaining = _multiset(base);
      for (final s in e.value) {
        final left = remaining[s.hash] ?? 0;
        if (left > 0) {
          remaining[s.hash] = left - 1;
        } else {
          r.fail('${s.file}:${s.line}: new hardcoded display string '
              '"${s.preview}" (${s.hash}) — migrate to ARB or annotate '
              '// l10n-exempt: <reason>');
        }
      }
      r.fail('${e.key}: literal site count grew '
          '${base.length} -> ${e.value.length}');
    }
  }


  final perDir = <String, int>{};
  for (final e in sitesByFile.entries) {
    final seg = e.key.split('/');
    final dir = seg.length > 2 ? '${seg[0]}/${seg[1]}' : 'lib';
    perDir[dir] = (perDir[dir] ?? 0) + e.value.length;
  }
  stdout.writeln('scanned ${files.length} file(s), '
      '$total literal site(s) in ${sitesByFile.length} file(s)');

  exit(r.finish(extraRows: [
    MapEntry('total sites', '$total'),
    MapEntry('files with sites', '${sitesByFile.length}'),
    for (final d in perDir.keys.toList()..sort())
      MapEntry(d, '${perDir[d]}'),
  ]));
}
