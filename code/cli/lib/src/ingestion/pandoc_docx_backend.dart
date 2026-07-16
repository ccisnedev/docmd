library;

import 'dart:io';

import '../package_layout.dart';
import '../process_runner.dart';
import '../tool_locator.dart';
import 'ingestion_backend.dart';

/// Converts `.docx` sources to GitHub-flavored Markdown via Pandoc, extracting
/// media into the package's assets directory and rewriting asset references so
/// they resolve from `content/document.md`.
class PandocDocxBackend implements IngestionBackend {
  final ProcessRunner _runProcess;
  final bool Function() _isAvailable;

  PandocDocxBackend({ProcessRunner? processRunner, bool Function()? isAvailable})
    : _runProcess = processRunner ?? runProcess,
      _isAvailable =
          isAvailable ?? (() => resolvePandocExecutable() != null);

  @override
  String get engineId => 'pandoc';

  @override
  Set<String> get formats => const {'docx'};

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
    final result = await _runProcess('pandoc', [
      source.path,
      '-t',
      'gfm',
      '--wrap=none',
      '--extract-media=${layout.assetsDirPath}',
      '-o',
      layout.canonicalDocumentPath,
    ]);

    if (result.exitCode != 0) {
      throw ProcessException(
        'pandoc',
        [],
        'Pandoc import failed with exit code ${result.exitCode}: ${result.stderr}',
        result.exitCode,
      );
    }

    _normalizeAssetReferences(layout.canonicalDocumentPath);
    return const IngestionResult('converted');
  }

  void _normalizeAssetReferences(String markdownPath) {
    final file = File(markdownPath);
    if (!file.existsSync()) {
      return;
    }

    final content = file.readAsStringSync();
    final normalized = content
        .replaceAll('(assets/', '(../assets/')
        .replaceAll('="assets/', '="../assets/')
        .replaceAll("='assets/", "='../assets/");

    if (normalized != content) {
      file.writeAsStringSync(normalized);
    }
  }
}
