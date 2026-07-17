import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:docmd_cli/src/ingestion/docling_pdf_backend.dart';
import 'package:docmd_cli/src/ingestion/markitdown_pdf_backend.dart';
import 'package:docmd_cli/src/package_layout.dart';

void main() {
  group('DoclingPdfBackend', () {
    test('converts a PDF, relocating docling artifacts into package assets', () async {
      final dir = Directory.systemTemp.createTempSync('docmd_docling_test_');
      final source = File(p.join(dir.path, 'sample.pdf'))
        ..writeAsStringSync('%PDF-1.7 stub');
      final layout = DocmdPackageLayout(p.join(dir.path, 'sample.docmd'))
        ..createSkeleton();

      String? capturedExe;
      List<String>? capturedArgs;

      try {
        final backend = DoclingPdfBackend(
          isAvailable: () => true,
          executableResolver: () => 'docling',
          // Simulate docling's real output shape: it writes `<stem>.md` into the
          // `--output` directory and, in referenced image mode, an artifacts
          // folder of images alongside it.
          processRunner: (exe, args, {workingDirectory}) async {
            capturedExe = exe;
            capturedArgs = args;

            final outputIndex = args.indexOf('--output');
            final outputDir = args[outputIndex + 1];
            final stem = p.basenameWithoutExtension(args.first);

            final artifactsDir =
                Directory(p.join(outputDir, '${stem}_artifacts'))
                  ..createSync(recursive: true);
            File(p.join(artifactsDir.path, 'image_000.png'))
                .writeAsStringSync('PNGDATA');
            File(p.join(outputDir, '$stem.md')).writeAsStringSync(
              '# Sample\n\n![figure](${stem}_artifacts/image_000.png)\n',
            );

            return ProcessResult(0, 0, '', '');
          },
        );

        final result = await backend.ingest(
          source: source,
          format: 'pdf',
          layout: layout,
        );

        expect(result.status, equals('converted'));
        expect(backend.engineId, equals('docling'));
        expect(capturedExe, equals('docling'));
        expect(capturedArgs, containsAllInOrder(['--to', 'md']));
        expect(
          capturedArgs,
          containsAllInOrder(['--image-export-mode', 'referenced']),
        );

        final canonical = File(layout.canonicalDocumentPath).readAsStringSync();
        expect(canonical, contains('# Sample'));
        // Reference rewritten so it resolves from content/document.md.
        expect(
          canonical,
          contains('](../assets/sample_artifacts/image_000.png)'),
        );
        // Image artifact relocated into the package assets directory.
        expect(
          File(p.join(
            layout.assetsDirPath,
            'sample_artifacts',
            'image_000.png',
          )).existsSync(),
          isTrue,
        );
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('throws when docling exits non-zero', () async {
      final dir = Directory.systemTemp.createTempSync('docmd_docling_fail_');
      final source = File(p.join(dir.path, 'sample.pdf'))
        ..writeAsStringSync('stub');
      final layout = DocmdPackageLayout(p.join(dir.path, 'sample.docmd'))
        ..createSkeleton();

      try {
        final backend = DoclingPdfBackend(
          isAvailable: () => true,
          processRunner: (exe, args, {workingDirectory}) async =>
              ProcessResult(0, 1, '', 'boom'),
        );

        expect(
          () => backend.ingest(source: source, format: 'pdf', layout: layout),
          throwsA(isA<ProcessException>()),
        );
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  group('MarkitdownPdfBackend', () {
    test('converts a PDF straight to the canonical document via -o', () async {
      final dir = Directory.systemTemp.createTempSync('docmd_markitdown_test_');
      final source = File(p.join(dir.path, 'sample.pdf'))
        ..writeAsStringSync('%PDF-1.7 stub');
      final layout = DocmdPackageLayout(p.join(dir.path, 'sample.docmd'))
        ..createSkeleton();

      String? capturedExe;
      List<String>? capturedArgs;

      try {
        final backend = MarkitdownPdfBackend(
          isAvailable: () => true,
          // Pin the resolver so the assertion below describes this backend's
          // contract rather than whatever markitdown the host happens to have.
          executableResolver: () => 'markitdown',
          // markitdown writes Markdown straight to the `-o` path (text-only).
          processRunner: (exe, args, {workingDirectory}) async {
            capturedExe = exe;
            capturedArgs = args;
            final outputIndex = args.indexOf('-o');
            File(args[outputIndex + 1])
              ..createSync(recursive: true)
              ..writeAsStringSync('# Sample\n\nExtracted text.\n');
            return ProcessResult(0, 0, '', '');
          },
        );

        final result = await backend.ingest(
          source: source,
          format: 'pdf',
          layout: layout,
        );

        expect(result.status, equals('converted'));
        expect(backend.engineId, equals('markitdown'));
        expect(capturedExe, equals('markitdown'));
        expect(capturedArgs, contains('-o'));
        expect(capturedArgs, contains(layout.canonicalDocumentPath));
        expect(
          File(layout.canonicalDocumentPath).readAsStringSync(),
          contains('Extracted text.'),
        );
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    // Regression: resolving a working binary is pointless if execution then goes
    // back through PATH by bare name — a broken shim earlier on PATH would win
    // and the tool locator's verification would be silently discarded.
    test('runs the resolved executable rather than the bare name', () async {
      final dir = Directory.systemTemp.createTempSync('docmd_markitdown_resolved_');
      final source = File(p.join(dir.path, 'sample.pdf'))
        ..writeAsStringSync('%PDF-1.7 stub');
      final layout = DocmdPackageLayout(p.join(dir.path, 'sample.docmd'))
        ..createSkeleton();

      const resolvedPath = r'C:\Users\dev\.local\bin\markitdown.exe';
      String? capturedExe;

      try {
        final backend = MarkitdownPdfBackend(
          executableResolver: () => resolvedPath,
          processRunner: (exe, args, {workingDirectory}) async {
            capturedExe = exe;
            final outputIndex = args.indexOf('-o');
            File(args[outputIndex + 1])
              ..createSync(recursive: true)
              ..writeAsStringSync('# Sample\n');
            return ProcessResult(0, 0, '', '');
          },
        );

        expect(backend.isAvailable(), isTrue);
        await backend.ingest(source: source, format: 'pdf', layout: layout);
        expect(capturedExe, equals(resolvedPath));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('is unavailable when no working executable resolves', () {
      final backend = MarkitdownPdfBackend(executableResolver: () => null);
      expect(backend.isAvailable(), isFalse);
    });
  });
}
