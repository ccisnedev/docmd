import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:docmd_cli/docmd_cli.dart';

/// Runs [args] through the real [runDocmd] entry point and captures both
/// streams, exactly as the VS Code extension's `DocmdCli.run` does.
Future<({int exitCode, String stdout, String stderr})> _run(
  List<String> args, {
  Map<String, String>? environment,
}) async {
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
      args,
      stdout: stdoutSink,
      stderr: stderrSink,
      environment: environment,
    );

    await stdoutSink.flush();
    await stderrSink.flush();
    await stdoutSink.close();
    await stderrSink.close();

    return (
      exitCode: exitCode,
      stdout: utf8.decode(stdoutBytes).trim(),
      stderr: utf8.decode(stderrBytes).trim(),
    );
  } finally {
    await stdoutController.close();
    await stderrController.close();
  }
}

Map<String, dynamic> _decode(String text) =>
    jsonDecode(text) as Map<String, dynamic>;

void main() {
  group('VS Code extension argument order (cli_router 0.2.0 compatibility)', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('docmd_vscode_args_test_');
    });

    tearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });

    test(
      'import with output-dir and overwrite: options before the operand is accepted',
      () async {
        final sourceFile = File('${dir.path}/sample.md')
          ..writeAsStringSync('# Sample');
        final outputDir = Directory('${dir.path}/out')..createSync();

        final result = await _run([
          'import',
          '--output-dir',
          outputDir.path,
          '--overwrite',
          '--json',
          sourceFile.path,
        ]);

        expect(result.exitCode, equals(0));
        expect(_decode(result.stdout)['status'], equals('copied'));
      },
    );

    test(
      'import with suffix: options before the operand is accepted',
      () async {
        final sourceFile = File('${dir.path}/sample.md')
          ..writeAsStringSync('# Sample');

        final result = await _run([
          'import',
          '--suffix',
          '--json',
          sourceFile.path,
        ]);

        expect(result.exitCode, equals(0));
        expect(_decode(result.stdout)['status'], equals('copied'));
      },
    );

    test(
      'import with the old order (operand before options) is accepted by '
      'default: cli_router 0.2.1 permutes options after an operand unless '
      'POSIXLY_CORRECT is set',
      () async {
        final sourceFile = File('${dir.path}/sample.md')
          ..writeAsStringSync('# Sample');

        final result = await _run([
          'import',
          sourceFile.path,
          '--overwrite',
          '--json',
        ]);

        expect(result.exitCode, equals(0));
        expect(_decode(result.stdout)['status'], equals('copied'));
      },
    );

    test(
      'import with the old order (operand before options) is rejected as '
      'misplaced-option in strict mode (POSIXLY_CORRECT)',
      () async {
        final sourceFile = File('${dir.path}/sample.md')
          ..writeAsStringSync('# Sample');

        final result = await _run([
          'import',
          sourceFile.path,
          '--overwrite',
          '--json',
        ], environment: const {'POSIXLY_CORRECT': '1'});

        expect(result.exitCode, isNot(equals(0)));
        expect(result.stderr, contains('[misplaced-option]'));
      },
    );

    test('render docx: --json before the operand routes past parsing, '
        'reaching a missing-input error rather than real conversion', () async {
      // A missing input, not a real Markdown file: this only needs to
      // prove cli_router accepted the argument order and dispatched to
      // the render query. RenderCommand.validate() runs before execute(),
      // so a missing path is rejected before Pandoc is ever invoked, and
      // the test needs neither Pandoc nor LibreOffice installed. Actual
      // conversion is exercised by real_document_integration_test.dart,
      // which is guarded on both tools being present.
      final missingFile = '${dir.path}/missing.md';

      final result = await _run(['render', '--json', missingFile]);

      expect(result.stderr, isNot(contains('[misplaced-option]')));
      final error = _decode(result.stderr)['error'] as Map<String, dynamic>;
      expect(error['id'], equals('validation-failed'));
      expect(error['message'], contains('Input path not found'));
      expect(result.exitCode, equals(7));
    });

    test(
      'render --pdf: options before the operand parses past routing, unlike the old order',
      () async {
        final missingFile = '${dir.path}/missing.md';

        final result = await _run(['render', '--pdf', '--json', missingFile]);

        // Whether this machine has LibreOffice installed to actually
        // produce a PDF is not this test's concern, and neither is Pandoc:
        // RenderCommand.validate() rejects the missing input before
        // execute() ever runs either tool, so this only exercises that
        // cli_router accepted the argument order and dispatched to render,
        // rather than rejecting it as misplaced-option.
        expect(result.stderr, isNot(contains('[misplaced-option]')));
        final error = _decode(result.stderr)['error'] as Map<String, dynamic>;
        expect(error['id'], equals('validation-failed'));
        expect(error['message'], contains('Input path not found'));
        expect(result.exitCode, equals(7));
      },
    );

    test(
      'render with the old order (operand before --pdf) is accepted by '
      'default: cli_router 0.2.1 permutes an option after its operand '
      'unless POSIXLY_CORRECT is set',
      () async {
        final missingFile = '${dir.path}/missing.md';

        final result = await _run(['render', missingFile, '--pdf', '--json']);

        // Same routing question as the "options first" cases above: the
        // permuted invocation is dispatched, not rejected, and reaches the
        // same missing-input validation error.
        expect(result.stderr, isNot(contains('[misplaced-option]')));
        final error = _decode(result.stderr)['error'] as Map<String, dynamic>;
        expect(error['id'], equals('validation-failed'));
        expect(result.exitCode, equals(7));
      },
    );

    test(
      'render with the old order (operand before --pdf) is rejected as '
      'misplaced-option in strict mode (POSIXLY_CORRECT)',
      () async {
        final sourceFile = File('${dir.path}/sample.md')
          ..writeAsStringSync('# Sample');

        final result = await _run([
          'render',
          sourceFile.path,
          '--pdf',
          '--json',
        ], environment: const {'POSIXLY_CORRECT': '1'});

        expect(result.exitCode, isNot(equals(0)));
        expect(result.stderr, contains('[misplaced-option]'));
      },
    );

    test(
      'doctor: the operand-free invocation is unaffected by option order',
      () async {
        final result = await _run(['doctor', '--json']);

        final json = _decode(
          result.stdout.isNotEmpty ? result.stdout : result.stderr,
        );
        expect(json['checks'] ?? json['error']?['checks'], isNotNull);
      },
    );
  });
}
