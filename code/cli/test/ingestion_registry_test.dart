import 'package:test/test.dart';

import 'package:docmd_cli/src/ingestion/ingestion_registry.dart';
import 'package:docmd_cli/src/ingestion/markdown_passthrough_backend.dart';
import 'package:docmd_cli/src/ingestion/pandoc_docx_backend.dart';
import 'package:docmd_cli/src/ingestion/pdf_backend.dart';
import 'package:docmd_cli/src/ingestion/placeholder_backend.dart';
import 'package:docmd_cli/src/ingestion/pptx_backend.dart';

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

    test('routes pdf to the native pure-Dart backend', () {
      expect(registry.backendFor('pdf'), isA<PdfIngestionBackend>());
    });

    test('routes pptx to the native OOXML backend', () {
      expect(registry.backendFor('pptx'), isA<PptxIngestionBackend>());
    });

    test('routes xlsx to the placeholder backend', () {
      // No xlsx engine yet; the placeholder keeps the original recoverable.
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

  group('IngestionRegistry backend selection', () {
    test('prefers an available real backend over the fallback', () {
      final registry = IngestionRegistry([
        PandocDocxBackend(isAvailable: () => true),
        PlaceholderIngestionBackend(),
      ]);
      expect(registry.backendFor('docx'), isA<PandocDocxBackend>());
    });

    test('picks the first candidate when none is available and none is a fallback', () {
      final registry = IngestionRegistry([
        PandocDocxBackend(isAvailable: () => false),
      ]);
      // No placeholder registered: return the preferred candidate so the caller
      // surfaces a precise engine-unavailable error, not "unsupported format".
      expect(registry.backendFor('docx'), isA<PandocDocxBackend>());
    });
  });
}
