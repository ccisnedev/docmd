# Roadmap

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
