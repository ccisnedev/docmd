import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:docmd_cli/src/render/cover_filter.dart';

import 'support/parity.dart';

/// Runs the embedded cover filter through real pandoc into [out].
File _render(Directory dir, String markdown, String out) {
  final source = File(p.join(dir.path, 'doc.md'))..writeAsStringSync(markdown);
  File(p.join('test', 'fixtures', 'parity', 'logo.png'))
      .copySync(p.join(dir.path, 'logo.png'));
  final target = File(p.join(dir.path, out));
  final result = Process.runSync('pandoc', [
    source.path,
    '--lua-filter',
    writeCoverFilter(dir).path,
    '--resource-path',
    dir.path,
    '-o',
    target.path,
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return target;
}

String _documentXml(File docx) => utf8.decode(
  ZipDecoder()
      .decodeBytes(docx.readAsBytesSync())
      .findFile('word/document.xml')!
      .content as List<int>,
);

// Metadata is Markdown to pandoc: a backslash keeps the quotes straight, and
// "A < B" is not an HTML tag. Both must survive Typst strings and OpenXML.
const _cover = '---\n'
    r"""title: 'Informe \"final\" #1 & A < B'""" '\n'
    'cover:\n'
    '  logo: logo.png\n'
    '  kind: Tarea\n'
    '  fields:\n'
    '    - Curso: A & B < C\n'
    '---\n\n'
    '# Cuerpo\n\nTexto.\n';

void main() {
  group('cover filter', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('docmd_cover_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('docx: the logo opens the cover, centered, and a page break ends it',
        () {
      final xml = _documentXml(_render(dir, _cover, 'out.docx'));
      final first = RegExp(r'<w:p>.*?</w:p>', dotAll: true).firstMatch(xml)!;
      expect(first[0], contains('w:val="Title"'));
      expect(first[0], contains('<w:drawing>'));
      expect(xml.indexOf('w:type="page"'), lessThan(xml.indexOf('Cuerpo')));
    });

    test('docx: text is escaped, not read as markup', () {
      final text = normalize(docxText(_render(dir, _cover, 'out.docx')));
      expect(text, contains('Informe "final" #1 & A < B'));
      expect(text, contains('CURSO A & B < C'));
    });

    test('typst: the cover is its own unnumbered page and the body starts at 1',
        () {
      final typst = _render(dir, _cover, 'out.typ').readAsStringSync();
      expect(typst, contains('#page(numbering: none'));
      expect(typst, contains('#counter(page).update(1)'));
      expect(typst, contains(r'"Informe \"final\" #1 & A < B"'));
    });

    test('a document without a cover is left alone', () {
      final typst = _render(dir, '# Cuerpo\n', 'out.typ').readAsStringSync();
      expect(typst, isNot(contains('#page(')));
      expect(typst, isNot(contains('counter(page)')));
    });
  }, skip: toolExists('pandoc') ? false : 'needs pandoc on PATH');
}
