library;

import 'dart:io';

import '../package_layout.dart';

/// Outcome of populating a package's canonical content from a source document.
class IngestionResult {
  /// Import status recorded in the manifest:
  /// `copied` | `converted` | `package-only`.
  final String status;

  const IngestionResult(this.status);
}

/// A pluggable engine that ingests one or more source formats into a DocMD
/// package's canonical Markdown (and assets).
///
/// Backends are selected by source format through [IngestionRegistry]. Adding a
/// new engine (e.g. docling for PDF) means implementing this interface and
/// registering it — no changes to the import command flow.
abstract interface class IngestionBackend {
  /// Stable identifier recorded for provenance, e.g. `pandoc`, `passthrough`.
  String get engineId;

  /// Source formats this backend handles, as lowercase extensions without a
  /// leading dot (e.g. `docx`).
  Set<String> get formats;

  /// Whether the underlying toolchain is present on this machine. Backends with
  /// no external dependency return `true`.
  bool isAvailable();

  /// Whether this backend is a guaranteed last-resort for its formats, used when
  /// no real engine is available (e.g. the placeholder writer). Selection prefers
  /// available real backends and only falls back to a fallback backend.
  bool get isFallback;

  /// Populate [layout]'s canonical document (and assets) from [source], which
  /// has the given lowercase [format] (no leading dot).
  Future<IngestionResult> ingest({
    required File source,
    required String format,
    required DocmdPackageLayout layout,
  });
}
