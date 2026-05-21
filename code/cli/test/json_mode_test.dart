import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:docmd_cli/docmd_cli.dart';

void main() {
  group('JSON mode', () {
    test('import command emits machine-readable JSON when --json is placed at the end', () async {
      final dir = Directory.systemTemp.createTempSync('docmd_json_mode_test_');
      final sourceFile = File('${dir.path}/sample.md')..writeAsStringSync('# Sample');

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
          ['import', sourceFile.path, '--json'],
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
        expect(json['status'], equals('copied'));
        expect(json['canonicalDocumentPath'], endsWith('document.md'));
        expect(json['packagePath'], endsWith('sample.docmd'));
      } finally {
        await stdoutController.close();
        await stderrController.close();
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      }
    });
  });
}