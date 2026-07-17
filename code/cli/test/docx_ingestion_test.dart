import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:docmd_cli/src/ingestion/pandoc_docx_backend.dart';
import 'package:docmd_cli/src/package_layout.dart';

/// A fake pandoc that reproduces what the real one emits for a docx carrying
/// sized images — the shape the previous mock (`# Imported from docx`) invented
/// away, which is why the portability and image-loss defects survived a green
/// suite.
///
/// Real behaviour, observed with pandoc 3.x:
///   * `--extract-media=DIR` writes files to `DIR/media/` and rewrites each
///     reference to point at the path *as given on the command line*.
///   * The gfm writer emits raw `<img>` HTML — not `![]()` — whenever an image
///     carries width/height attributes.
ProcessRunnerFake fakePandocEmittingSizedImages() => ProcessRunnerFake();

class ProcessRunnerFake {
  String? capturedExe;
  List<String>? capturedArgs;
  String? capturedWorkingDirectory;

  Future<ProcessResult> call(
    String exe,
    List<String> args, {
    String? workingDirectory,
  }) async {
    capturedExe = exe;
    capturedArgs = args;
    capturedWorkingDirectory = workingDirectory;

    final mediaArg = args.firstWhere((a) => a.startsWith('--extract-media='));
    final mediaDir = mediaArg.substring('--extract-media='.length);

    // pandoc resolves the media dir against its working directory.
    final resolvedMediaDir = p.isAbsolute(mediaDir)
        ? mediaDir
        : p.join(workingDirectory ?? Directory.current.path, mediaDir);
    final imagePath = p.join(resolvedMediaDir, 'media', 'image1.png');
    File(imagePath)
      ..createSync(recursive: true)
      ..writeAsStringSync('PNGDATA');

    // The reference pandoc writes back is the command-line path, verbatim.
    final referenced = p.join(mediaDir, 'media', 'image1.png');

    final outputIndex = args.indexOf('-o');
    File(args[outputIndex + 1])
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '# Title\n\n'
        '<img src="$referenced" style="width:5.9in;height:1.2in" />\n',
      );

    return ProcessResult(0, 0, '', '');
  }
}

void main() {
  group('PandocDocxBackend', () {
    late Directory dir;
    late File source;
    late DocmdPackageLayout layout;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('docmd_docx_ingest_');
      source = File(p.join(dir.path, 'sample.docx'))..writeAsStringSync('PK stub');
      layout = DocmdPackageLayout(p.join(dir.path, 'sample.docmd'))
        ..createSkeleton();
    });

    tearDown(() => dir.deleteSync(recursive: true));

    Future<String> ingestAndReadCanonical(ProcessRunnerFake fake) async {
      final backend = PandocDocxBackend(
        isAvailable: () => true,
        executableResolver: () => 'pandoc',
        processRunner: fake.call,
      );
      await backend.ingest(source: source, format: 'docx', layout: layout);
      return File(layout.canonicalDocumentPath).readAsStringSync();
    }

    // The package is the portable unit (ADR-0002). Absolute host paths baked
    // into the canonical document break every consumer that is not this exact
    // machine at this exact path.
    test('never writes host-absolute paths into the canonical document', () async {
      final fake = fakePandocEmittingSizedImages();
      final canonical = await ingestAndReadCanonical(fake);

      expect(canonical, isNot(contains(dir.path)));
      expect(canonical, isNot(contains(layout.assetsDirPath)));
    });

    // Images must survive the round trip. pandoc's docx writer silently drops
    // raw HTML, so an `<img>` tag means every image vanishes on render.
    test('rewrites raw img tags to Markdown image syntax', () async {
      final fake = fakePandocEmittingSizedImages();
      final canonical = await ingestAndReadCanonical(fake);

      expect(canonical, isNot(contains('<img')));
      expect(canonical, contains('![](../assets/media/image1.png)'));
    });

    test('references resolve from content/document.md to the real file', () async {
      final fake = fakePandocEmittingSizedImages();
      final canonical = await ingestAndReadCanonical(fake);

      final match = RegExp(r'!\[\]\(([^)]+)\)').firstMatch(canonical);
      expect(match, isNotNull, reason: 'expected a Markdown image reference');

      final resolved = p.normalize(
        p.join(p.dirname(layout.canonicalDocumentPath), match!.group(1)!),
      );
      expect(File(resolved).existsSync(), isTrue,
          reason: '$resolved should exist relative to the canonical document');
    });

    test('reports how many media files were extracted and referenced', () async {
      final fake = fakePandocEmittingSizedImages();
      final backend = PandocDocxBackend(
        isAvailable: () => true,
        executableResolver: () => 'pandoc',
        processRunner: fake.call,
      );

      final result = await backend.ingest(
        source: source,
        format: 'docx',
        layout: layout,
      );

      expect(result.status, equals('converted'));
      expect(result.mediaExtracted, equals(1));
      expect(result.mediaReferenced, equals(1));
      expect(result.orphanedMedia, isEmpty);
    });

    // pandoc extracts every file in word/media, including vector objects (.emf)
    // it cannot represent in Markdown. Those become orphans: present in the
    // package, referenced by nothing, silently absent from any render.
    test('reports unreferenced media as orphans', () async {
      final fake = ProcessRunnerFake();
      final backend = PandocDocxBackend(
        isAvailable: () => true,
        executableResolver: () => 'pandoc',
        processRunner: (exe, args, {workingDirectory}) async {
          final result = await fake.call(exe, args,
              workingDirectory: workingDirectory);
          // An .emf pandoc extracted but never referenced.
          final mediaArg =
              args.firstWhere((a) => a.startsWith('--extract-media='));
          final mediaDir = mediaArg.substring('--extract-media='.length);
          final resolved = p.isAbsolute(mediaDir)
              ? mediaDir
              : p.join(workingDirectory ?? Directory.current.path, mediaDir);
          File(p.join(resolved, 'media', 'image2.emf'))
            ..createSync(recursive: true)
            ..writeAsStringSync('EMFDATA');
          return result;
        },
      );

      final result = await backend.ingest(
        source: source,
        format: 'docx',
        layout: layout,
      );

      expect(result.mediaExtracted, equals(2));
      expect(result.mediaReferenced, equals(1));
      expect(result.orphanedMedia, equals(['media/image2.emf']));
    });

    test('throws when pandoc exits non-zero', () async {
      final backend = PandocDocxBackend(
        isAvailable: () => true,
        executableResolver: () => 'pandoc',
        processRunner: (exe, args, {workingDirectory}) async =>
            ProcessResult(0, 1, '', 'boom'),
      );

      expect(
        () => backend.ingest(source: source, format: 'docx', layout: layout),
        throwsA(isA<ProcessException>()),
      );
    });
  });
}
