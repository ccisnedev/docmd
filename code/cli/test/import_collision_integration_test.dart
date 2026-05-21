import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:docmd_cli/docmd_cli.dart';

void main() {
  group('Import collision integration', () {
    test('overwrites an existing package when --overwrite is passed', () async {
      final dir = Directory.systemTemp.createTempSync('docmd_import_overwrite_');
      final sourceFile = File(p.join(dir.path, 'sample.md'))..writeAsStringSync('# First version');

      try {
        final initial = await _runDocmdJson(['import', sourceFile.path, '--json']);
        expect(initial.exitCode, equals(0));

        final packagePath = initial.stdoutJson['packagePath'] as String;
        File(p.join(packagePath, 'stale.txt')).writeAsStringSync('stale');
        sourceFile.writeAsStringSync('# Second version');

        final overwrite = await _runDocmdJson([
          'import',
          sourceFile.path,
          '--overwrite',
          '--json',
        ]);

        expect(overwrite.exitCode, equals(0));
        expect(overwrite.stdoutJson['packagePath'], equals(packagePath));
        expect(
          File(p.join(packagePath, 'content', 'document.md')).readAsStringSync(),
          equals('# Second version'),
        );
        expect(File(p.join(packagePath, 'stale.txt')).existsSync(), isFalse);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('creates the next available suffixed package when --suffix is passed', () async {
      final dir = Directory.systemTemp.createTempSync('docmd_import_suffix_');
      final sourceFile = File(p.join(dir.path, 'sample.md'))..writeAsStringSync('# Sample');

      try {
        final first = await _runDocmdJson(['import', sourceFile.path, '--json']);
        final second = await _runDocmdJson(['import', sourceFile.path, '--suffix', '--json']);
        final third = await _runDocmdJson(['import', sourceFile.path, '--suffix', '--json']);

        expect(first.exitCode, equals(0));
        expect(second.exitCode, equals(0));
        expect(third.exitCode, equals(0));

        expect(first.stdoutJson['packagePath'], endsWith('sample.docmd'));
        expect(second.stdoutJson['packagePath'], endsWith('sample-2.docmd'));
        expect(third.stdoutJson['packagePath'], endsWith('sample-3.docmd'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('rejects --overwrite together with --suffix', () async {
      final dir = Directory.systemTemp.createTempSync('docmd_import_conflict_');
      final sourceFile = File(p.join(dir.path, 'sample.md'))..writeAsStringSync('# Sample');

      try {
        final result = await _runDocmdJson([
          'import',
          sourceFile.path,
          '--overwrite',
          '--suffix',
          '--json',
        ]);

        expect(result.exitCode, equals(7));
        expect(result.stderrJson['error'], equals('VALIDATION_FAILED'));
        expect(result.stderrJson['message'], contains('Choose either --overwrite or --suffix'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}

Future<_JsonRunResult> _runDocmdJson(List<String> args) async {
  final stdoutController = StreamController<List<int>>();
  final stderrController = StreamController<List<int>>();
  final stdoutBytes = <int>[];
  final stderrBytes = <int>[];

  stdoutController.stream.listen(stdoutBytes.addAll);
  stderrController.stream.listen(stderrBytes.addAll);

  final stdoutSink = IOSink(stdoutController.sink);
  final stderrSink = IOSink(stderrController.sink);

  try {
    final exitCode = await runDocmd(args, stdout: stdoutSink, stderr: stderrSink);

    await stdoutSink.flush();
    await stderrSink.flush();
    await stdoutSink.close();
    await stderrSink.close();

    final stdoutText = utf8.decode(stdoutBytes).trim();
    final stderrText = utf8.decode(stderrBytes).trim();

    return _JsonRunResult(
      exitCode: exitCode,
      stdoutJson: stdoutText.isEmpty ? const {} : jsonDecode(stdoutText) as Map<String, dynamic>,
      stderrJson: stderrText.isEmpty ? const {} : jsonDecode(stderrText) as Map<String, dynamic>,
    );
  } finally {
    await stdoutController.close();
    await stderrController.close();
  }
}

class _JsonRunResult {
  _JsonRunResult({
    required this.exitCode,
    required this.stdoutJson,
    required this.stderrJson,
  });

  final int exitCode;
  final Map<String, dynamic> stdoutJson;
  final Map<String, dynamic> stderrJson;
}