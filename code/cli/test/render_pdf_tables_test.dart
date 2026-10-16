import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:docmd_cli/modules/render/commands/render_file.dart';
import 'package:docmd_cli/src/ingestion/pdf_backend.dart';
import 'package:docmd_cli/src/package_layout.dart';

import 'support/parity.dart';

/// Text of each page of [pdf], as docmd's own reader splits it.
Future<List<String>> _pages(File pdf, Directory work) async {
  final layout = DocmdPackageLayout(p.join(work.path, 'read-back.docmd'))
    ..createSkeleton();
  await PdfIngestionBackend().ingest(
    source: pdf,
    format: 'pdf',
    layout: layout,
  );
  return File(layout.canonicalDocumentPath)
      .readAsStringSync()
      .split(RegExp(r'<!-- page \d+ -->'))
      .where((page) => page.trim().isNotEmpty)
      .map(normalize)
      .toList();
}

void main() {
  // pandoc's Typst writer wraps a captioned table in a figure, and a Typst
  // figure does not break: a table longer than what is left of the page moved
  // whole to the next one and left the page above it almost empty.
  test(
    'a long captioned table starts where it is and breaks across pages',
    () async {
      final work = Directory.systemTemp.createTempSync('docmd_tables_');
      addTearDown(() => work.deleteSync(recursive: true));
      final rows = [
        for (var i = 1; i <= 45; i++) '| Fila $i | Valor de la fila $i |',
      ];
      final source = File(p.join(work.path, 'doc.md'))
        ..writeAsStringSync(
          [
            '---\nlang: es\n---\n',
            for (var i = 0; i < 12; i++)
              'Un párrafo que ocupa parte de la primera página antes de la tabla, '
                  'con texto suficiente para llenar algunas líneas del ancho.\n',
            ': Tabla larga. {#tbl:larga}\n',
            '| Fila | Valor |\n|---|---|',
            ...rows,
            '',
          ].join('\n'),
        );

      final pdf = await RenderCommand(
        RenderInput(inputPath: source.path, format: 'pdf'),
      ).execute();
      final pages = await _pages(File(pdf.outputPath), work);

      expect(pages.first, contains('Fila 1 Valor de la fila 1'));
      expect(pages.last, contains('Fila 45 Valor de la fila 45'));
      // The header row is repeated on the page the table continues on.
      expect(pages.last, contains('Fila Valor Fila'));
    },
    skip: toolExists('pandoc') && toolExists('typst')
        ? false
        : 'needs pandoc and typst on PATH',
  );
}
