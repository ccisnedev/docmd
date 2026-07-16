import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:docmd_cli/modules/benchmark/commands/bench.dart';

void main() {
  group('BenchCommand', () {
    late Directory corpus;

    setUp(() {
      corpus = Directory.systemTemp.createTempSync('docmd_bench_cmd_');
      File(p.join(corpus.path, 'a.pdf')).writeAsStringSync('stub');
      File(p.join(corpus.path, 'b.docx')).writeAsStringSync('stub');
      // An unsupported file that must be ignored by the corpus scan.
      File(p.join(corpus.path, 'notes.txt')).writeAsStringSync('ignore me');
    });

    tearDown(() => corpus.deleteSync(recursive: true));

    test('validate() rejects a missing corpus directory', () {
      final cmd = BenchCommand(
        BenchInput(corpusPath: p.join(corpus.path, 'nope')),
        engines: {'docmd': (s) async => 'x'},
      );
      expect(cmd.validate(), contains('not found'));
    });

    test('validate() rejects an unavailable reference engine', () {
      final cmd = BenchCommand(
        BenchInput(corpusPath: corpus.path, referenceEngine: 'docling'),
        engines: {'docmd': (s) async => 'x'},
      );
      expect(cmd.validate(), contains('not available'));
    });

    test('benchmarks supported corpus files across injected engines', () async {
      final cmd = BenchCommand(
        BenchInput(corpusPath: corpus.path),
        engines: {
          'docmd': (source) async =>
              '# ${p.basename(source.path)}\n\nalpha beta gamma\n',
          'baseline': (source) async => 'alpha\n',
        },
      );

      final output = await cmd.execute();

      final docmd =
          output.report.summaries.firstWhere((s) => s.engineId == 'docmd');
      // Only a.pdf and b.docx are supported; notes.txt is ignored.
      expect(docmd.documents, equals(2));
      expect(output.engineIds, containsAll(<String>['docmd', 'baseline']));
      expect(output.toText(), contains('DocMD ingestion benchmark'));
    });

    test('reports recall when a reference engine is chosen', () async {
      final cmd = BenchCommand(
        BenchInput(corpusPath: corpus.path, referenceEngine: 'docmd'),
        engines: {
          'docmd': (source) async => 'alpha beta gamma delta',
          'partial': (source) async => 'alpha beta',
        },
      );

      final output = await cmd.execute();
      final partial =
          output.report.summaries.firstWhere((s) => s.engineId == 'partial');
      expect(partial.meanRecall, equals(0.5));
    });
  });
}
