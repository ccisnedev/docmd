library;

import 'dart:io';

import '../package_layout.dart';
import 'ingestion_backend.dart';

/// Copies Markdown sources into the package verbatim. No external tool.
class MarkdownPassthroughBackend implements IngestionBackend {
  @override
  String get engineId => 'passthrough';

  @override
  Set<String> get formats => const {'md', 'markdown'};

  @override
  bool isAvailable() => true;

  @override
  bool get isFallback => false;

  @override
  Future<IngestionResult> ingest({
    required File source,
    required String format,
    required DocmdPackageLayout layout,
  }) async {
    source.copySync(layout.canonicalDocumentPath);
    return const IngestionResult('copied');
  }
}
