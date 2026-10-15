import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'package:docmd_cli/modules/render/commands/render_file.dart';
import 'package:docmd_cli/src/ingestion/pdf_backend.dart';
import 'package:docmd_cli/src/package_layout.dart';

/// The semantic parity oracle of ADR 0003. One Markdown source is rendered to
/// docx and to pdf (through Typst) with docmd's own `render`, and each output
/// is read back as plain text — the docx from its XML, the pdf with docmd's own
/// PDF reader — so a test can require the same facts of both.
class ParityRender {
  /// One paragraph per line, whitespace collapsed.
  final String docx;
  final String pdf;

  ParityRender(this.docx, this.pdf);

  static Future<ParityRender> of(Directory fixture, Directory work) async {
    for (final entity in fixture.listSync()) {
      if (entity is File) {
        entity.copySync(p.join(work.path, p.basename(entity.path)));
      }
    }
    final source = p.join(work.path, 'document.md');

    final docx = await RenderCommand(
      RenderInput(inputPath: source, format: 'docx'),
    ).execute();
    final pdf = await RenderCommand(
      RenderInput(inputPath: source, format: 'pdf'),
    ).execute();

    return ParityRender(
      docxText(File(docx.outputPath)),
      await pdfText(File(pdf.outputPath), work),
    );
  }

  /// Whether [fact] appears in both outputs, as a list of the ones missing it.
  List<String> missing(String fact) => [
    if (!normalize(docx).contains(normalize(fact))) 'docx',
    if (!normalize(pdf).contains(normalize(fact))) 'pdf',
  ];
}

/// Paragraph texts of a docx body, one per line.
String docxText(File docx) {
  final archive = ZipDecoder().decodeBytes(docx.readAsBytesSync());
  final xml = XmlDocument.parse(
    utf8.decode(archive.findFile('word/document.xml')!.content as List<int>),
  );
  return xml
      .findAllElements('w:p')
      .map((paragraph) => paragraph.findAllElements('w:t').map((t) => t.innerText).join())
      .where((text) => text.trim().isNotEmpty)
      .join('\n');
}

/// Text of a pdf as docmd's own importer reads it, page markers removed.
Future<String> pdfText(File pdf, Directory work) async {
  final layout = DocmdPackageLayout(p.join(work.path, 'read-back.docmd'))
    ..createSkeleton();
  await PdfIngestionBackend().ingest(
    source: pdf,
    format: 'pdf',
    layout: layout,
  );
  return File(layout.canonicalDocumentPath)
      .readAsStringSync()
      .replaceAll(RegExp(r'<!--.*?-->'), '');
}

/// Collapses whitespace (line breaks, runs placed apart, non-breaking and
/// zero-width spaces) so a fact is matched on its words, not on layout.
String normalize(String text) => text
    .replaceAll(RegExp('[   ]'), ' ')
    .replaceAll(RegExp('[​⁠­]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

bool toolExists(String executable) {
  final lookup = Platform.isWindows ? 'where' : 'which';
  return Process.runSync(lookup, [executable]).exitCode == 0;
}
