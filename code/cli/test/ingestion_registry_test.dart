import 'package:test/test.dart';

import 'package:docmd_cli/src/ingestion/docling_pdf_backend.dart';
import 'package:docmd_cli/src/ingestion/ingestion_registry.dart';
import 'package:docmd_cli/src/ingestion/markdown_passthrough_backend.dart';
import 'package:docmd_cli/src/ingestion/markitdown_pdf_backend.dart';
import 'package:docmd_cli/src/ingestion/pandoc_docx_backend.dart';
import 'package:docmd_cli/src/ingestion/placeholder_backend.dart';

void main() {
  group('IngestionRegistry.defaults', () {
    final registry = IngestionRegistry.defaults();

    test('routes markdown to the passthrough backend', () {
      expect(registry.backendFor('md'), isA<MarkdownPassthroughBackend>());
      expect(registry.backendFor('markdown'), isA<MarkdownPassthroughBackend>());
    });

    test('routes docx to the pandoc backend', () {
      expect(registry.backendFor('docx'), isA<PandocDocxBackend>());
    });

    test('routes pptx and xlsx to the placeholder backend', () {
      expect(registry.backendFor('pptx'), isA<PlaceholderIngestionBackend>());
      expect(registry.backendFor('xlsx'), isA<PlaceholderIngestionBackend>());
    });

    test('returns null for an unknown format', () {
      expect(registry.backendFor('rtf'), isNull);
    });

    test('exposes every supported format', () {
      expect(
        registry.supportedFormats,
        equals({'md', 'markdown', 'docx', 'pdf', 'pptx', 'xlsx'}),
      );
    });

    test('passthrough is always available; placeholder never is', () {
      expect(MarkdownPassthroughBackend().isAvailable(), isTrue);
      expect(PlaceholderIngestionBackend().isAvailable(), isFalse);
    });

    test('pandoc backend availability is injectable', () {
      expect(
        PandocDocxBackend(isAvailable: () => false).isAvailable(),
        isFalse,
      );
      expect(
        PandocDocxBackend(isAvailable: () => true).isAvailable(),
        isTrue,
      );
    });
  });

  group('IngestionRegistry PDF engine selection', () {
    IngestionRegistry pdfRegistry({
      required bool docling,
      required bool markitdown,
    }) {
      return IngestionRegistry([
        MarkdownPassthroughBackend(),
        DoclingPdfBackend(isAvailable: () => docling),
        MarkitdownPdfBackend(isAvailable: () => markitdown),
        PlaceholderIngestionBackend(),
      ]);
    }

    test('prefers docling when it is available', () {
      final backend =
          pdfRegistry(docling: true, markitdown: true).backendFor('pdf');
      expect(backend, isA<DoclingPdfBackend>());
    });

    test('falls back to markitdown when only markitdown is available', () {
      final backend =
          pdfRegistry(docling: false, markitdown: true).backendFor('pdf');
      expect(backend, isA<MarkitdownPdfBackend>());
    });

    test('falls back to the placeholder when no PDF engine is available', () {
      final backend =
          pdfRegistry(docling: false, markitdown: false).backendFor('pdf');
      expect(backend, isA<PlaceholderIngestionBackend>());
    });

    test('picks the first candidate when none is available and none is a fallback', () {
      final registry = IngestionRegistry([
        DoclingPdfBackend(isAvailable: () => false),
        MarkitdownPdfBackend(isAvailable: () => false),
      ]);
      // No placeholder registered: return the preferred candidate so the caller
      // surfaces a precise engine-unavailable error, not "unsupported format".
      expect(registry.backendFor('pdf'), isA<DoclingPdfBackend>());
    });
  });
}
