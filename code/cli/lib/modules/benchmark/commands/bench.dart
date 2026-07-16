library;

import 'dart:io';

import 'package:cli_router/cli_router.dart';
import 'package:modular_cli_sdk/modular_cli_sdk.dart';
import 'package:path/path.dart' as p;

import '../../../src/benchmark/benchmark_runner.dart';
import '../../../src/benchmark/ingestion_engines.dart';
import '../../../src/ingestion/ingestion_registry.dart';

class BenchInput extends Input {
  final String corpusPath;
  final String? referenceEngine;

  BenchInput({required this.corpusPath, this.referenceEngine});

  factory BenchInput.fromCliRequest(CliRequest req) {
    final reference = req.flagString('reference')?.trim();
    return BenchInput(
      corpusPath: req.params['corpus'] ?? '',
      referenceEngine:
          reference == null || reference.isEmpty ? null : reference,
    );
  }

  static final List<CliParam> params = [
    CliParam.positional(
      'corpus',
      description: 'Directory of source documents to benchmark',
    ),
    CliParam.string(
      'reference',
      description: 'Engine id to measure text recall against (e.g. docling)',
    ),
  ];

  @override
  List<CliParam> get schemaFields => params;

  @override
  Map<String, dynamic> toJson() => {
    'corpusPath': corpusPath,
    'referenceEngine': referenceEngine,
  };
}

class BenchOutput extends Output {
  final BenchmarkReport report;
  final List<String> engineIds;

  BenchOutput({required this.report, required this.engineIds});

  @override
  Map<String, dynamic> toJson() => {
    'engines': engineIds,
    ...report.toJson(),
  };

  @override
  int get exitCode => ExitCode.ok;

  @override
  String toText() {
    final lines = <String>[
      'DocMD ingestion benchmark',
      '  engines: ${engineIds.join(', ')}',
      if (report.referenceEngine != null)
        '  reference: ${report.referenceEngine}',
      '',
    ];

    for (final summary in report.summaries) {
      final recall = summary.meanRecall == null
          ? ''
          : ', recall ${(summary.meanRecall! * 100).toStringAsFixed(0)}%';
      lines.add(
        '  ${summary.engineId}: '
        '${summary.documents} docs, '
        '${summary.failures} failed, '
        'words ${summary.meanWords.toStringAsFixed(0)}, '
        'tables ${summary.meanTables.toStringAsFixed(1)}, '
        'images ${summary.meanImages.toStringAsFixed(1)}$recall',
      );
    }

    if (report.skipped.isNotEmpty) {
      lines.add('');
      lines.add('Skipped (engine unavailable or failed):');
      for (final cell in report.skipped) {
        lines.add('  ${cell.engineId} on ${cell.source}: ${cell.error}');
      }
    }

    return lines.join('\n');
  }
}

class BenchCommand implements Command<BenchInput, BenchOutput> {
  @override
  final BenchInput input;
  final Map<String, IngestionEngine> _engines;

  BenchCommand(this.input, {Map<String, IngestionEngine>? engines})
    : _engines = engines ?? buildBenchmarkEngines();

  @override
  String? validate() {
    if (input.corpusPath.isEmpty) {
      return 'Corpus directory required. Use: docmd bench <corpus>';
    }
    if (!Directory(input.corpusPath).existsSync()) {
      return 'Corpus directory not found: ${input.corpusPath}';
    }
    if (input.referenceEngine != null &&
        !_engines.containsKey(input.referenceEngine)) {
      return 'Reference engine "${input.referenceEngine}" is not available. '
          'Available: ${_engines.keys.join(', ')}';
    }
    return null;
  }

  @override
  Future<BenchOutput> execute() async {
    final supported =
        IngestionRegistry.defaults().supportedFormats;
    final corpus = Directory(input.corpusPath)
        .listSync()
        .whereType<File>()
        .where((file) => supported.contains(
              p.extension(file.path).toLowerCase().replaceFirst('.', ''),
            ))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final report = await BenchmarkRunner(_engines).run(
      corpus,
      referenceEngine: input.referenceEngine,
    );

    return BenchOutput(report: report, engineIds: _engines.keys.toList());
  }
}
