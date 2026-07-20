import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:docmd_cli/src/ingestion/pdf_backend.dart';
import 'package:docmd_cli/src/package_layout.dart';

/// Exercises the whole pure-Dart PDF path against a real PDF committed at
/// test/fixtures/sample.pdf (a Word/LibreOffice-style PDF with subset fonts and
/// ToUnicode CMaps — the shape the extractor must handle). Unlike the unit tests
/// for the CMap and content-stream logic, this runs dart_pdf_reader end to end.
void main() {
  group('PdfIngestionBackend (real fixture)', () {
    late Directory dir;
    late DocmdPackageLayout layout;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('docmd_pdf_integration_');
      layout = DocmdPackageLayout(p.join(dir.path, 'sample.docmd'))
        ..createSkeleton();
    });

    tearDown(() => dir.deleteSync(recursive: true));

    Future<String> ingestFixture() async {
      final fixture = File(p.join(
        Directory.current.path,
        'test',
        'fixtures',
        'sample.pdf',
      ));
      final source = File(p.join(dir.path, 'sample.pdf'))
        ..writeAsBytesSync(fixture.readAsBytesSync());
      await PdfIngestionBackend()
          .ingest(source: source, format: 'pdf', layout: layout);
      return File(layout.canonicalDocumentPath).readAsStringSync();
    }

    test('recovers the text layer, including accented characters', () async {
      final markdown = await ingestFixture();

      expect(markdown, contains('Quarterly Report'));
      expect(markdown, contains('Section One'));
      expect(markdown, contains('42'));
      expect(markdown, contains('active'));
      // The accent must survive — glyph→Unicode via ToUnicode, decoded as UTF-8.
      expect(markdown, contains('Bogotá'));
      expect(markdown, isNot(contains('BogotÃ')));
    });

    test('marks page provenance without inventing headings', () async {
      final markdown = await ingestFixture();
      expect(markdown, contains('<!-- page 1 -->'));
    });
  });
}
