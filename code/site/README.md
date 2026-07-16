# DocMD site

The public landing page for DocMD, served at **docmd.ccisne.dev** (GitHub Pages;
see `CNAME`).

## Structure — separation of concerns is a hard rule

| Responsibility | Lives in | Never put it in |
|----------------|----------|-----------------|
| **Structure** (markup) | `index.html` | — |
| **Presentation** (styles) | `css/landing.css` | a `<style>` block or `style="..."` attributes |
| **Behaviour** (scripts) | `js/landing.js` | a `<script>` block or `onclick="..."` attributes |
| **Assets** (logo, images) | `img/` | inlined SVG/data-URIs in the HTML |

```
site/
  index.html        # structure only
  css/landing.css   # all presentation (single source of truth)
  js/landing.js     # all behaviour
  img/logo.svg      # brand mark (referenced, never inlined)
  install.ps1       # Windows CLI installer
  install.sh        # Linux CLI installer
  CNAME             # custom domain
```

### Why

Keeping structure, presentation, behaviour, and assets in separate files gives us
browser caching, reuse, clean diffs, and a single place to change each concern.
A **self-contained one-file build** (CSS + JS + SVG all inlined into one HTML) is
only ever acceptable as a **throwaway preview** — e.g. a hosted design preview
that requires everything in one file. It must never be committed here.

If you need a one-off style, add a small utility class in `css/landing.css`
(see the `utilities` block) rather than an inline `style="..."`.

## Content

The copy must reflect the **current CLI**. When commands or the engine matrix
change (`import`, `render`, `doctor`, `bench`, `setup --plan/--apply`, the
docling/markitdown/pandoc/LibreOffice orchestration), update `index.html` to
match. Keep `docs/roadmap.md` as the source of truth for direction.

## Preview locally

Open `index.html` directly in a browser, or serve the folder:

```sh
python -m http.server --directory code/site 8000
# then visit http://localhost:8000
```
