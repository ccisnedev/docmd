# Architecture

## System Goal

DocMD is a Markdown-first document system with two initial surfaces:

- a local CLI runtime exposed as `docmd`
- a VS Code extension that acts as the primary interactive frontend

The long-term goal is to provide an acceptable office workflow for developers in
VS Code, while keeping the canonical source readable for both humans and AI.

For v0.0.1, the scope is intentionally narrower:

- import a `.docx` into a DocMD document package
- edit the generated Markdown directly
- render the edited package back to `.docx`
- provide a minimal VS Code frontend for import, visual editing, package editing, and export

## Architectural Summary

DocMD follows a CLI-first engine architecture.

- The core engine owns document package semantics, import pipelines, render pipelines, and validation.
- The CLI is the stable local execution boundary for users, scripts, CI, and future UIs.
- The VS Code extension is a frontend over the CLI rather than a second implementation of document logic.
- Binary office formats are treated as import and export formats, not as the canonical editable source.

## Current Release Focus

### v0.0.1

The first release proves a single end-to-end workflow for `document` packages:

1. import `.docx`
2. normalize into a Markdown-first package
3. edit the Markdown package directly or through a visual editor
4. export back to `.docx` or `.pdf`

Presentation and spreadsheet workflows remain part of the broader product vision,
but they are not part of the first release contract.

## Runtime Topology

```text
VS Code Extension
				|
				v
		docmd CLI
				|
				v
	 Core Engine
	 |  package model
	 |  import services
	 |  render services
	 |  validation
				|
				v
Format Adapters and Tools
Pandoc / LibreOffice / native libraries / filesystem
```

## Target Repository Modules

| Module | Responsibility |
|--------|----------------|
| `code/engine` | Shared core engine for package modeling, validation, import, render orchestration, and adapter contracts. Planned module. |
| `code/cli` | Public local runtime surface. Exposes commands for import, inspect, validate, and render. |
| `code/vscode` | Primary authoring frontend. Invokes the CLI, manages UX, shows diagnostics, and integrates with editor and AI workflows. |
| `docs` | Product documentation, ADRs, architecture, roadmap, and future format specifications. |

## Canonical Document Package

DocMD does not treat `.docx`, `.pptx`, `.xlsx`, or `.pdf` as editable truth.
Instead it normalizes content into a package.

For v0.0.1, the only supported package kind is `document`, and the canonical
package shape is intentionally simple.

```text
package/
	manifest.yaml
	content/
		document.md
	assets/
		original/
		... extracted media
	exports/
```

### Package Rules

- `manifest.yaml` is required and declares package kind, metadata, and supported render targets.
- `content/document.md` is the canonical editable source for v0.0.1.
- `assets/original/` stores the imported source file.
- `assets/` also stores extracted binaries such as images and embedded media.
- `exports/` contains generated files and is reproducible from canonical sources.

## Future Package Evolution

The architecture still reserves room for richer package layouts, including slide
and spreadsheet packages, but those are future concerns.

Possible future additions include:

- `content/deck.md`
- `content/notes.md`
- `data/*.csv`
- `data/*.yaml`

## Package Kinds

DocMD is intended to support multiple package kinds under one architecture.

| Kind | Canonical focus | Typical outputs |
|------|------------------|-----------------|
| `document` | prose-first Markdown | `.docx`, `.pdf` |
| `deck` | slide-oriented Markdown plus assets | `.pptx`, `.pdf` |
| `sheet` | structured tables plus notes and metadata | `.xlsx`, `.csv`, `.pdf` |

Not every package kind renders to every output. Export compatibility is decided
by the package kind and the renderer profile.

Only `document` is in scope for v0.0.1.

## Core Engine Responsibilities

### Package Services

- create and load document packages
- validate package structure and metadata
- normalize paths, assets, and generated outputs
- keep canonical content deterministic and diff-friendly

### Import Services

- v0.0.1: ingest `.docx`
- extract semantic content, metadata, and assets
- convert imported material into DocMD packages
- preserve meaning and structure where possible, without aiming for pixel-perfect reconstruction
- future: extend import services to `.pptx`, `.xlsx`, and `.pdf`

### Render Services

- render package content back into stakeholder-friendly formats
- v0.0.1: render `document` packages to `.docx` and `.pdf`
- encapsulate tool-specific flags and style profiles
- provide stable render contracts for CLI and VS Code callers

### Validation Services

- validate package integrity before rendering
- validate adapter prerequisites and external tool availability
- emit machine-readable diagnostics for frontend consumption

## CLI Responsibilities

The CLI is the public local API.

Its responsibilities are:

- expose import, inspect, validate, and render commands
- provide machine-readable JSON output for the VS Code extension
- provide human-readable terminal output for direct users
- isolate external tool execution behind a stable command contract

The CLI should be scriptable, deterministic, and suitable for future CI or batch use.

## VS Code Extension Responsibilities

The VS Code extension is the primary user-facing product.

Its responsibilities are:

- create or open DocMD packages in the editor
- import a `.docx` into a local package when opening external documents
- invoke the CLI for import and render operations
- surface logs, errors, and validation in editor UX
- coordinate AI-assisted editing against canonical Markdown content
- provide a minimal Google Docs-inspired editing experience for `document` packages
- allow the user to edit either through a visual editor or by directly editing package files
- make office-style workflows feel natural inside VS Code

The extension should not duplicate import or render logic already owned by the engine.

## Primary Workflows

### CLI round-trip workflow

1. User receives a `.docx` requirement from a non-technical area.
2. The CLI imports it into a DocMD `document` package.
3. The generated `content/document.md` becomes the canonical editable source.
4. The user edits the Markdown directly.
5. The CLI renders the edited package back to `.docx`.

### VS Code editing workflow

1. User opens a `.docx` through the extension.
2. The extension imports it into a local DocMD package.
3. The user edits the document through a minimal visual editor or by editing package files directly.
4. AI and human editing both operate on the same canonical package.
5. The extension saves the package and exports `.docx` or `.pdf` for sharing.

## Cross-cutting Concerns

- **Readability first**: canonical files must remain understandable outside specialized editors.
- **AI-first structure**: metadata, headings, and assets should be explicit and discoverable.
- **Determinism**: imports and renders should minimize noisy diffs.
- **Local-first execution**: the core workflow should work on a developer machine without remote dependencies.
- **Tool encapsulation**: Pandoc, LibreOffice, and future format libraries are implementation details behind adapters.
- **Diagnostics**: every major operation should have both human-readable and machine-readable errors.

## Non-goals

- Pixel-perfect round-tripping with Microsoft Office files.
- Treating binary office formats as the canonical editable source.
- Prioritizing visual styling over semantic structure in early versions.
- Supporting full spreadsheet and presentation workflows in v0.0.1.
