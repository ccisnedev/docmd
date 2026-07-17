library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../package_layout.dart';
import 'ingestion_backend.dart';

/// Ingests `.pptx` decks into Markdown by reading the OOXML package directly.
///
/// A pptx is a zip of XML parts, so no external engine is needed: this backend
/// is always available, which matters because the alternatives are not viable.
/// pandoc has no pptx *reader* (it only writes pptx), and markitdown's pptx
/// output references pictures by shape name (`Imagen4.jpg`) rather than by media
/// part, so its image links cannot be resolved to files and point at nothing.
///
/// Each slide becomes a `## Slide N` section holding that slide's text and
/// images in the order they appear on the slide.
class PptxIngestionBackend implements IngestionBackend {
  @override
  String get engineId => 'docmd';

  @override
  Set<String> get formats => const {'pptx'};

  /// Pure Dart: nothing to install, so nothing to be missing.
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
    final archive = _openArchive(source);
    final slideParts = _slidePartsInPresentationOrder(archive);

    final buffer = StringBuffer();
    final extractedMedia = <String>{};
    var referenceCount = 0;

    for (var index = 0; index < slideParts.length; index++) {
      final slidePart = slideParts[index];
      buffer.writeln('## Slide ${index + 1}');
      buffer.writeln();

      final relationships = _imageRelationships(archive, slidePart);
      for (final block in _slideBlocks(archive, slidePart, relationships)) {
        switch (block) {
          case _TextBlock(:final text):
            buffer.writeln(text);
            buffer.writeln();
          case _ImageBlock(:final mediaName):
            _extractMedia(archive, mediaName, layout);
            extractedMedia.add(mediaName);
            referenceCount += 1;
            // Resolves from content/document.md, one level below the package root.
            buffer.writeln('![](../assets/media/$mediaName)');
            buffer.writeln();
        }
      }
    }

    File(layout.canonicalDocumentPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(buffer.toString());

    return IngestionResult(
      'converted',
      mediaExtracted: extractedMedia.length,
      // Every image this backend writes is one it just referenced, so a deck
      // cannot produce orphans the way pandoc's bulk media extraction can.
      mediaReferenced: referenceCount == 0 ? 0 : extractedMedia.length,
      orphanedMedia: const [],
    );
  }

  Archive _openArchive(File source) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(source.readAsBytesSync());
    } on Exception catch (e) {
      throw FormatException('Not a readable .pptx package: ${source.path} ($e)');
    }

    // ZipDecoder answers garbage with an empty archive rather than an error, and
    // a zip that is not a deck has no presentation part. Both would otherwise
    // import as an empty package reported as "converted", which is worse than
    // failing: it looks like the deck genuinely had nothing in it.
    if (archive.findFile('ppt/presentation.xml') == null) {
      throw FormatException(
        'Not a readable .pptx package (no ppt/presentation.xml): ${source.path}',
      );
    }
    return archive;
  }

  /// Running order comes from `presentation.xml`'s `sldIdLst`, resolved through
  /// the presentation relationships. Part names (`slide7.xml`) reflect creation
  /// order, not running order — reordering a deck in PowerPoint does not rename
  /// anything — so ordering by file name scrambles reordered decks.
  List<String> _slidePartsInPresentationOrder(Archive archive) {
    final presentation = _parseXml(archive, 'ppt/presentation.xml');
    final rels = _relationshipTargets(archive, 'ppt/_rels/presentation.xml.rels');
    if (presentation == null) {
      return const [];
    }

    final parts = <String>[];
    // Namespace-wildcarded: the `p:` prefix is conventional, not guaranteed.
    for (final sldId in presentation.findAllElements('sldId', namespace: '*')) {
      final relId = _relationshipId(sldId);
      final target = relId == null ? null : rels[relId];
      if (target != null) {
        parts.add(p.url.normalize('ppt/$target'));
      }
    }
    return parts;
  }

  /// Relationship id -> media part name, for the image relationships of a slide.
  Map<String, String> _imageRelationships(Archive archive, String slidePart) {
    final relsPath = p.url.join(
      p.url.dirname(slidePart),
      '_rels',
      '${p.url.basename(slidePart)}.rels',
    );
    return _relationshipTargets(archive, relsPath).map(
      (id, target) => MapEntry(id, p.url.basename(target)),
    );
  }

  Map<String, String> _relationshipTargets(Archive archive, String relsPath) {
    final document = _parseXml(archive, relsPath);
    if (document == null) {
      return const {};
    }

    final targets = <String, String>{};
    for (final relationship in document.findAllElements('Relationship')) {
      final id = relationship.getAttribute('Id');
      final target = relationship.getAttribute('Target');
      if (id != null && target != null) {
        targets[id] = target;
      }
    }
    return targets;
  }

  /// Walks the slide's shape tree in document order, yielding the text and the
  /// pictures as they are laid out. Recurses into group shapes, whose children
  /// are ordinary shapes one level down.
  Iterable<_Block> _slideBlocks(
    Archive archive,
    String slidePart,
    Map<String, String> imageRelationships,
  ) sync* {
    final slide = _parseXml(archive, slidePart);
    if (slide == null) {
      return;
    }

    final shapeTree = slide.findAllElements('spTree', namespace: '*').firstOrNull;
    if (shapeTree == null) {
      return;
    }

    yield* _blocksIn(shapeTree, imageRelationships);
  }

  Iterable<_Block> _blocksIn(
    XmlElement parent,
    Map<String, String> imageRelationships,
  ) sync* {
    for (final element in parent.childElements) {
      switch (element.name.local) {
        case 'sp':
          final text = _shapeText(element);
          if (text.isNotEmpty) {
            yield _TextBlock(text);
          }
        case 'pic':
          final mediaName = _pictureMedia(element, imageRelationships);
          if (mediaName != null) {
            yield _ImageBlock(mediaName);
          }
        case 'grpSp':
          yield* _blocksIn(element, imageRelationships);
      }
    }
  }

  /// One Markdown line per `<a:p>`, joining that paragraph's runs.
  String _shapeText(XmlElement shape) {
    final paragraphs = <String>[];
    for (final paragraph in shape.findAllElements('p', namespace: _drawingmlNs)) {
      final text = paragraph
          .findAllElements('t', namespace: _drawingmlNs)
          .map((run) => run.innerText)
          .join()
          .trim();
      if (text.isNotEmpty) {
        paragraphs.add(text);
      }
    }
    return paragraphs.join('\n\n');
  }

  String? _pictureMedia(
    XmlElement picture,
    Map<String, String> imageRelationships,
  ) {
    final blip = picture.findAllElements('blip', namespace: _drawingmlNs).firstOrNull;
    if (blip == null) {
      return null;
    }
    final embedId = _relationshipId(blip);
    return embedId == null ? null : imageRelationships[embedId];
  }

  void _extractMedia(Archive archive, String mediaName, DocmdPackageLayout layout) {
    final target = File(p.join(layout.assetsDirPath, 'media', mediaName));
    if (target.existsSync()) {
      // Decks reuse one media part across slides; extract it once.
      return;
    }

    final entry = archive.findFile('ppt/media/$mediaName');
    if (entry == null) {
      return;
    }

    target
      ..createSync(recursive: true)
      ..writeAsBytesSync(entry.readBytes() ?? const []);
  }

  XmlDocument? _parseXml(Archive archive, String path) {
    final entry = archive.findFile(path);
    if (entry == null) {
      return null;
    }
    try {
      // OOXML parts are UTF-8; decoding them as raw code units mangles every
      // non-ASCII character. `allowMalformed` keeps one bad byte from failing an
      // otherwise readable deck.
      final text = utf8.decode(entry.readBytes() ?? const [], allowMalformed: true);
      return XmlDocument.parse(text);
    } on XmlException {
      return null;
    }
  }

  /// The relationship pointer `r:id` / `r:embed`. Matched on local name plus the
  /// presence of a prefix, which distinguishes `r:id` from the unrelated plain
  /// `id` attribute that sits beside it on `<p:sldId>`.
  String? _relationshipId(XmlElement element) {
    for (final attribute in element.attributes) {
      final local = attribute.name.local;
      if ((local == 'id' || local == 'embed') && attribute.name.prefix != null) {
        return attribute.value;
      }
    }
    return null;
  }
}

const String _drawingmlNs = 'http://schemas.openxmlformats.org/drawingml/2006/main';

sealed class _Block {
  const _Block();
}

class _TextBlock extends _Block {
  final String text;
  const _TextBlock(this.text);
}

class _ImageBlock extends _Block {
  final String mediaName;
  const _ImageBlock(this.mediaName);
}
