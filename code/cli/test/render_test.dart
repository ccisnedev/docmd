import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:docmd_cli/modules/render/commands/render_file.dart';

Directory _package(Directory parent, String name, String kind) {
  final packageDir = Directory(p.join(parent.path, '$name.docmd'))..createSync();
  Directory(p.join(packageDir.path, 'content')).createSync(recursive: true);
  File(p.join(packageDir.path, 'manifest.yaml')).writeAsStringSync(
    'kind: $kind\nversion: 0.0.1\ncanonical:\n  entry: content/document.md\n',
  );
  File(p.join(packageDir.path, 'content', 'document.md'))
      .writeAsStringSync('## Slide 1 · Title');
  return packageDir;
}

void main() {
  // Defaulting every package to docx turned `render` on an imported deck into a
  // silent format change, and left the VS Code extension with no way to ask for
  // pptx at all.
  group('RenderInput default format', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('docmd_render_kind_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('a deck package renders back to pptx', () {
      final packageDir = _package(dir, 'deck', 'deck');
      expect(
        RenderInput.formatFor(packageDir.path),
        equals('pptx'),
      );
    });

    test('a document package still renders to docx', () {
      final packageDir = _package(dir, 'requirement', 'document');
      expect(
        RenderInput.formatFor(packageDir.path),
        equals('docx'),
      );
    });

    // No manifest to consult, so the historical default stands.
    test('a bare markdown file still renders to docx', () {
      final file = File(p.join(dir.path, 'draft.md'))..writeAsStringSync('# Draft');
      expect(
        RenderInput.formatFor(file.path),
        equals('docx'),
      );
    });

    test('an explicit flag overrides the kind', () {
      final packageDir = _package(dir, 'deck', 'deck');
      expect(
        RenderInput.formatFor(packageDir.path, requested: 'docx'),
        equals('docx'),
      );
      expect(
        RenderInput.formatFor(packageDir.path, requested: 'pdf'),
        equals('pdf'),
      );
    });

    // A kind with no renderer must not become an unsupported format that
    // validate() then rejects; it falls back to docx.
    test('a sheet package falls back to docx', () {
      final packageDir = _package(dir, 'book', 'sheet');
      expect(
        RenderInput.formatFor(packageDir.path),
        equals('docx'),
      );
    });
  });

  group('Render Command', () {
    test('validate() returns error when input is missing', () {
      final cmd = RenderCommand(RenderInput(inputPath: '', format: 'docx'));
      expect(cmd.validate(), contains('Input path required'));
    });

    test('validate() rejects unsupported output formats', () {
      final dir = Directory.systemTemp.createTempSync('docmd_render_invalid_');
      final file = File('${dir.path}/draft.md')..writeAsStringSync('# Draft');

      try {
        // xlsx has no renderer; pptx now does, so it is no longer the example.
        final cmd = RenderCommand(RenderInput(inputPath: file.path, format: 'xlsx'));
        expect(cmd.validate(), contains('Unsupported output format'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('execute() renders markdown inputs to pptx through pandoc', () async {
      final dir = Directory.systemTemp.createTempSync('docmd_render_pptx_');
      final file = File('${dir.path}/deck.md')..writeAsStringSync('# Slide one');

      String? capturedExe;
      List<String>? capturedArgs;

      try {
        final cmd = RenderCommand(
          RenderInput(inputPath: file.path, format: 'pptx'),
          processRunner: (exe, args, {workingDirectory}) async {
            capturedExe = exe;
            capturedArgs = args;

            final outputIndex = args.indexOf('-o');
            File(args[outputIndex + 1])
              ..createSync(recursive: true)
              ..writeAsStringSync('pptx binary');

            return ProcessResult(0, 0, '', '');
          },
        );
        final output = await cmd.execute();

        // pptx is a native pandoc writer — same path as docx, not LibreOffice.
        expect(capturedExe, equals('pandoc'));
        expect(capturedArgs, containsAllInOrder(['-t', 'pptx']));
        expect(output.outputPath, endsWith('deck.pptx'));
        expect(output.status, equals('rendered'));
        expect(File(output.outputPath).existsSync(), isTrue);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('execute() renders markdown inputs to docx through pandoc', () async {
      final dir = Directory.systemTemp.createTempSync('docmd_render_test_');
      final file = File('${dir.path}/draft.md')..writeAsStringSync('# Draft');

      String? capturedExe;
      List<String>? capturedArgs;

      try {
        final cmd = RenderCommand(
          RenderInput(inputPath: file.path, format: 'docx'),
          processRunner: (exe, args, {workingDirectory}) async {
            capturedExe = exe;
            capturedArgs = args;

            final outputIndex = args.indexOf('-o');
            File(args[outputIndex + 1])
              ..createSync(recursive: true)
              ..writeAsStringSync('docx binary');

            return ProcessResult(0, 0, '', '');
          },
        );
        final output = await cmd.execute();

        expect(capturedExe, equals('pandoc'));
        expect(capturedArgs, contains('docx'));
        expect(output.outputPath, endsWith('draft.docx'));
        expect(output.sourceMarkdownPath, endsWith('draft.md'));
        expect(output.status, equals('rendered'));
        expect(File(output.outputPath).existsSync(), isTrue);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    // ADR 0003: with typst installed, pdf is a single pandoc call that hands
    // the Typst source to typst. pandoc writes its temporary .typ in the
    // working directory, so that must be a scratch directory, never the
    // caller's (it may not be writable) nor the package.
    test('execute() renders pdf through pandoc with the typst engine', () async {
      final dir = Directory.systemTemp.createTempSync('docmd_render_typst_');
      final file = File(p.join(dir.path, 'draft.md'))..writeAsStringSync('# Draft');

      final calls = <(String, List<String>, String?)>[];

      try {
        final cmd = RenderCommand(
          RenderInput(inputPath: file.path, format: 'pdf'),
          typstLocator: () => '/usr/bin/typst',
          processRunner: (exe, args, {workingDirectory}) async {
            calls.add((exe, args, workingDirectory));
            File(args[args.indexOf('-o') + 1])
              ..createSync(recursive: true)
              ..writeAsStringSync('pdf binary');
            return ProcessResult(0, 0, '', '');
          },
        );
        final output = await cmd.execute();

        expect(calls, hasLength(1));
        final (exe, args, workingDirectory) = calls.single;
        expect(exe, equals('pandoc'));
        expect(args, containsAllInOrder(['--pdf-engine', '/usr/bin/typst']));
        // pandoc hands typst the media it extracted to the temp dir as a
        // root-relative path (/Users/.../media-x/a.svg), which typst resolves
        // against --root: that must be the temp dir's filesystem root.
        final root = p.rootPrefix(Directory.systemTemp.absolute.path);
        expect(args, contains('--pdf-engine-opt=--root=$root'));
        expect(args[args.indexOf('-o') + 1], endsWith('draft.pdf'));
        expect(workingDirectory, isNotNull);
        expect(p.equals(workingDirectory!, dir.path), isFalse);
        expect(Directory(workingDirectory).existsSync(), isFalse,
            reason: 'the scratch directory is removed after the render');
        expect(output.outputPath, endsWith('draft.pdf'));
        expect(File(output.outputPath).existsSync(), isTrue);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('execute() falls back to pandoc and libreoffice for pdf without typst', () async {
      final dir = Directory.systemTemp.createTempSync('docmd_render_package_test_');
      final packageDir = Directory('${dir.path}/requirement.docmd')..createSync();
      Directory('${packageDir.path}/content').createSync(recursive: true);
      Directory('${packageDir.path}/exports').createSync(recursive: true);
      File('${packageDir.path}/manifest.yaml').writeAsStringSync('kind: document');
      File('${packageDir.path}/content/document.md').writeAsStringSync('# Imported');

      final calls = <String>[];

      try {
        final cmd = RenderCommand(
          RenderInput(inputPath: packageDir.path, format: 'pdf'),
          typstLocator: () => null,
          processRunner: (exe, args, {workingDirectory}) async {
            calls.add(exe);

            if (exe == 'pandoc') {
              final outputIndex = args.indexOf('-o');
              File(args[outputIndex + 1])
                ..createSync(recursive: true)
                ..writeAsStringSync('temp docx');
            } else if (p.basename(exe) == 'soffice' || p.basename(exe) == 'soffice.exe') {
              final inputDocx = args[3];
              final outdir = args[5];
              File(p.join(outdir, '${p.basenameWithoutExtension(inputDocx)}.pdf'))
                ..createSync(recursive: true)
                ..writeAsStringSync('pdf binary');
            }

            return ProcessResult(0, 0, '', '');
          },
        );

        final output = await cmd.execute();

        expect(calls, contains('pandoc'));
        expect(calls.any((value) => p.basename(value) == 'soffice' || p.basename(value) == 'soffice.exe'), isTrue);
        expect(output.outputPath, endsWith('requirement.pdf'));
        expect(output.sourceMarkdownPath, endsWith('content${p.separator}document.md'));
        expect(File(output.outputPath).existsSync(), isTrue);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}