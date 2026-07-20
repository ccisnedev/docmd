# Changelog

## 0.2.0 — 2026-07-20

Repositions DocMD as an ultralight LLM-ingestion tool: import needs no Python and
nothing heavy to install. PDF and PPTX are read directly in pure Dart; only Pandoc
(docx + all render) and LibreOffice (PDF render) remain, both single, well-behaved
binaries.

### Added

- **Native pure-Dart PDF import**, replacing the Python engines. It recovers the
  text layer (glyph codes → Unicode via each font's `/ToUnicode` CMap, detecting 1-
  vs 2-byte code width) and extracts embedded JPEG images, referencing them like
  every other format. No OCR and no page rasterization by design: a scan or vector
  page has no recoverable text layer and is left to a downstream vision model.
  Unsupported image encodings are noted in the document rather than dropped silently.
- **`render --pptx`** — Markdown to PowerPoint via Pandoc's native writer. Render now
  targets docx, pptx, and pdf.

### Removed

- **markitdown and docling** as PDF import engines, and everything that provisioned
  them: `docmd setup` no longer installs uv/docling/markitdown, and `doctor` no
  longer reports them. `docmd setup` now provisions only pandoc and libreoffice.
  (The `bench` command keeps them as optional external comparators when present, so
  `docmd vs markitdown` can still be measured — a benchmark baseline, not a runtime
  dependency.)

### Notes

- `import pdf` and `import pptx` are always available now — pure Dart, nothing to
  install, so nothing to be missing.
- Still deferred: XLSX import (placeholder, original preserved); PDF images in
  non-JPEG encodings (reported, not yet re-encoded to PNG); OCR/scanned-page
  rasterization (left to the model).

## 0.1.0 — 2026-07-17

Makes the CLI functional for everything it advertises, verified end to end against a
real corpus (docx, pdf, pptx). Full analysis in `docs/qa/2026-07-17-qa-analysis.md`.

### Added

- **Native PPTX import.** Decks are read directly from their OOXML package — no
  external engine — giving each slide a `## Slide N` section with its text and images
  in on-slide order. Slide order follows `presentation.xml`, not file names; parts are
  decoded as UTF-8 so accented text is preserved. `import pptx` reports as
  `available (docmd)`.
- **Media fidelity reporting on import.** Import now reports media extracted vs
  referenced and warns about orphaned files that no render would include.
- **`docmd setup <tool>`.** Each tool (pandoc, libreoffice, uv, docling, markitdown)
  is a capability of its own, and `--force` reinstalls a present-but-broken tool.

### Fixed

- **Tools reported available now actually run.** Resolution verified a tool by
  presence on PATH alone, so a stale Python shim shadowed a working install and
  `doctor` reported `import pdf: available` on a machine where every invocation
  crashed. Resolution now probes Python console-scripts for real, and backends
  execute the resolved path instead of the bare name.
- **DOCX packages are portable and keep their images.** `--extract-media` no longer
  bakes host-absolute paths into the canonical document, and raw `<img>` tags (which
  pandoc's docx writer silently drops) are rewritten to Markdown image syntax, so the
  round trip no longer loses every image.
- **Engine failures surface as errors, not crashes.** A failing tool is now reported
  through the error envelope (exit 2) instead of a Dart stack trace and exit 255.
- **`setup pdf` provisions the whole PDF toolchain**, markitdown included.

### Changed

- **Removed `render --pptx` / `--xlsx`.** They parsed and then always failed with
  "Unsupported output format"; the help no longer advertises renderers that do not
  exist. (Breaking, but neither flag ever succeeded.)

### Known gaps

- XLSX import remains a placeholder; the original is preserved in `assets/original/`.
- `upgrade` still calls `Process.run` directly in a few places, outside the injected
  process runner; those paths are not yet covered by tests.
