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
/// Each slide becomes a `## Slide N` section — titled when the slide has a title
/// — holding that slide's text and images in **reading order** (see
/// [_blocksIn]).
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
    final bandHeight = _readingBandHeight(archive);

    final buffer = StringBuffer();
    final extractedMedia = <String>{};
    var referenceCount = 0;

    for (var index = 0; index < slideParts.length; index++) {
      final slidePart = slideParts[index];
      final relationships = _imageRelationships(archive, slidePart);
      final slide = _readSlide(archive, slidePart, relationships, bandHeight);

      buffer.writeln(
        slide.title == null
            ? '## Slide ${index + 1}'
            : '## Slide ${index + 1} · ${slide.title}',
      );
      buffer.writeln();

      for (final block in slide.blocks) {
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

  /// Height of one horizontal reading band, in EMU: shapes whose tops fall in the
  /// same band count as one visual row and are read left to right.
  ///
  /// A twentieth of the slide height is calibrated, not guessed. On the deck that
  /// motivated this, a bullet and its `01.` numeral sit 140 746 EMU apart on a
  /// 6 858 000 EMU slide: a band of `cy / 40` splits them into separate rows and
  /// puts the numeral after its own bullet, while `cy / 20` keeps the pair in one
  /// row so the numeral leads, as printed. The same value keeps a row of six
  /// side-by-side process boxes in left-to-right order rather than interleaving
  /// them with the rows above and below.
  double _readingBandHeight(Archive archive) {
    const defaultSlideHeight = 6858000; // 16:9 at 96 dpi, the PowerPoint default.
    final presentation = _parseXml(archive, 'ppt/presentation.xml');
    final size = presentation
        ?.findAllElements('sldSz', namespace: '*')
        .firstOrNull;
    final height = int.tryParse(size?.getAttribute('cy') ?? '') ?? defaultSlideHeight;
    return (height <= 0 ? defaultSlideHeight : height) / 20;
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

  _Slide _readSlide(
    Archive archive,
    String slidePart,
    Map<String, String> imageRelationships,
    double bandHeight,
  ) {
    final slide = _parseXml(archive, slidePart);
    final shapeTree = slide
        ?.findAllElements('spTree', namespace: '*')
        .firstOrNull;
    if (shapeTree == null) {
      return const _Slide(null, []);
    }

    final blocks = _blocksIn(shapeTree, imageRelationships, bandHeight).toList();
    return _titledSlide(shapeTree, blocks);
  }

  /// Splits the slide title off the body.
  ///
  /// The layout placeholder is authoritative when present. Plenty of real decks
  /// have none — every slide of the deck this was built against is free-floating
  /// text boxes with no placeholder at all — so the fallback is the first text in
  /// reading order, which is where a title sits by construction. The length guard
  /// keeps a paragraph of body copy on a title-less slide from being promoted
  /// into the heading.
  _Slide _titledSlide(XmlElement shapeTree, List<_Block> blocks) {
    final title = _placeholderTitle(shapeTree) ?? _heuristicTitle(blocks);
    if (title == null) {
      return _Slide(null, blocks);
    }

    // The title shape is still in the body — the placeholder is not necessarily
    // the first shape in reading order, so it is matched rather than assumed.
    // Leaving it would print the title twice, as heading and as body text.
    final body = [...blocks];
    final titleIndex = body.indexWhere(
      (block) => block is _TextBlock && _asHeading(block.text) == title,
    );
    if (titleIndex >= 0) {
      body.removeAt(titleIndex);
    }
    return _Slide(title, body);
  }

  /// The first *text* in reading order, which is where a title sits by
  /// construction. Leading images are skipped rather than disqualifying the
  /// slide: a picture is never a title, and on the motivating deck two slides
  /// open with a decorative image that sorts above the heading. The length guard
  /// is what keeps body copy from being promoted on a slide that has no title.
  String? _heuristicTitle(List<_Block> blocks) {
    for (final block in blocks) {
      if (block is _ImageBlock) {
        continue;
      }
      if (block is _TextBlock && block.text.length <= _maxHeuristicTitleLength) {
        return _asHeading(block.text);
      }
      return null;
    }
    return null;
  }

  String? _placeholderTitle(XmlElement shapeTree) {
    for (final shape in shapeTree.findAllElements('sp', namespace: '*')) {
      final placeholder = shape
          .findAllElements('ph', namespace: '*')
          .firstOrNull;
      final type = placeholder?.getAttribute('type');
      if (type == 'title' || type == 'ctrTitle') {
        final text = _shapeText(shape);
        if (text.isNotEmpty) {
          return _asHeading(text);
        }
      }
    }
    return null;
  }

  /// A title box may hold several paragraphs ("APP Santa Isabel" / "(App de la
  /// Socia)"); a heading is one line.
  String _asHeading(String text) =>
      text.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty).join(' ');

  /// Walks a shape tree in **reading order**, yielding text and pictures as they
  /// are laid out. Recurses into group shapes, whose children are ordinary shapes
  /// one level down.
  ///
  /// Document order is z-order — the order shapes were created, which PowerPoint
  /// never rewrites — so it does not survive any editing. On the motivating deck
  /// it detached all four `01.`–`04.` numerals from their bullets and left them
  /// in a clump at the end of the slide. Sorting siblings by position restores
  /// what the slide actually reads like.
  ///
  /// Shapes with no `<a:off>` inherit the previous positioned sibling's spot
  /// (leading ones default to the origin), and the document index breaks ties, so
  /// a slide that carries no geometry at all comes out in document order exactly
  /// as before.
  Iterable<_Block> _blocksIn(
    XmlElement parent,
    Map<String, String> imageRelationships,
    double bandHeight,
  ) sync* {
    final ordered = _childShapesInReadingOrder(parent, bandHeight);

    for (final shape in ordered) {
      switch (shape.name.local) {
        case 'sp':
          final text = _shapeText(shape);
          if (text.isNotEmpty) {
            yield _TextBlock(text);
          }
        case 'pic':
          final mediaName = _pictureMedia(shape, imageRelationships);
          if (mediaName != null) {
            yield _ImageBlock(mediaName);
          }
        case 'grpSp':
          yield* _blocksIn(
            shape,
            imageRelationships,
            _childBandHeight(shape, bandHeight),
          );
      }
    }
  }

  List<XmlElement> _childShapesInReadingOrder(
    XmlElement parent,
    double bandHeight,
  ) {
    final keyed = <_PositionedShape>[];
    var lastX = 0;
    var lastY = 0;

    for (final element in parent.childElements) {
      if (!_shapeTags.contains(element.name.local)) {
        continue;
      }
      final offset = _offsetOf(element);
      if (offset != null) {
        lastX = offset.$1;
        lastY = offset.$2;
      }
      keyed.add(
        _PositionedShape(
          element: element,
          band: (lastY / bandHeight).floor(),
          x: lastX,
          documentIndex: keyed.length,
        ),
      );
    }

    // Dart's sort is not stable, so the document index is part of the ordering
    // rather than left to the algorithm.
    keyed.sort((a, b) {
      final byBand = a.band.compareTo(b.band);
      if (byBand != 0) return byBand;
      final byX = a.x.compareTo(b.x);
      if (byX != 0) return byX;
      return a.documentIndex.compareTo(b.documentIndex);
    });

    return [for (final shape in keyed) shape.element];
  }

  /// A group's children are expressed in its own child coordinate space, so the
  /// band has to be rescaled by the child-to-parent ratio or a tall group would
  /// collapse its rows into one and a short one would split every row.
  double _childBandHeight(XmlElement group, double bandHeight) {
    final transform = _transformOf(group);
    final extent = transform?.findElements('ext', namespace: _drawingmlNs).firstOrNull;
    final childExtent =
        transform?.findElements('chExt', namespace: _drawingmlNs).firstOrNull;

    final height = int.tryParse(extent?.getAttribute('cy') ?? '');
    final childHeight = int.tryParse(childExtent?.getAttribute('cy') ?? '');
    if (height == null || childHeight == null || height <= 0) {
      return bandHeight;
    }
    return bandHeight * childHeight / height;
  }

  (int, int)? _offsetOf(XmlElement shape) {
    final offset = _transformOf(
      shape,
    )?.findElements('off', namespace: _drawingmlNs).firstOrNull;
    final x = int.tryParse(offset?.getAttribute('x') ?? '');
    final y = int.tryParse(offset?.getAttribute('y') ?? '');
    return (x == null || y == null) ? null : (x, y);
  }

  /// The shape's own `<a:xfrm>`, reached through its direct properties element —
  /// `p:spPr` for shapes and pictures, `p:grpSpPr` for groups. Searching the
  /// subtree instead would let a group pick up a child's transform.
  XmlElement? _transformOf(XmlElement shape) {
    final properties = shape.childElements
        .where((child) => _shapePropertyTags.contains(child.name.local))
        .firstOrNull;
    return properties?.findElements('xfrm', namespace: _drawingmlNs).firstOrNull;
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

const Set<String> _shapeTags = {'sp', 'pic', 'grpSp'};

const Set<String> _shapePropertyTags = {'spPr', 'grpSpPr'};

/// Long enough for a wrapped headline, short enough that a paragraph of body copy
/// is never mistaken for a title.
const int _maxHeuristicTitleLength = 120;

class _Slide {
  final String? title;
  final List<_Block> blocks;
  const _Slide(this.title, this.blocks);
}

class _PositionedShape {
  final XmlElement element;
  final int band;
  final int x;
  final int documentIndex;

  const _PositionedShape({
    required this.element,
    required this.band,
    required this.x,
    required this.documentIndex,
  });
}

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
