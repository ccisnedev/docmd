# ADR 0002: Adopt a Markdown-first Document Package with CLI Runtime and VS Code Frontend

**Status:** Accepted

## Context

DocMD needs to solve a specific problem for developers working with AI:

- incoming office files such as `.docx`, `.pptx`, `.xlsx`, and `.pdf` are difficult to diff, inspect, and feed into AI workflows
- the primary user environment is VS Code, not a traditional office suite
- non-technical stakeholders still require common output formats such as `.docx`, `.pdf`, `.pptx`, and `.xlsx`

The project therefore needs a canonical source format that is easy to read,
version, inspect, and transform, while still supporting import from and export to
common office formats.

## Decision

We will adopt the following architecture:

1. The canonical source of truth is a DocMD package, not a binary office file.
2. The package is Markdown-first and stores metadata, content, assets, and optional structured data.
3. The CLI is the stable local runtime boundary for import, validation, inspection, and rendering.
4. The VS Code extension is the primary frontend and invokes the CLI instead of reimplementing core logic.
5. Import and render operations are implemented through format adapters and external tools.
6. Semantic preservation and readability are prioritized over pixel-perfect visual fidelity.

## Consequences

### Positive

- Canonical files become readable to both humans and AI.
- The system supports version control and stable diffs more naturally than binary office files.
- Multiple user surfaces can be built without changing the document model.
- The VS Code extension stays thin and focused on UX.
- The CLI becomes useful for direct users, automation, and future CI workflows.

### Negative

- Imported documents will not round-trip with exact visual fidelity.
- Some office-specific features will be normalized or dropped during import.
- Rendering quality depends on external tools and adapter maturity.
- Spreadsheet and presentation workflows require package conventions beyond a single Markdown file.

## Notes

This decision intentionally favors semantic clarity over office-format fidelity.
That tradeoff is central to the product.