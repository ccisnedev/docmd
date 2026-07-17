library;

import '../process_runner.dart';
import 'docling_pdf_backend.dart';
import 'ingestion_backend.dart';
import 'markdown_passthrough_backend.dart';
import 'markitdown_pdf_backend.dart';
import 'pandoc_docx_backend.dart';
import 'placeholder_backend.dart';
import 'pptx_backend.dart';

/// Selects an [IngestionBackend] by source format.
///
/// Backend order encodes per-format precedence. For a given format the registry
/// prefers the first *available* backend in registration order, so per-format
/// engine defaults are configured by ordering (e.g. docling before markitdown
/// for PDF). If no real backend is available it falls back to a
/// [IngestionBackend.isFallback] backend (the placeholder) when one is
/// registered, otherwise to the first candidate so callers surface a precise
/// "engine unavailable" error rather than "unsupported format".
class IngestionRegistry {
  final List<IngestionBackend> backends;

  IngestionRegistry(this.backends);

  /// The default engine matrix: Markdown passthrough; Pandoc for `.docx`;
  /// docling (default) then markitdown (fallback) for `.pdf`; the native OOXML
  /// reader for `.pptx`; and a placeholder for formats without a real engine yet
  /// (xlsx) or PDF with no engine installed.
  factory IngestionRegistry.defaults({ProcessRunner? processRunner}) {
    return IngestionRegistry([
      MarkdownPassthroughBackend(),
      PandocDocxBackend(processRunner: processRunner),
      DoclingPdfBackend(processRunner: processRunner),
      MarkitdownPdfBackend(processRunner: processRunner),
      PptxIngestionBackend(),
      PlaceholderIngestionBackend(),
    ]);
  }

  /// The backend that handles [format] (lowercase, no leading dot), or `null`.
  IngestionBackend? backendFor(String format) {
    final candidates =
        backends.where((backend) => backend.formats.contains(format)).toList();
    if (candidates.isEmpty) {
      return null;
    }
    for (final backend in candidates) {
      if (backend.isAvailable()) {
        return backend;
      }
    }
    for (final backend in candidates) {
      if (backend.isFallback) {
        return backend;
      }
    }
    return candidates.first;
  }

  /// Every source format the registry can route, across all backends.
  Set<String> get supportedFormats =>
      {for (final backend in backends) ...backend.formats};
}
