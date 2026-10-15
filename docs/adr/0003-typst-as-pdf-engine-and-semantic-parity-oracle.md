# ADR 0003: Typst as PDF Engine and Semantic Parity Oracle

**Status:** Accepted

## Context

`render` produces `.docx` through pandoc and `.pdf` through pandoc → `.docx` →
LibreOffice. Rendering a real academic document (citations, numbered sections,
figures, tables, block math) through both paths showed that the two outputs
disagree on *content*, not just on looks:

- LibreOffice drops the table of contents and prints the `&` of an `aligned`
  block literally.
- Citations stay raw (`@rosen2019`) and the bibliography is empty, because
  `--citeproc` is never passed.
- `number-sections: true` in the front matter is ignored: pandoc only honors it
  as a command-line option.
- `@fig:x` / `@tbl:x` references are left unresolved; captions are numbered in
  one output and not in the other.

pandoc has a native Typst writer (since 3.1.2), and `typst compile` turns its
output into a PDF in well under a second, with no office suite involved. Both
outputs then come from the same pandoc AST, the same options and the same
filters.

## Decision

1. **Visual-style fidelity remains a non-goal** (see the roadmap). The `.docx`
   and the `.pdf` are not expected to look alike: Word and Typst set type
   differently and chasing that has no end.
2. **Semantic parity is a goal.** Both outputs of the same source must say the
   same thing:
   - the same text and structure (headings, lists, tables, figures);
   - the same numbering (sections, figure and table captions) and the same
     resolved cross-references;
   - the same citations and the same bibliography;
   - nothing raw or broken in either (`@key`, `fig:x?`, a literal `&`, an empty
     table of contents).
3. **The PDF is rendered by Typst** (pandoc `-t typst` → `typst compile`).
   LibreOffice stays as the fallback when Typst is not installed.
4. **Typst is the parity oracle.** A parity fixture is rendered to both formats
   and a test extracts a set of facts from each — from the `.docx` XML and, with
   docmd's own PDF reader, from the PDF — and requires them to match. Each
   render feature adds its facts to that test.
5. **Options travel through the front matter.** Writer options pandoc does not
   read from metadata (`number-sections`, citation processing) are derived by
   docmd from the source's front matter, so the Markdown stays the single place
   a document is configured.
6. **No new tool dependencies beyond Typst.** Filters are pandoc Lua filters
   embedded in docmd; pandoc ships its own Lua.

## Consequences

### Positive

- The PDF is correct on content and much faster, and LibreOffice is no longer
  required to produce one.
- A parity regression shows up as a failing test instead of a reader's comment.
- Fixing a feature once (in options or a filter) fixes it in both formats.

### Negative

- Typst becomes a new recommended tool; `doctor` and `setup` must know about it.
- docx-only styling (templates, fonts) and Typst-only styling are out of scope
  and will keep diverging, by design.
- Parity is checked on extracted text, so it covers what text extraction can
  see; layout and math rendering are verified by eye.
