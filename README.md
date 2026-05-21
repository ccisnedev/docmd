# DocMD

DocMD is a Markdown-first document engine for developers and AI-assisted workflows.

Its primary goal is to make office-style documents easier to import, review, edit,
version, and re-export from developer tooling, starting with VS Code.

## Install

- Website: https://docmd.ccisne.dev/
- VS Code: install the DocMD extension, then run `DocMD: Import File` or `DocMD: Install CLI`
- Windows CLI: `irm https://docmd.ccisne.dev/install.ps1 | iex`
- Linux CLI: `curl -fsSL https://docmd.ccisne.dev/install.sh | bash`

The VS Code extension installs the CLI from GitHub Releases directly inside VS Code.
It does not invoke an external install script when satisfying a missing runtime.

## Product Goal

DocMD aims to be an acceptable office workflow inside VS Code.

The system is optimized for this loop:

1. Import a document received as `.docx`, `.pptx`, `.xlsx`, or `.pdf`.
2. Convert it into a readable, semantic package that humans and AI can inspect.
3. Edit the canonical Markdown-first source in VS Code.
4. Render outward again to formats required by non-technical stakeholders.

## Product Thesis

- The canonical source should not be a binary office file.
- The canonical source should be easy to read by both humans and AI systems.
- Semantic preservation matters more than pixel-perfect visual fidelity.
- VS Code is the primary interactive surface.
- The CLI is the local runtime boundary for automation, scripting, and future surfaces.

## Primary Surfaces

- `docmd` CLI: headless runtime for import, validation, inspection, and rendering.
- VS Code extension: primary frontend for package creation, editing, AI workflows, and export commands.
- Future surfaces: desktop or mobile apps can be added later without changing the canonical document model.

## Canonical Artifact

DocMD stores work as a document package instead of treating `.docx`, `.pptx`, `.xlsx`,
or `.pdf` as the editable source of truth.

Typical package shape:

```text
my-package/
	manifest.yaml
	content/
		document.md
	assets/
	data/
	exports/
```

- `manifest.yaml` describes package kind, metadata, and rendering capabilities.
- `content/` contains Markdown-first canonical content.
- `assets/` stores extracted images and supporting files.
- `data/` stores structured tabular material when Markdown alone is not sufficient.
- `exports/` stores generated artifacts and should usually be ignored in version control.

## Quality Priorities

1. Human readability.
2. AI readability.
3. Stable diffs and deterministic outputs.
4. Semantic preservation.
5. Visual quality that is acceptable for sharing, but not the primary architectural driver.

## Repository Direction

```text
code/
	cli/
	vscode/
docs/
	adr/
```

The repository starts with CLI and VS Code surfaces. The shared engine and format
adapters are defined in the architecture and can be introduced incrementally.