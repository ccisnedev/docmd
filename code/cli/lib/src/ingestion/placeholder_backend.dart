library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../package_layout.dart';
import 'ingestion_backend.dart';

/// Fallback for formats without real semantic extraction yet (pdf, pptx, xlsx).
///
/// The original file is still preserved in `assets/original/` by the import
/// command; this backend only writes a placeholder canonical document. It is
/// [isAvailable] `false` because it does not deliver real ingestion — a signal
/// `docmd doctor` uses to report these capabilities as not-yet-available.
class PlaceholderIngestionBackend implements IngestionBackend {
  @override
  String get engineId => 'placeholder';

  @override
  Set<String> get formats => const {'pdf', 'pptx', 'xlsx'};

  @override
  bool isAvailable() => false;

  @override
  bool get isFallback => true;

  @override
  Future<IngestionResult> ingest({
    required File source,
    required String format,
    required DocmdPackageLayout layout,
  }) async {
    File(layout.canonicalDocumentPath).writeAsStringSync([
      '# Imported asset',
      '',
      'Original file: ${p.basename(source.path)}',
      '',
      'Source format: .$format',
      '',
      'The original file was copied into `assets/original/`.',
      'Semantic extraction for this format is not implemented yet.',
    ].join('\n'));
    return const IngestionResult('package-only');
  }
}
