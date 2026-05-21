import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:docmd_cli/docmd_cli.dart';
import 'package:docmd_cli/modules/importing/commands/import_file.dart';
import 'package:docmd_cli/modules/render/commands/render_file.dart';

final bool _hasPandoc = _toolExists('pandoc');
final bool _hasLibreOffice = _toolExists(
  Platform.isWindows ? 'soffice.exe' : 'soffice',
);

void main() {
  group('Real document integration', () {
    test(
      'imports the real analisis fixture into a semantic Markdown package',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'docmd_real_import_test_',
        );
        final fixtureCopy = _copyFixtureToTemp(tempDir);

        try {
          final cmd = ImportCommand(ImportInput(inputPath: fixtureCopy.path));
          final output = await cmd.execute();
          final markdown = File(output.canonicalDocumentPath).readAsStringSync();
          final manifest = File(output.manifestPath).readAsStringSync();

          expect(output.status, equals('converted'));
          expect(output.packagePath, endsWith('analisis.docmd'));
          expect(File(output.originalSourcePath).existsSync(), isTrue);
          expect(manifest, contains('kind: document'));
          expect(manifest, contains('format: docx'));

          expect(markdown, contains('Análisis de Requerimiento'));
          expect(markdown, contains('# 1. Historias de Usuario'));
          expect(markdown, contains('### Acceptance Criteria'));
          expect(markdown, contains('| AC-1 |'));
          expect(markdown, contains('# 2. Estrategia de Testing'));
          expect(markdown, contains('# 3. Alcance Explícito'));
          expect(markdown, contains('# Anexos'));
        } finally {
          tempDir.deleteSync(recursive: true);
        }
      },
      skip: !_hasPandoc,
    );

    test(
      'emits machine-readable JSON for the real analisis fixture',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'docmd_real_json_test_',
        );
        final fixtureCopy = _copyFixtureToTemp(tempDir);

        final stdoutController = StreamController<List<int>>();
        final stderrController = StreamController<List<int>>();
        final stdoutBytes = <int>[];
        final stderrBytes = <int>[];

        stdoutController.stream.listen(stdoutBytes.addAll);
        stderrController.stream.listen(stderrBytes.addAll);

        final stdoutSink = IOSink(stdoutController.sink);
        final stderrSink = IOSink(stderrController.sink);

        try {
          final exitCode = await runDocmd(
            ['import', fixtureCopy.path, '--json'],
            stdout: stdoutSink,
            stderr: stderrSink,
          );

          await stdoutSink.flush();
          await stderrSink.flush();
          await stdoutSink.close();
          await stderrSink.close();

          final stdoutText = utf8.decode(stdoutBytes).trim();
          final stderrText = utf8.decode(stderrBytes).trim();
          final json = jsonDecode(stdoutText) as Map<String, dynamic>;

          expect(exitCode, equals(0));
          expect(stderrText, isEmpty);
          expect(json['status'], equals('converted'));
          expect(json['packagePath'], endsWith('analisis.docmd'));
          expect(
            json['canonicalDocumentPath'],
            endsWith(p.join('content', 'document.md')),
          );
        } finally {
          await stdoutController.close();
          await stderrController.close();
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        }
      },
      skip: !_hasPandoc,
    );

    test(
      'round-trips the real analisis fixture back to docx after editing Markdown',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'docmd_real_roundtrip_test_',
        );
        final fixtureCopy = _copyFixtureToTemp(tempDir);

        try {
          final importOutput = await ImportCommand(
            ImportInput(inputPath: fixtureCopy.path),
          ).execute();

          final canonicalFile = File(importOutput.canonicalDocumentPath);
          canonicalFile.writeAsStringSync(
            '${canonicalFile.readAsStringSync()}\n\n## Round-trip Verification\n\nThis paragraph was added by the integration test.\n',
          );

          final renderOutput = await RenderCommand(
            RenderInput(inputPath: importOutput.packagePath, format: 'docx'),
          ).execute();

          expect(renderOutput.status, equals('rendered'));
          expect(File(renderOutput.outputPath).existsSync(), isTrue);

          final reimportSource = File(
            p.join(tempDir.path, 'roundtrip.docx'),
          );
          File(renderOutput.outputPath).copySync(reimportSource.path);

          final reimportOutput = await ImportCommand(
            ImportInput(inputPath: reimportSource.path),
          ).execute();
          final roundTripMarkdown = File(
            reimportOutput.canonicalDocumentPath,
          ).readAsStringSync();

          expect(roundTripMarkdown, contains('Round-trip Verification'));
          expect(
            roundTripMarkdown,
            contains('This paragraph was added by the integration test.'),
          );
          expect(roundTripMarkdown, contains('Análisis de Requerimiento'));
        } finally {
          tempDir.deleteSync(recursive: true);
        }
      },
      skip: !_hasPandoc,
    );

    test(
      'renders the real analisis fixture package to pdf',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'docmd_real_pdf_test_',
        );
        final fixtureCopy = _copyFixtureToTemp(tempDir);

        try {
          final importOutput = await ImportCommand(
            ImportInput(inputPath: fixtureCopy.path),
          ).execute();

          final renderOutput = await RenderCommand(
            RenderInput(inputPath: importOutput.packagePath, format: 'pdf'),
          ).execute();

          final pdfFile = File(renderOutput.outputPath);
          expect(renderOutput.status, equals('rendered'));
          expect(pdfFile.existsSync(), isTrue);
          expect(pdfFile.lengthSync(), greaterThan(0));
        } finally {
          tempDir.deleteSync(recursive: true);
        }
      },
      skip: !_hasPandoc || !_hasLibreOffice,
    );
  });
}

File _copyFixtureToTemp(Directory tempDir) {
  final fixturePath = p.join(Directory.current.path, 'test', 'fixtures', 'analisis.docx');
  final targetPath = p.join(tempDir.path, 'analisis.docx');
  return File(fixturePath).copySync(targetPath);
}

bool _toolExists(String executable) {
  final lookup = Platform.isWindows ? 'where' : 'which';
  final result = Process.runSync(lookup, [executable]);
  return result.exitCode == 0;
}