# Changelog

## 0.2.4 — 2026-09-29

### Changed

- **Upgraded `modular_cli_sdk` to ^0.8.1** (from ^0.8.0, itself bumped from
  ^0.7.0 earlier in this cycle) **and `cli_router` to ^0.2.1** (from ^0.2.0).
  `cli_router` 0.2.1 permutes an option that follows its operand by default
  (`docmd import file.md --overwrite` now works); the previous strict
  rejection (`misplaced-option`) only applies when `POSIXLY_CORRECT` is set
  in the environment. `ModularCli.run` gained an optional `environment`
  parameter for this, forwarded from docmd's own `runDocmd` entry point, so
  a caller such as the VS Code extension can opt into strict ordering when
  it needs to.
- **Replaced docmd's own hand rolled `upgrade` and `uninstall` commands with
  `modular_cli_sdk`'s `InstallationPlugin`** (its `alias` became optional in
  0.8.1, which is what makes this possible for a CLI like docmd that has
  never had one). Two small custom steps, wired through the plugin's own
  `postUpgradeSteps`/`preUninstallSteps` extension points, keep the two
  pieces of docmd specific behavior the plugin does not cover on its own:
  recreating the `~/.local/bin/docmd` symlink on Linux after an upgrade (and
  removing it on uninstall), and `chmod 755` on the freshly extracted
  binary. docmd's own `PlatformOps` abstraction, and the import workaround
  it required in `modules/global/commands/upgrade.dart`, are gone along with
  it. See the pull request body's parity table for the small set of
  observable differences this could not preserve without forcing behavior
  the plugin was not built for: the old "not installed, skip the network
  call" shortcut on upgrade, a new `release` check added to `docmd doctor`,
  different error ids and exit codes for a few failure cases, and the
  Windows uninstall's directory removal now going through the plugin's own
  scheduled cleanup instead of docmd's own PowerShell script.
- **`bench` and `setup` now accept the SDK's global options** (`--json`,
  `--quiet`, `--help`), matching every other command. Both were registered
  with `globals: false`, so passing `--json` to either was rejected as an
  unknown option instead of being honored.

### Fixed

- **The render routing tests no longer depend on Pandoc or LibreOffice
  being installed.** `test/vscode_extension_argument_order_test.dart`'s
  "render docx" and "render --pdf" tests exercised real rendering against
  an existing input, purely to check argument order; they now point at a
  missing input instead, which reaches the same validation-failed error
  before Pandoc or LibreOffice would ever be invoked. Actual conversion
  stays covered by `real_document_integration_test.dart`, already guarded
  on both tools being present.

## 0.2.3 — 2026-07-21

### Added

- **The default `docmd` summary now tells you when a newer release is available**
  (`Update available: v0.2.2 → v0.2.3 — run \`docmd upgrade\``). Previously a bare
  `docmd` gave no hint an update existed — you had to run `upgrade` to find out.
  The check is non-blocking and silent on network failure, so it never delays or
  breaks the summary. Mirrors the sibling `inquiry` CLI. (`doctor` already
  reported update availability; this brings the default view to parity.)

## 0.2.2 — 2026-07-21

### Changed

- **All of `upgrade`'s platform-specific install steps now live in `PlatformOps`**,
  finishing the seam started in 0.2.1. Backing up a running binary (Windows),
  extraction, the execute bit, and linking into the user's PATH (Linux) are each a
  method that is a no-op on the platform it does not apply to — so the command has
  no `if (platform == 'windows')` branching in its install flow at all. Aligns with
  the sibling `inquiry` CLI. The Windows backup/cleanup logic is unit-tested against
  a temp directory; the Linux symlink is covered on Linux (CI). No behaviour change.

## 0.2.1 — 2026-07-21

### Fixed

- **`upgrade` reported a malformed version.** The upgrade line read
  `Upgraded: 0.0.5 -> version: 0.2.0` — the `version:` label leaking in — because
  upgrade ran the new binary's `version` command and used its stdout verbatim,
  and `docmd version` prints a labelled `version: X`. It now reports the release
  tag version; the new binary is still run as a smoke-check, but its output is
  discarded.

### Changed

- **`upgrade`'s OS shell operations now sit behind a `PlatformOps` seam** (modelled
  on the sibling `inquiry` CLI). Archive extraction, the execute bit, and asset
  naming are polymorphic per platform instead of scattered `if windows` checks,
  and — because each implementation takes the shared process runner — the real
  commands (`tar xzf`, PowerShell `Expand-Archive`, `chmod 755`) are now covered
  by tests. No behaviour change; internal structure and test coverage only.

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
