# Changelog

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
