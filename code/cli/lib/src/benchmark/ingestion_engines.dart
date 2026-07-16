library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../ingestion/ingestion_registry.dart';
import '../package_layout.dart';
import '../process_runner.dart';
import '../tool_locator.dart';
import 'benchmark_runner.dart';

/// Builds the ingestion engines to benchmark on this machine.
///
/// `docmd` (the orchestrated pipeline) is always included; the raw `docling`
/// and `markitdown` baselines are included only when their toolchain is
/// present. Availability and the process runner are injectable so the set can
/// be exercised in tests without any engine installed.
Map<String, IngestionEngine> buildBenchmarkEngines({
  ProcessRunner? processRunner,
  bool Function()? hasDocling,
  bool Function()? hasMarkitdown,
}) {
  final runProc = processRunner ?? runProcess;
  final doclingAvailable =
      (hasDocling ?? () => resolveDoclingExecutable() != null)();
  final markitdownAvailable =
      (hasMarkitdown ?? () => resolveMarkitdownExecutable() != null)();

  final engines = <String, IngestionEngine>{
    'docmd': (source) => _ingestWithDocmd(source, processRunner: processRunner),
  };
  if (doclingAvailable) {
    engines['docling'] = (source) => _ingestWithDocling(source, runProc);
  }
  if (markitdownAvailable) {
    engines['markitdown'] = (source) => _ingestWithMarkitdown(source, runProc);
  }
  return engines;
}

/// Ingests through DocMD's orchestrated registry (the pipeline under test).
Future<String> _ingestWithDocmd(
  File source, {
  ProcessRunner? processRunner,
}) async {
  final tempDir = Directory.systemTemp.createTempSync('docmd_bench_docmd_');
  try {
    final layout = DocmdPackageLayout(p.join(tempDir.path, 'bench.docmd'))
      ..createSkeleton();
    final format =
        p.extension(source.path).toLowerCase().replaceFirst('.', '');
    final backend =
        IngestionRegistry.defaults(processRunner: processRunner)
            .backendFor(format);
    if (backend == null) {
      throw StateError('docmd cannot ingest .$format');
    }
    await backend.ingest(source: source, format: format, layout: layout);
    return File(layout.canonicalDocumentPath).readAsStringSync();
  } finally {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  }
}

/// Raw docling baseline: convert to Markdown in a temp dir and read it back.
Future<String> _ingestWithDocling(File source, ProcessRunner runProc) async {
  final tempDir = Directory.systemTemp.createTempSync('docmd_bench_docling_');
  try {
    final result = await runProc('docling', [
      source.path,
      '--to',
      'md',
      '--output',
      tempDir.path,
    ]);
    if (result.exitCode != 0) {
      throw ProcessException('docling', [], '${result.stderr}', result.exitCode);
    }
    final md = tempDir
        .listSync()
        .whereType<File>()
        .firstWhere((f) => p.extension(f.path).toLowerCase() == '.md');
    return md.readAsStringSync();
  } finally {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  }
}

/// Raw markitdown baseline: convert straight to a temp Markdown file.
Future<String> _ingestWithMarkitdown(File source, ProcessRunner runProc) async {
  final tempDir = Directory.systemTemp.createTempSync('docmd_bench_markitdown_');
  final outputPath = p.join(tempDir.path, 'out.md');
  try {
    final result = await runProc('markitdown', [source.path, '-o', outputPath]);
    if (result.exitCode != 0) {
      throw ProcessException(
        'markitdown',
        [],
        '${result.stderr}',
        result.exitCode,
      );
    }
    return File(outputPath).readAsStringSync();
  } finally {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  }
}
