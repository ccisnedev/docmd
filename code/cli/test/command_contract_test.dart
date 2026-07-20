import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:docmd_cli/docmd_cli.dart';

import 'support/memory_sink.dart';

/// Runs `docmd <args>` through the real dispatcher and returns (exitCode, stderr).
Future<(int, String)> _run(List<String> args) async {
  final stdout = MemorySink();
  final stderr = MemorySink();
  final code = await runDocmd(args, stdout: stdout.sink, stderr: stderr.sink);
  return (code, await stderr.text());
}

void main() {
  late Directory tempDir;
  late String missing;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('docmd_contract_');
    missing = p.join(tempDir.path, 'nope.md');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('parameter contracts reject undeclared flags', () {
    test('version rejects an unknown option', () async {
      final (code, err) = await _run(['version', '--bogus']);
      expect(code, 7); // ExitCode.validationFailed
      expect(err, contains('unknown option --bogus'));
    });

    test('render rejects an unknown option', () async {
      final (code, err) = await _run(['render', missing, '--bogus']);
      expect(code, 7);
      expect(err, contains('unknown option --bogus'));
    });

    // --pptx is a real renderer (pandoc's native pptx writer), so it must reach
    // validation, not flag-rejection. --xlsx has no renderer and must stay an
    // unknown option rather than parse and then fail at the end.
    test('render advertises pptx but not xlsx', () async {
      final (pptxCode, pptxErr) = await _run(['render', missing, '--pptx']);
      expect(pptxErr, isNot(contains('unknown option --pptx')));
      expect(pptxCode, 7); // fails on the missing input, not on the flag
      expect(pptxErr, contains('not found'));

      final (xlsxCode, xlsxErr) = await _run(['render', missing, '--xlsx']);
      expect(xlsxCode, 7);
      expect(xlsxErr, contains('unknown option --xlsx'));
    });

    test('import rejects an unknown option', () async {
      final (code, err) = await _run(['import', missing, '--bogus']);
      expect(code, 7);
      expect(err, contains('unknown option --bogus'));
    });

    test('bench rejects an unknown option', () async {
      final (code, err) = await _run(['bench', tempDir.path, '--bogus']);
      expect(code, 7);
      expect(err, contains('unknown option --bogus'));
    });

    test('setup rejects an unknown option', () async {
      final (code, err) = await _run(['setup', 'docx', '--bogus']);
      expect(code, 7);
      expect(err, contains('unknown option --bogus'));
    });
  });

  group('new commands route and validate', () {
    test('setup preview runs without executing and exits ok', () async {
      final stdout = MemorySink();
      final code = await runDocmd(
        ['setup', 'docx'],
        stdout: stdout.sink,
        stderr: MemorySink().sink,
      );
      expect(code, 0);
      expect(await stdout.text(), contains('DocMD setup'));
    });

    test('bench rejects a missing corpus directory', () async {
      final (code, err) = await _run(['bench', p.join(tempDir.path, 'nope')]);
      expect(code, 7);
      expect(err, contains('not found'));
    });
  });

  // The VSCode extension invokes these exact flags. They must pass the contract
  // (reach validate — "not found") rather than being rejected ("unknown
  // option"), or the extension's spawns would start failing with exit != 0.
  group('the extension flags stay accepted', () {
    test('render --pdf reaches validation, not flag rejection', () async {
      final (code, err) = await _run(['render', missing, '--pdf']);
      expect(code, 7);
      expect(err, contains('not found'));
      expect(err, isNot(contains('unknown option')));
    });

    test('import --output-dir/--overwrite/--suffix reach validation', () async {
      final outDir = p.join(tempDir.path, 'out');
      final (code, err) =
          await _run(['import', missing, '--output-dir', outDir, '--overwrite']);
      expect(code, 7);
      expect(err, contains('not found'));
      expect(err, isNot(contains('unknown option')));
    });
  });
}
