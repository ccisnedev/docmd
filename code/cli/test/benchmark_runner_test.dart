import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:docmd_cli/src/benchmark/benchmark_runner.dart';

void main() {
  group('BenchmarkRunner', () {
    late Directory dir;
    late File docA;
    late File docB;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('docmd_bench_test_');
      docA = File(p.join(dir.path, 'a.pdf'))..writeAsStringSync('stub');
      docB = File(p.join(dir.path, 'b.pdf'))..writeAsStringSync('stub');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('aggregates per-engine coverage across the corpus', () async {
      final runner = BenchmarkRunner({
        'rich': (source) async =>
            '# ${p.basename(source.path)}\n\nalpha beta gamma delta\n\n![x](y.png)\n',
        'sparse': (source) async => 'alpha\n',
      });

      final report = await runner.run([docA, docB]);

      final rich =
          report.summaries.firstWhere((s) => s.engineId == 'rich');
      final sparse =
          report.summaries.firstWhere((s) => s.engineId == 'sparse');

      expect(rich.documents, equals(2));
      expect(rich.meanImages, equals(1.0));
      expect(rich.meanWords, greaterThan(sparse.meanWords));
      expect(sparse.meanImages, equals(0.0));
    });

    test('measures recall against a reference engine', () async {
      final runner = BenchmarkRunner({
        'reference': (source) async => 'alpha beta gamma delta',
        'partial': (source) async => 'alpha beta',
      });

      final report = await runner.run([docA], referenceEngine: 'reference');

      final reference =
          report.summaries.firstWhere((s) => s.engineId == 'reference');
      final partial =
          report.summaries.firstWhere((s) => s.engineId == 'partial');

      expect(reference.meanRecall, equals(1.0));
      expect(partial.meanRecall, equals(0.5));
      expect(report.referenceEngine, equals('reference'));
    });

    test('records engine failures as skips instead of dropping them', () async {
      final runner = BenchmarkRunner({
        'ok': (source) async => 'alpha beta',
        'broken': (source) async => throw StateError('engine not installed'),
      });

      final report = await runner.run([docA, docB]);

      final broken =
          report.summaries.firstWhere((s) => s.engineId == 'broken');
      expect(broken.documents, equals(0));
      expect(broken.failures, equals(2));
      expect(report.skipped, hasLength(2));
      expect(report.skipped.first.error, contains('not installed'));
    });
  });
}
