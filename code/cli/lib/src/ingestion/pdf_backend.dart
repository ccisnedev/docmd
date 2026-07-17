library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pdf_reader/dart_pdf_reader.dart';
import 'package:path/path.dart' as p;

import '../package_layout.dart';
import 'ingestion_backend.dart';
import 'pdf/content_stream_text.dart';
import 'pdf/to_unicode_cmap.dart';

/// Ingests `.pdf` into Markdown by reading the PDF directly — no external engine.
///
/// This replaces the Python engines (markitdown, docling). It recovers the text
/// layer (glyph codes → Unicode via each font's `/ToUnicode` CMap) and extracts
/// embedded images, referencing them like every other format. It deliberately
/// does *no* OCR and *no* page rasterization: a PDF whose content is a scan or
/// vector art has no recoverable text layer, and that is left to a downstream
/// vision model rather than pulled into this pipeline.
///
/// [dart_pdf_reader] supplies the object model and stream decoding (FlateDecode
/// et al.); the text logic lives in the pure functions this composes.
class PdfIngestionBackend implements IngestionBackend {
  @override
  String get engineId => 'docmd';

  @override
  Set<String> get formats => const {'pdf'};

  /// Pure Dart — nothing to install, so nothing to be missing.
  @override
  bool isAvailable() => true;

  @override
  bool get isFallback => false;

  @override
  Future<IngestionResult> ingest({
    required File source,
    required String format,
    required DocmdPackageLayout layout,
  }) async {
    final PDFDocument doc;
    try {
      doc = await PDFParser(ByteStream(source.readAsBytesSync())).parse();
    } on Exception catch (e) {
      throw FormatException('Not a readable .pdf: ${source.path} ($e)');
    }

    final pages = await (await doc.catalog).getPages();
    final buffer = StringBuffer();
    final extractedMedia = <String>{};
    var referenceCount = 0;
    var imageIndex = 0;

    for (var pageNumber = 1; pageNumber <= pages.pageCount; pageNumber++) {
      final page = pages.getPageAtIndex(pageNumber - 1);
      final resolver = page.objectResolver;
      // A page comment marks provenance without inventing semantic headings —
      // PDF pages are layout, not sections.
      buffer.writeln('<!-- page $pageNumber -->');
      buffer.writeln();

      final text = await _extractPageText(page, resolver);
      if (text.trim().isNotEmpty) {
        buffer.writeln(text.trim());
        buffer.writeln();
      }

      for (final image in await _extractPageImages(page, resolver)) {
        if (image.bytes == null) {
          // Present but in an encoding we do not re-encode yet. Say so rather
          // than drop it silently — a reader must know an image was here.
          buffer.writeln(
            '<!-- image on page $pageNumber omitted: '
            'unsupported encoding (${image.encoding}) -->',
          );
          buffer.writeln();
          continue;
        }
        imageIndex += 1;
        final name = 'image$imageIndex${image.extension}';
        File(p.join(layout.assetsDirPath, 'media', name))
          ..createSync(recursive: true)
          ..writeAsBytesSync(image.bytes!);
        extractedMedia.add(name);
        referenceCount += 1;
        buffer.writeln('![](../assets/media/$name)');
        buffer.writeln();
      }
    }

    File(layout.canonicalDocumentPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(buffer.toString());

    return IngestionResult(
      'converted',
      mediaExtracted: extractedMedia.length,
      mediaReferenced: referenceCount == 0 ? 0 : extractedMedia.length,
      orphanedMedia: const [],
    );
  }

  Future<String> _extractPageText(
    PDFPageObjectNode page,
    ObjectResolver resolver,
  ) async {
    final cmaps = await _fontCMaps(page, resolver);

    final streams = await page.contentStreams;
    if (streams == null || streams.isEmpty) {
      return '';
    }
    final content = StringBuffer();
    for (final stream in streams) {
      content.write(String.fromCharCodes(await stream.read(resolver)));
      content.write('\n');
    }

    return extractTextFromContentStream(
      content.toString(),
      (fontName) => cmaps[fontName],
    );
  }

  /// Resource-name → CMap for the fonts on this page that carry a `/ToUnicode`
  /// map. Fonts without one are absent, so their glyphs are dropped rather than
  /// emitted as noise.
  Future<Map<String, ToUnicodeCMap>> _fontCMaps(
    PDFPageObjectNode page,
    ObjectResolver resolver,
  ) async {
    final resources = await page.resources;
    final fonts = await resolver.resolve<PDFDictionary>(
      resources?[PDFName('Font')],
    );
    if (fonts == null) return const {};

    final cmaps = <String, ToUnicodeCMap>{};
    for (final entry in fonts.entries.entries) {
      final font = await resolver.resolve<PDFDictionary>(entry.value);
      final toUnicode = await resolver.resolve<PDFStreamObject>(
        font?[PDFName('ToUnicode')],
      );
      if (toUnicode == null) continue;
      final cmap = ToUnicodeCMap.parse(
        String.fromCharCodes(await toUnicode.read(resolver)),
      );
      if (!cmap.isEmpty) {
        cmaps[entry.key.value] = cmap;
      }
    }
    return cmaps;
  }

  Future<List<_ExtractedImage>> _extractPageImages(
    PDFPageObjectNode page,
    ObjectResolver resolver,
  ) async {
    final resources = await page.resources;
    final xobjects = await resolver.resolve<PDFDictionary>(
      resources?[PDFName('XObject')],
    );
    if (xobjects == null) return const [];

    final images = <_ExtractedImage>[];
    for (final entry in xobjects.entries.entries) {
      final xobject = await resolver.resolve<PDFStreamObject>(entry.value);
      if (xobject == null) continue;
      final subtype = xobject.dictionary[PDFName('Subtype')];
      if (subtype is! PDFName || subtype.value != 'Image') continue;

      images.add(await _extractImage(xobject, resolver));
    }
    return images;
  }

  /// Extracts an embedded image when it is stored in a directly usable encoding:
  /// DCTDecode is a JPEG file as-is, JPXDecode a JPEG 2000. Raw-bitmap encodings
  /// (FlateDecode samples) would need re-encoding to PNG with colour-space
  /// handling; those come back with null bytes so the caller can report them
  /// rather than write unusable data.
  Future<_ExtractedImage> _extractImage(
    PDFStreamObject xobject,
    ObjectResolver resolver,
  ) async {
    final filters = _filterNames(xobject.dictionary, resolver);
    if (filters.contains('DCTDecode')) {
      return _ExtractedImage(await xobject.read(resolver), '.jpg', 'DCTDecode');
    }
    if (filters.contains('JPXDecode')) {
      return _ExtractedImage(await xobject.read(resolver), '.jp2', 'JPXDecode');
    }
    return _ExtractedImage(
      null,
      '',
      filters.isEmpty ? 'raw bitmap' : filters.join('+'),
    );
  }

  Set<String> _filterNames(PDFDictionary dictionary, ObjectResolver resolver) {
    final filter = dictionary[PDFName('Filter')];
    if (filter is PDFName) return {filter.value};
    if (filter is PDFArray) {
      return filter.whereType<PDFName>().map((f) => f.value).toSet();
    }
    return const {};
  }
}

class _ExtractedImage {
  /// Usable image file bytes, or null when the encoding is not yet supported.
  final Uint8List? bytes;
  final String extension;
  final String encoding;
  const _ExtractedImage(this.bytes, this.extension, this.encoding);
}
