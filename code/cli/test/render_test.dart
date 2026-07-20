import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:docmd_cli/modules/render/commands/render_file.dart';

void main() {
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

    test('execute() renders package inputs to pdf through pandoc and libreoffice', () async {
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