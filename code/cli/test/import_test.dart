import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:docmd_cli/modules/importing/commands/import_file.dart';

void main() {
  group('Import Command', () {
    test('validate() returns error when input is missing', () {
      final cmd = ImportCommand(ImportInput(inputPath: ''));
      expect(cmd.validate(), contains('Input file required'));
    });

    test('execute() creates a package and copies markdown into content/document.md', () async {
      final dir = Directory.systemTemp.createTempSync('docmd_import_test_');
      final file = File('${dir.path}/requirement.md')
        ..writeAsStringSync('# Requirement');

      try {
        final cmd = ImportCommand(ImportInput(inputPath: file.path));
        final output = await cmd.execute();

        expect(output.packagePath, endsWith('requirement.docmd'));
        expect(output.status, equals('copied'));
        expect(
          output.canonicalDocumentPath,
          endsWith(p.join('content', 'document.md')),
        );
        expect(
          output.originalSourcePath,
          endsWith(p.join('assets', 'original', 'requirement.md')),
        );
        expect(
          File('${output.packagePath}/content/document.md').readAsStringSync(),
          equals('# Requirement'),
        );
        expect(
          File('${output.packagePath}/manifest.yaml').readAsStringSync(),
          contains('kind: document'),
        );
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('execute() creates the package under the requested output directory', () async {
      final dir = Directory.systemTemp.createTempSync('docmd_import_output_test_');
      final outputDir = Directory(p.join(dir.path, 'imports'));
      final file = File('${dir.path}/requirement.md')
        ..writeAsStringSync('# Requirement');

      try {
        final cmd = ImportCommand(
          ImportInput(inputPath: file.path, outputDir: outputDir.path),
        );
        final output = await cmd.execute();

        expect(
          output.packagePath,
          equals(p.join(outputDir.path, 'requirement.docmd')),
        );
        expect(
          File(p.join(output.packagePath, 'content', 'document.md'))
              .readAsStringSync(),
          equals('# Requirement'),
        );
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('execute() converts docx inputs through pandoc', () async {
      final dir = Directory.systemTemp.createTempSync('docmd_import_docx_test_');
      final file = File('${dir.path}/requirement.docx')..writeAsStringSync('stub');

      String? capturedExe;
      List<String>? capturedArgs;

      try {
        final cmd = ImportCommand(
          ImportInput(inputPath: file.path),
          processRunner: (exe, args, {workingDirectory}) async {
            capturedExe = exe;
            capturedArgs = args;

            final outputIndex = args.indexOf('-o');
            File(args[outputIndex + 1])
              ..createSync(recursive: true)
              ..writeAsStringSync('# Imported from docx');

            return ProcessResult(0, 0, '', '');
          },
        );

        final output = await cmd.execute();

        expect(capturedExe, equals('pandoc'));
        expect(
          capturedArgs,
          contains('--extract-media=${p.join(output.packagePath, 'assets')}'),
        );
        expect(output.status, equals('converted'));
        expect(output.manifestPath, endsWith('manifest.yaml'));
        expect(
          File('${output.packagePath}/content/document.md').readAsStringSync(),
          contains('Imported from docx'),
        );
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
