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
///
/// `x`/`y` are the shape's EMU offset. Leaving them null omits the `<a:xfrm>`
/// entirely, which is how a shape with no geometry is expressed.
sealed class Shape {
  final int? x;
  final int? y;
  const Shape({this.x, this.y});
}

class TextShape extends Shape {
  final List<String> paragraphs;

  /// Emits the `<p:ph type="title"/>` that marks a layout title placeholder.
  final bool isTitlePlaceholder;

  const TextShape(
    this.paragraphs, {
    super.x,
    super.y,
    this.isTitlePlaceholder = false,
  });
}

class PictureShape extends Shape {
  /// Media file name, e.g. `image1.png`.
  final String media;
  const PictureShape(this.media, {super.x, super.y});
}

/// A group whose children live in their own coordinate space: `ext` is the size
/// on the slide, `chExt` the size the children are drawn against.
class GroupShape extends Shape {
  final List<Shape> children;
  final int extentHeight;
  final int childExtentHeight;

  const GroupShape(
    this.children, {
    super.x,
    super.y,
    this.extentHeight = 1000,
    this.childExtentHeight = 1000,
  });
}

class SlideSpec {
  /// Part name inside the archive, e.g. `slide2.xml`.
  final String fileName;
  final List<Shape> shapes;
  const SlideSpec(this.fileName, this.shapes);
}

/// 16:9 at 96 dpi — the PowerPoint default, and what the backend assumes when a
/// deck declares no size.
const int slideHeight = 6858000;

/// The backend reads a twentieth of the slide height as one row.
const int bandHeight = slideHeight ~/ 20;

String _shapeProperties(Shape shape) {
  if (shape.x == null || shape.y == null) {
    return '';
  }
  return '<p:spPr><a:xfrm><a:off x="${shape.x}" y="${shape.y}"/></a:xfrm></p:spPr>';
}

String _groupProperties(GroupShape group) {
  final offset = (group.x == null || group.y == null)
      ? ''
      : '<a:off x="${group.x}" y="${group.y}"/>';
  return '<p:grpSpPr><a:xfrm>$offset'
      '<a:ext cx="1000" cy="${group.extentHeight}"/>'
      '<a:chOff x="0" y="0"/>'
      '<a:chExt cx="1000" cy="${group.childExtentHeight}"/>'
      '</a:xfrm></p:grpSpPr>';
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
    '<p:sldIdLst>$sldIds</p:sldIdLst>'
    // 16:9 default. Reading bands are a twentieth of this, so 342 900 EMU.
    '<p:sldSz cx="12192000" cy="$slideHeight"/>'
    '</p:presentation>',
  );
  addFile(
    'ppt/_rels/presentation.xml.rels',
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<Relationships xmlns="$_relNs">$presRels</Relationships>',
  );

  for (final slide in slidesInPresentationOrder) {
    final slideRels = StringBuffer();
    var imageCount = 0;

    String emit(List<Shape> shapeList) {
      final out = StringBuffer();
      for (final shape in shapeList) {
        switch (shape) {
          case TextShape(:final paragraphs, :final isTitlePlaceholder):
            final body = paragraphs
                .map((text) => '<a:p><a:r><a:t>$text</a:t></a:r></a:p>')
                .join();
            final placeholder = isTitlePlaceholder
                ? '<p:nvSpPr><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>'
                : '';
            out.write(
              '<p:sp>$placeholder${_shapeProperties(shape)}'
              '<p:txBody>$body</p:txBody></p:sp>',
            );
          case PictureShape(:final media):
            imageCount += 1;
            final relId = 'rId$imageCount';
            slideRels.write(
              '<Relationship Id="$relId" Type="$_imageRelType" '
              'Target="../media/$media"/>',
            );
            out.write(
              '<p:pic>${_shapeProperties(shape)}'
              '<p:blipFill><a:blip r:embed="$relId"/></p:blipFill></p:pic>',
            );
            archive.addFile(
              ArchiveFile.bytes('ppt/media/$media', utf8.encode('BINARY:$media')),
            );
          case GroupShape(:final children):
            out.write(
              '<p:grpSp>${_groupProperties(shape)}${emit(children)}</p:grpSp>',
            );
        }
      }
      return out.toString();
    }

    final shapes = StringBuffer(emit(slide.shapes));

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

    // Document order in a slide is z-order — the order shapes were created, which
    // PowerPoint never rewrites. On the deck that motivated this, the numerals had
    // been added after the bullets, so reading the tree in order detached all four
    // from the text they label and left them clumped at the end of the slide.
    test('reads shapes in layout order, not the order they were created', () async {
      final (markdown, _) = await ingest([
        SlideSpec('slide1.xml', [
          const TextShape(['Diagnosis'], x: 0, y: 0),
          const TextShape(['Second finding'], x: 2000000, y: bandHeight * 6),
          const TextShape(['First finding'], x: 2000000, y: bandHeight * 4),
          const TextShape(['02.'], x: 1000000, y: bandHeight * 6),
          const TextShape(['01.'], x: 1000000, y: bandHeight * 4),
        ]),
      ]);

      expect(markdown.indexOf('01.'), lessThan(markdown.indexOf('First finding')));
      expect(
        markdown.indexOf('First finding'),
        lessThan(markdown.indexOf('02.')),
      );
      expect(markdown.indexOf('02.'), lessThan(markdown.indexOf('Second finding')));
    });

    // Shapes never line up to the pixel, so rows are bands rather than exact
    // matches on y. Without the band, a row of side-by-side boxes interleaves
    // with the rows above and below it.
    test('reads a row of near-aligned shapes left to right', () async {
      final (markdown, _) = await ingest([
        SlideSpec('slide1.xml', [
          const TextShape(['Processes'], x: 0, y: 0),
          const TextShape(['Right'], x: 9000000, y: bandHeight * 8 + 1000),
          const TextShape(['Left'], x: 200000, y: bandHeight * 8),
          const TextShape(['Middle'], x: 4000000, y: bandHeight * 8 + 500),
        ]),
      ]);

      expect(markdown.indexOf('Left'), lessThan(markdown.indexOf('Middle')));
      expect(markdown.indexOf('Middle'), lessThan(markdown.indexOf('Right')));
    });

    // A group's children are drawn against `chExt`, not the slide, so the band has
    // to be rescaled on the way in or a tall group collapses its rows into one.
    test('orders group children among themselves and the group among siblings', () async {
      final (markdown, _) = await ingest([
        SlideSpec('slide1.xml', [
          const TextShape(['Heading'], x: 0, y: 0),
          const TextShape(['After the group'], x: 0, y: bandHeight * 12),
          const GroupShape(
            [
              TextShape(['Group second'], x: 0, y: 800),
              TextShape(['Group first'], x: 0, y: 100),
            ],
            x: 0,
            y: bandHeight * 6,
            extentHeight: bandHeight * 2,
            childExtentHeight: 1000,
          ),
        ]),
      ]);

      expect(
        markdown.indexOf('Group first'),
        lessThan(markdown.indexOf('Group second')),
      );
      expect(
        markdown.indexOf('Group second'),
        lessThan(markdown.indexOf('After the group')),
      );
    });

    test('keeps document order when the slide carries no geometry', () async {
      final (markdown, _) = await ingest([
        const SlideSpec('slide1.xml', [
          TextShape(['Heading']),
          TextShape(['One']),
          TextShape(['Two']),
          TextShape(['Three']),
        ]),
      ]);

      expect(markdown.indexOf('One'), lessThan(markdown.indexOf('Two')));
      expect(markdown.indexOf('Two'), lessThan(markdown.indexOf('Three')));
    });

    test('titles the section from the layout placeholder, wherever it sits', () async {
      final (markdown, _) = await ingest([
        SlideSpec('slide1.xml', [
          const TextShape(['Body copy, first in reading order'], x: 0, y: 0),
          const TextShape(
            ['The Real Title'],
            x: 0,
            y: bandHeight * 10,
            isTitlePlaceholder: true,
          ),
        ]),
      ]);

      expect(markdown, contains('## Slide 1 · The Real Title'));
      expect(markdown, contains('Body copy, first in reading order'));
      // Promoted into the heading, not repeated in the body.
      expect(RegExp('The Real Title').allMatches(markdown).length, equals(1));
    });

    // Every slide of the deck this was built against is free-floating text boxes
    // with no placeholder at all, so the fallback carries the real decks.
    test('falls back to the first text in reading order as the title', () async {
      final (markdown, _) = await ingest([
        SlideSpec('slide1.xml', [
          const TextShape(['Body copy'], x: 0, y: bandHeight * 8),
          const TextShape(['¿DIAGNÓSTICO?'], x: 0, y: bandHeight),
        ]),
      ]);

      expect(markdown, contains('## Slide 1 · ¿DIAGNÓSTICO?'));
      expect(markdown, contains('Body copy'));
      expect(RegExp(r'¿DIAGNÓSTICO\?').allMatches(markdown).length, equals(1));
    });

    // Two slides of the motivating deck open with a decorative image that sorts
    // above the heading. A picture is never a title, so it must not cost the
    // slide its own.
    test('looks past a leading image for the title', () async {
      final (markdown, _) = await ingest([
        SlideSpec('slide1.xml', [
          const PictureShape('banner.png', x: 0, y: 0),
          const TextShape(['APP Santa Isabel'], x: 0, y: bandHeight * 4),
          const TextShape(['Body copy'], x: 0, y: bandHeight * 8),
        ]),
      ]);

      expect(markdown, contains('## Slide 1 · APP Santa Isabel'));
      expect(markdown, contains('![](../assets/media/banner.png)'));
      expect(RegExp('APP Santa Isabel').allMatches(markdown).length, equals(1));
    });

    test('leaves a long opening paragraph in the body rather than titling with it', () async {
      const paragraph =
          'Actualmente en el proceso de desembolso del producto se recaba la firma '
          'manuscrita digital de las socias, en donde se ha identificado lo siguiente.';
      final (markdown, _) = await ingest([
        const SlideSpec('slide1.xml', [TextShape([paragraph], x: 0, y: 0)]),
      ]);

      expect(markdown, contains('## Slide 1\n'));
      expect(markdown, contains(paragraph));
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
