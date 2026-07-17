import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:docmd_cli/src/ingestion/pptx_backend.dart';
import 'package:docmd_cli/src/package_layout.dart';

const _relNs = 'http://schemas.openxmlformats.org/package/2006/relationships';
const _slideRelType =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide';
const _imageRelType =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/image';

/// One shape on a slide, in document order.
sealed class Shape {
  const Shape();
}

class TextShape extends Shape {
  final List<String> paragraphs;
  const TextShape(this.paragraphs);
}

class PictureShape extends Shape {
  /// Media file name, e.g. `image1.png`.
  final String media;
  const PictureShape(this.media);
}

class SlideSpec {
  /// Part name inside the archive, e.g. `slide2.xml`.
  final String fileName;
  final List<Shape> shapes;
  const SlideSpec(this.fileName, this.shapes);
}

/// Builds a minimal but structurally real .pptx.
///
/// [slidesInPresentationOrder] is the running order; each entry's `fileName`
/// decides where it lives in the archive, so the two can be made to disagree —
/// which is exactly what real decks do once slides get reordered.
File buildPptx(String path, List<SlideSpec> slidesInPresentationOrder) {
  final archive = Archive();

  void addFile(String name, String content) => archive.addFile(
        ArchiveFile.bytes(name, utf8.encode(content)),
      );

  final sldIds = StringBuffer();
  final presRels = StringBuffer();
  for (var i = 0; i < slidesInPresentationOrder.length; i++) {
    final relId = 'rId${i + 2}';
    sldIds.write('<p:sldId id="${256 + i}" r:id="$relId"/>');
    presRels.write(
      '<Relationship Id="$relId" Type="$_slideRelType" '
      'Target="slides/${slidesInPresentationOrder[i].fileName}"/>',
    );
  }

  addFile(
    'ppt/presentation.xml',
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<p:presentation '
    'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
    '<p:sldIdLst>$sldIds</p:sldIdLst></p:presentation>',
  );
  addFile(
    'ppt/_rels/presentation.xml.rels',
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<Relationships xmlns="$_relNs">$presRels</Relationships>',
  );

  for (final slide in slidesInPresentationOrder) {
    final shapes = StringBuffer();
    final slideRels = StringBuffer();
    var imageCount = 0;

    for (final shape in slide.shapes) {
      switch (shape) {
        case TextShape(:final paragraphs):
          final body = paragraphs
              .map((text) => '<a:p><a:r><a:t>$text</a:t></a:r></a:p>')
              .join();
          shapes.write('<p:sp><p:txBody>$body</p:txBody></p:sp>');
        case PictureShape(:final media):
          imageCount += 1;
          final relId = 'rId$imageCount';
          slideRels.write(
            '<Relationship Id="$relId" Type="$_imageRelType" '
            'Target="../media/$media"/>',
          );
          shapes.write(
            '<p:pic><p:blipFill><a:blip r:embed="$relId"/></p:blipFill></p:pic>',
          );
          archive.addFile(
            ArchiveFile.bytes('ppt/media/$media', utf8.encode('BINARY:$media')),
          );
      }
    }

    addFile(
      'ppt/slides/${slide.fileName}',
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<p:cSld><p:spTree>$shapes</p:spTree></p:cSld></p:sld>',
    );
    addFile(
      'ppt/slides/_rels/${slide.fileName}.rels',
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<Relationships xmlns="$_relNs">$slideRels</Relationships>',
    );
  }

  final bytes = ZipEncoder().encode(archive);
  return File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);
}

void main() {
  group('PptxIngestionBackend', () {
    late Directory dir;
    late DocmdPackageLayout layout;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('docmd_pptx_ingest_');
      layout = DocmdPackageLayout(p.join(dir.path, 'deck.docmd'))..createSkeleton();
    });

    tearDown(() => dir.deleteSync(recursive: true));

    Future<(String, dynamic)> ingest(List<SlideSpec> slides) async {
      final source = buildPptx(p.join(dir.path, 'deck.pptx'), slides);
      final backend = PptxIngestionBackend();
      final result = await backend.ingest(
        source: source,
        format: 'pptx',
        layout: layout,
      );
      return (File(layout.canonicalDocumentPath).readAsStringSync(), result);
    }

    test('is available without any external engine', () {
      expect(PptxIngestionBackend().isAvailable(), isTrue);
      expect(PptxIngestionBackend().isFallback, isFalse);
      expect(PptxIngestionBackend().formats, equals({'pptx'}));
    });

    test('gives every slide its own section, numbered in running order', () async {
      final (markdown, result) = await ingest([
        const SlideSpec('slide1.xml', [TextShape(['First'])]),
        const SlideSpec('slide2.xml', [TextShape(['Second'])]),
      ]);

      expect(result.status, equals('converted'));
      expect(markdown, contains('## Slide 1'));
      expect(markdown, contains('## Slide 2'));
      expect(markdown.indexOf('## Slide 1'), lessThan(markdown.indexOf('## Slide 2')));
      expect(markdown.indexOf('First'), lessThan(markdown.indexOf('Second')));
    });

    // Slide order lives in presentation.xml's sldIdLst, not in the part names.
    // Reordering a deck in PowerPoint leaves the file names alone, so trusting
    // slideN.xml numbering silently scrambles any deck that was ever reordered.
    test('follows presentation order, not slide file numbering', () async {
      final (markdown, _) = await ingest([
        // slide2.xml is presented *first*.
        const SlideSpec('slide2.xml', [TextShape(['Presented first'])]),
        const SlideSpec('slide1.xml', [TextShape(['Presented second'])]),
      ]);

      expect(
        markdown.indexOf('Presented first'),
        lessThan(markdown.indexOf('Presented second')),
      );
    });

    test('extracts each slide image and references it from the document', () async {
      final (markdown, result) = await ingest([
        const SlideSpec('slide1.xml', [
          TextShape(['Cover']),
          PictureShape('image1.png'),
        ]),
      ]);

      expect(markdown, contains('![](../assets/media/image1.png)'));
      expect(
        File(p.join(layout.assetsDirPath, 'media', 'image1.png')).existsSync(),
        isTrue,
      );
      expect(result.mediaExtracted, equals(1));
      expect(result.mediaReferenced, equals(1));
      expect(result.orphanedMedia, isEmpty);
    });

    test('keeps text and images in the order they appear on the slide', () async {
      final (markdown, _) = await ingest([
        const SlideSpec('slide1.xml', [
          TextShape(['Before the picture']),
          PictureShape('image1.png'),
          TextShape(['After the picture']),
        ]),
      ]);

      expect(
        markdown.indexOf('Before the picture'),
        lessThan(markdown.indexOf('![](../assets/media/image1.png)')),
      );
      expect(
        markdown.indexOf('![](../assets/media/image1.png)'),
        lessThan(markdown.indexOf('After the picture')),
      );
    });

    // The corpus deck that motivated this is 13 slides carrying 123 characters
    // of text and 19 images: an image-only deck must still import as one.
    test('handles an image-only slide', () async {
      final (markdown, result) = await ingest([
        const SlideSpec('slide1.xml', [
          PictureShape('image1.png'),
          PictureShape('image2.png'),
        ]),
      ]);

      expect(markdown, contains('## Slide 1'));
      expect(markdown, contains('![](../assets/media/image1.png)'));
      expect(markdown, contains('![](../assets/media/image2.png)'));
      expect(result.mediaExtracted, equals(2));
    });

    test('keeps an empty slide as a section rather than dropping it', () async {
      final (markdown, _) = await ingest([
        const SlideSpec('slide1.xml', []),
        const SlideSpec('slide2.xml', [TextShape(['Second'])]),
      ]);

      // Dropping it would renumber every later slide against the real deck.
      expect(markdown, contains('## Slide 1'));
      expect(markdown, contains('## Slide 2'));
    });

    test('reuses one media file referenced from several slides', () async {
      final (markdown, result) = await ingest([
        const SlideSpec('slide1.xml', [PictureShape('logo.png')]),
        const SlideSpec('slide2.xml', [PictureShape('logo.png')]),
      ]);

      expect(
        RegExp(r'!\[\]\(\.\./assets/media/logo\.png\)').allMatches(markdown).length,
        equals(2),
      );
      // Extracted once, not duplicated per reference.
      expect(result.mediaExtracted, equals(1));
    });

    // OOXML parts are UTF-8. Reading them as raw code units turns every accented
    // character into mojibake ("Información" -> "InformaciÃ³n"), which quietly
    // corrupts any deck not written in ASCII.
    test('preserves non-ASCII slide text', () async {
      final (markdown, _) = await ingest([
        const SlideSpec('slide1.xml', [
          TextShape(['Información General', 'Día de pago — ¿café?']),
        ]),
      ]);

      expect(markdown, contains('Información General'));
      expect(markdown, contains('Día de pago — ¿café?'));
      expect(markdown, isNot(contains('Ã')));
    });

    test('rejects a file that is not a readable pptx', () async {
      final broken = File(p.join(dir.path, 'broken.pptx'))
        ..writeAsStringSync('this is not a zip');

      expect(
        () => PptxIngestionBackend()
            .ingest(source: broken, format: 'pptx', layout: layout),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
