library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'metrics.dart';

/// Ingests [source] into Markdown. Throws when the engine is unavailable or
/// fails, so the runner can record the gap instead of silently dropping it.
typedef IngestionEngine = Future<String> Function(File source);

/// One engine's result for one corpus document.
class BenchmarkCell {
  final String engineId;
  final String source;
  final IngestionMetrics? metrics;
  final double? recall;
  final String? error;

  const BenchmarkCell({
    required this.engineId,
    required this.source,
    this.metrics,
    this.recall,
    this.error,
  });

  bool get ok => error == null;

  Map<String, dynamic> toJson() => {
    'engine': engineId,
    'source': source,
    if (metrics != null) 'metrics': metrics!.toJson(),
    if (recall != null) 'recall': recall,
    if (error != null) 'error': error,
  };
}

/// Aggregate coverage for one engine across the corpus.
class EngineSummary {
  final String engineId;
  final int documents;
  final int failures;
  final double meanWords;
  final double meanHeadings;
  final double meanTables;
  final double meanImages;
  final double? meanRecall;

  const EngineSummary({
    required this.engineId,
    required this.documents,
    required this.failures,
    required this.meanWords,
    required this.meanHeadings,
    required this.meanTables,
    required this.meanImages,
    this.meanRecall,
  });

  Map<String, dynamic> toJson() => {
    'engine': engineId,
    'documents': documents,
    'failures': failures,
    'meanWords': meanWords,
    'meanHeadings': meanHeadings,
    'meanTables': meanTables,
    'meanImages': meanImages,
    if (meanRecall != null) 'meanRecall': meanRecall,
  };
}

class BenchmarkReport {
  final List<BenchmarkCell> cells;
  final List<EngineSummary> summaries;
  final String? referenceEngine;

  const BenchmarkReport({
    required this.cells,
    required this.summaries,
    this.referenceEngine,
  });

  /// Cells that failed (engine unavailable or errored) — surfaced so coverage
  /// gaps are never hidden.
  List<BenchmarkCell> get skipped =>
      cells.where((cell) => !cell.ok).toList(growable: false);

  Map<String, dynamic> toJson() => {
    if (referenceEngine != null) 'referenceEngine': referenceEngine,
    'summaries': summaries.map((s) => s.toJson()).toList(),
    'cells': cells.map((c) => c.toJson()).toList(),
  };
}

/// Runs a set of ingestion engines over a shared corpus and measures how much
/// content each captures — the "viable alternative to markitdown/docling"
/// measure. Engines are injected, so the harness is testable without any
/// engine installed.
class BenchmarkRunner {
  /// Engine id → producer. Iteration order is preserved in the report.
  final Map<String, IngestionEngine> engines;

  BenchmarkRunner(this.engines);

  Future<BenchmarkReport> run(
    List<File> corpus, {
    String? referenceEngine,
  }) async {
    final cells = <BenchmarkCell>[];

    for (final source in corpus) {
      final sourceName = p.basename(source.path);

      // Produce every engine's Markdown for this document first, so recall can
      // be measured against the reference engine's output.
      final markdownByEngine = <String, String>{};
      final errorByEngine = <String, String>{};
      for (final entry in engines.entries) {
        try {
          markdownByEngine[entry.key] = await entry.value(source);
        } catch (error) {
          errorByEngine[entry.key] = error.toString();
        }
      }

      final referenceMarkdown =
          referenceEngine == null ? null : markdownByEngine[referenceEngine];

      for (final engineId in engines.keys) {
        final markdown = markdownByEngine[engineId];
        if (markdown == null) {
          cells.add(BenchmarkCell(
            engineId: engineId,
            source: sourceName,
            error: errorByEngine[engineId] ?? 'no output',
          ));
          continue;
        }
        cells.add(BenchmarkCell(
          engineId: engineId,
          source: sourceName,
          metrics: IngestionMetrics.fromMarkdown(markdown),
          recall: referenceMarkdown == null
              ? null
              : textRecall(referenceMarkdown, markdown),
        ));
      }
    }

    return BenchmarkReport(
      cells: cells,
      summaries: _summarize(cells, referenceEngine),
      referenceEngine: referenceEngine,
    );
  }

  List<EngineSummary> _summarize(
    List<BenchmarkCell> cells,
    String? referenceEngine,
  ) {
    final summaries = <EngineSummary>[];
    for (final engineId in engines.keys) {
      final engineCells =
          cells.where((cell) => cell.engineId == engineId).toList();
      final ok = engineCells.where((cell) => cell.ok).toList();
      final failures = engineCells.length - ok.length;

      double mean(num Function(BenchmarkCell) selector) {
        if (ok.isEmpty) return 0;
        final total = ok.fold<num>(0, (sum, cell) => sum + selector(cell));
        return total / ok.length;
      }

      final recallCells =
          ok.where((cell) => cell.recall != null).toList();
      final meanRecall = referenceEngine == null || recallCells.isEmpty
          ? null
          : recallCells.fold<double>(0, (sum, cell) => sum + cell.recall!) /
              recallCells.length;

      summaries.add(EngineSummary(
        engineId: engineId,
        documents: ok.length,
        failures: failures,
        meanWords: mean((c) => c.metrics!.words),
        meanHeadings: mean((c) => c.metrics!.headings),
        meanTables: mean((c) => c.metrics!.tables),
        meanImages: mean((c) => c.metrics!.images),
        meanRecall: meanRecall,
      ));
    }
    return summaries;
  }
}
