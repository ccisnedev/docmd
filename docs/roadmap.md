# Roadmap

## Strategic Direction — Orchestrated Ingestion & Render (2026-07)

DocMD is an **orchestrator of best-of-breed engines**, not a converter. Its value
is the editable, git-native document *package* with a two-way loop (import ↔
render) plus a VS Code frontend — a workflow the ingestion libraries (markitdown,
docling) do not offer. DocMD borrows their extraction; it owns the loop.

### Objective — this stage: content over style

- **Primary — LLM ingestion.** Be a viable alternative to markitdown/docling:
  ingest documents into *structured* Markdown + images, preserving content and
  reading order — not visual style.
- **Secondary — office export.** Render the canonical Markdown back to `.pdf`
  (primary), then `.docx`, `.pptx`, `.xlsx`, as simplified linear text+images for
  sharing with non-Markdown users.
- **Tertiary — VS Code authoring.** Markdown editor + live preview + export today.
  A basic WYSIWYG is a possible future, deliberately out of scope for now.

Visual-style fidelity is an explicit non-goal at this stage.

### Engine matrix — the idoneous tool per case

Import (X → md + images):

| Format | Engine | Python? |
|--------|--------|---------|
| `md` | copy | no |
| `docx` | pandoc | no |
| `pptx` / `xlsx` | LibreOffice `--convert-to html` → pandoc | no |
| `pdf` | **docling** (default) / markitdown (light fallback) | **yes** |
| images | markitdown / VLM captioning (optional) | optional |

Render (md → X): `docx`, `pptx` → pandoc; `pdf` → pandoc → docx → LibreOffice;
`xlsx` → ingest-only (render is degenerate for text+images). All native.

**Python is scoped to PDF ingestion only.** All render, and docx/pptx/xlsx
import, is native (pandoc + LibreOffice). A user who only edits Markdown and
exports needs no Python.

### Decisions taken

- **Pluggable backends, per-format defaults.** `IngestionBackend` /
  `RenderBackend` interfaces + a registry that selects by format and is
  overridable by config.
- **PDF engine:** markitdown is the general lightweight default, but for **PDF the
  declared default is docling** (layout, table structure, OCR) — markitdown's
  pdfminer path is too weak for the format that decides the LLM-ingestion thesis.
  markitdown remains the zero-friction PDF fallback when docling is absent.
- **Capability manifest.** `manifest.yaml` records the engine + version that
  produced the canonical content (provenance, reproducibility).
- **`docmd doctor` reports per-capability**, not per-binary: which import/render
  formats are available given installed tools, with install hints. The existing
  `checks` map stays for backward compatibility with the VS Code extension.
- **`docmd setup` auto-provisions** the toolchain: pandoc / LibreOffice via OS
  package managers or direct download; docling / markitdown via `uv` (a single
  static binary that bootstraps Python + the tool, so no pre-existing Python is
  required).
- **Ingestion benchmark harness** compares DocMD vs markitdown vs docling on a
  shared corpus (text coverage, reading order, tables, images) — the measure of
  "viable alternative".

### Immediate work (in order)

1. [x] Extract the `IngestionBackend` interface; refactor the existing
   pandoc-docx, passthrough, and placeholder paths behind it (no behaviour
   change). Availability-aware registry selection with a fallback backend.
2. [x] `docmd doctor` per-capability reporting + install hints (the `checks` map
   is preserved for the VS Code extension).
3. [x] PDF via docling (default) + markitdown (fallback), selected per
   availability. Docling artifacts are relocated into package assets.
4. [x] Ingestion benchmark harness — `docmd bench <corpus>` compares docmd vs
   docling vs markitdown (word/heading/table/image coverage + recall vs a
   reference engine), reporting any skipped/failed engine instead of dropping it.
5. [x] `docmd setup [all|pdf|docx]` provisioning — evidence-based install plan
   per OS (winget/brew/apt for pandoc & LibreOffice; uv-bootstrapped docling &
   markitdown). Terraform-style `--plan` (safe default) / `--apply`, matching
   `iq issue publish`.

Follow-ups deferred from this cut: engine + version recorded in the manifest
(D2 provenance); pptx/xlsx real ingestion via LibreOffice; end-to-end validation
of docling's referenced-image output on a machine with docling installed (the
artifact-folder name is currently handled generically and marked in code).

Note: the engine matrix above lists `pptx` as "LibreOffice `--convert-to html` →
pandoc". That is stale — pptx ingestion is a native Dart OOXML reader
(`pptx_backend.dart`), which is strictly better: pandoc has no pptx *reader* at
all, and it resolves images to real media parts. The row is left as written until
the matrix is revised as a whole.

### Dogfood findings — 17-slide deck, 2026-07-24

Surfaced by running a real requirements deck through import → edit → render.
Fixed in 0.2.6: reading order, slide titles, kind-driven render default, and the
VS Code editor's blocked images and missing PPTX export. Still open:

- **Tables are dropped.** `<a:tbl>` inside `<p:graphicFrame>` is not handled in
  `_blocksIn`, which walks only `sp`, `pic` and `grpSp`. A deck with tables loses
  them silently — no warning, no placeholder. Not hit by the corpus deck (0
  tables across its 17 slides), which is the only reason it is not urgent.
- **Speaker notes are dropped.** `ppt/notesSlides/` is never read. Often carries
  the argument behind a slide. The corpus deck's two notes held only "8" and "9",
  so it bought nothing there.
- **Connectors are dropped.** `p:cxnSp` (4 in the corpus deck) — arrows and
  flow lines. Losing the shape is fine; losing a label on it would not be.
- **pandoc's pptx writer silently drops inline images.** Measured, not assumed: an
  image inside a text paragraph or a list item renders as *no image at all*, while
  an image alone in its paragraph survives but forces a slide break. So a deck
  round-trips at roughly one slide per image and there is no arrangement that
  keeps both the images and a 1:1 slide mapping. A native pptx writer is the only
  real fix; until then this is the ceiling on render fidelity for decks.
- **`--reference-doc` passthrough.** pandoc can take a template deck to preserve
  branding, and the imported package already keeps the original in
  `assets/original/`. Deliberately skipped this cut (the driving task did not want
  the institutional design carried over) but it is the only route to an export
  that looks like the source.
- **Import reports no per-slide fidelity.** The summary counts media but says
  nothing about shapes it could not represent, so silent loss stays silent.

The version milestones below remain the feature-level plan, reframed by the
direction above.

## v0.0.1 — DOCX to Markdown to DOCX

### CLI

- [x] Import `.docx` into a DocMD `document` package
- [x] Store canonical content in `content/document.md`
- [x] Preserve the original source file in the package
- [x] Extract media and keep asset references usable from Markdown
- [x] Render the edited package back to `.docx`
- [x] Support `.pdf` export from the same package

### VS Code extension

- [x] Open a `.docx` by importing it into a local DocMD package
- [x] Provide a minimal Google Docs-inspired editor for `document` packages
- [x] Allow switching between visual editing and raw package file editing
- [x] Save changes back into the DocMD package
- [x] Export the active package to `.docx` and `.pdf`

## v0.0.2 — Better Document Workflow

- [x] Emit machine-readable JSON output from the CLI
- [ ] Show import and render progress in the extension
- [ ] Surface validation and render diagnostics in editor UX
- [ ] Improve `.docx` normalization for cleaner Markdown output
- [ ] Add package templates for common document types

## v0.0.3 — Package-first Authoring

- [ ] Create new packages directly from VS Code without starting from `.docx`
- [ ] Support AI-assisted editing against canonical package files
- [ ] Add preview and split-mode editing for visual and raw workflows
- [ ] Validate package integrity before rendering
- [ ] Stabilize the `document` package contract

## v0.0.4 — Presentation and Spreadsheet Packages

- [ ] Introduce `deck` package kind for slide workflows
- [ ] Introduce `sheet` package kind for spreadsheet workflows
- [ ] Define format-specific package conventions and examples
- [ ] Render to `.pptx`
- [ ] Render to `.xlsx`

## v0.1.0 — Acceptable Office Workflow for VS Code

- [ ] End-to-end requirement workflow from imported `.docx` to edited package to exported stakeholder file
- [ ] Stable package specification and CLI surface
- [ ] Usable VS Code-first authoring experience
- [ ] Open source documentation suitable for contributors and external adoption

## Backlog

- Best-effort `.pdf` import and OCR support
- Review comments and tracked-change style workflows
- Multiple render profiles and style packs
- CI validation for sample packages
- Desktop surface once the VS Code workflow is stable
