import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:docmd_cli/src/render/crossref_filter.dart';

import 'support/parity.dart';

/// Runs the embedded filter through real pandoc and returns its output.
String _render(Directory dir, String markdown, {String to = 'html'}) {
  final source = File(p.join(dir.path, 'doc.md'))..writeAsStringSync(markdown);
  final filter = writeCrossrefFilter(dir);
  final result = Process.runSync('pandoc', [
    source.path,
    '--lua-filter',
    filter.path,
    '-t',
    to,
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return '${result.stdout}';
}

/// Visible text of the HTML rendering.
String _text(Directory dir, String markdown) =>
    normalize(_render(dir, markdown).replaceAll(RegExp(r'<[^>]*>'), ' '))
        .replaceAll(' .', '.')
        .replaceAll(' ,', ',');

void main() {
  group('crossref filter', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('docmd_crossref_'));
    tearDown(() => dir.deleteSync(recursive: true));

    const spanish = '---\nlang: es-PE\n---\n\n'
        'Ver @fig:a, @tbl:t y @fig:b.\n\n'
        '![Uno.](a.png){#fig:a}\n\n'
        ': Conceptos. {#tbl:t}\n\n'
        '| A | B |\n|---|---|\n| 1 | 2 |\n\n'
        '![Dos.](b.png){#fig:b}\n';

    test('numbers figure and table captions in document order', () {
      final text = _text(dir, spanish);
      expect(text, contains('Figura 1: Uno.'));
      expect(text, contains('Tabla 1: Conceptos.'));
      expect(text, contains('Figura 2: Dos.'));
    });

    test('resolves @fig and @tbl references to the same numbers', () {
      final text = _text(dir, spanish);
      expect(text, contains('Ver Figura 1, Tabla 1 y Figura 2.'));
      expect(text, isNot(contains('fig:')));
      expect(text, isNot(contains('tbl:')));
    });

    test('names them in English unless the document is in Spanish', () {
      final text = _text(dir, spanish.replaceFirst('es-PE', 'en'));
      expect(text, contains('Figure 1: Uno.'));
      expect(text, contains('Table 1: Conceptos.'));
      expect(text, contains('Ver Figure 1, Table 1 y Figure 2.'));
    });

    // An unresolved @fig:x used to reach Typst as a link to a missing label,
    // which aborted the whole PDF.
    test('marks an unknown reference instead of passing it on', () {
      final text = normalize(_render(dir, 'Ver @fig:nope.\n'));
      expect(text, contains('Ver ??.'));
    });

    test('leaves bibliographic citations to citeproc', () {
      final native = _render(dir, 'Contar [@rosen2019].\n', to: 'native');
      expect(native, contains('citationId = "rosen2019"'));
    });

    // Typst would add its own "Figura 1:" in front of the one the filter
    // writes; the filter owns the numbering in every format.
    test('turns Typst figure numbering off', () {
      final typst = _render(dir, spanish, to: 'typst');
      expect(typst, contains('#set figure(numbering: none)'));
      expect(_render(dir, spanish, to: 'markdown'),
          isNot(contains('numbering')));
    });
  }, skip: toolExists('pandoc') ? false : 'needs pandoc on PATH');
}
