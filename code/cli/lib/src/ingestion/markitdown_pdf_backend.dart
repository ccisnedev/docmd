library;

import 'dart:io';

import '../package_layout.dart';
import '../process_runner.dart';
import '../tool_locator.dart';
import 'ingestion_backend.dart';

/// Ingests PDF into Markdown using Microsoft markitdown — the lightweight PDF
/// fallback when docling is not installed.
///
/// markitdown's PDF path is text-only (no image extraction), so it trades image
/// fidelity for a small, fast dependency. It writes Markdown straight to the
/// output file via `-o`, so no post-processing is needed.
class MarkitdownPdfBackend implements IngestionBackend {
  final ProcessRunner _runProcess;
  final bool Function() _isAvailable;

  MarkitdownPdfBackend({
    ProcessRunner? processRunner,
    bool Function()? isAvailable,
  }) : _runProcess = processRunner ?? runProcess,
       _isAvailable =
           isAvailable ?? (() => resolveMarkitdownExecutable() != null);

  @override
  String get engineId => 'markitdown';

  @override
  Set<String> get formats => const {'pdf'};

  @override
  bool isAvailable() => _isAvailable();

  @override
  bool get isFallback => false;

  @override
  Future<IngestionResult> ingest({
    required File source,
    required String format,
    required DocmdPackageLayout layout,
  }) async {
    final result = await _runProcess('markitdown', [
      source.path,
      '-o',
      layout.canonicalDocumentPath,
    ]);

    if (result.exitCode != 0) {
      throw ProcessException(
        'markitdown',
        [],
        'markitdown import failed with exit code ${result.exitCode}: ${result.stderr}',
        result.exitCode,
      );
    }

    return const IngestionResult('converted');
  }
}
