# QA Analysis — docmd CLI 0.0.5

Date: 2026-07-17
Corpus: `C:\Users\44358590\Code\lab\mi_proyecto_1` (1 docx, 1 pdf, 2 pptx, 2 md)
Baseline: `dart analyze` clean, `dart test` = 88 passed / 1 skipped.

**Headline:** every defect below survives a fully green test suite. The suite is not
weak in coverage; it is weak in *mock fidelity*. The fake pandoc writes
`# Imported from docx`, which no real pandoc invocation has ever produced, so the
tests assert against a contract the real tool does not honor.

---

## F1 — Broken tools are reported as available (CRITICAL)

`resolveExecutable` (`lib/src/tool_locator.dart:118-132`) treats *presence on PATH*
as *works*. Two compounding faults:

```dart
if (deps.fileExists(trimmed)) return trimmed;
return trimmed;   // both branches return -> fileExists check is dead code
```

The loop returns the **first** `where` hit unconditionally and never considers later
candidates.

Observed on this machine:

```
where markitdown
  C:\Python311\Scripts\markitdown.exe        <- shim exists, module missing, EXIT 1
  C:\Users\44358590\.local\bin\markitdown.exe <- works, "markitdown 0.1.5"
```

`doctor` reports `import pdf: available (markitdown)`; `import` then dies with
`ModuleNotFoundError: No module named 'markitdown'`.

**Proven:** after a *correct* `uv tool install 'markitdown[all]'`, the CLI is *still
broken*, because the resolver keeps picking the shim. A correct install does not
repair the tool. This is the defect that makes the others unreachable.

**Fix:** probe functionally (`<tool> --version`, exit 0), iterate every candidate,
return the first that actually runs. Cache per-process.

## F2 — Tool failures crash instead of erroring (HIGH)

Backends throw `ProcessException` (`markitdown_pdf_backend.dart:51-58`,
`pandoc_docx_backend.dart:50-57`); nothing catches it. The user gets a Dart stack
trace and exit **255** instead of the SDK error envelope (exit 1/7 + JSON).

Violates `docs/architecture.md:211` — "every major operation should have both
human-readable and machine-readable errors". Also breaks `--json` consumers: the
VSCode extension gets a stack trace on stdout-adjacent stderr.

**Fix:** map `ProcessException` to a typed `ToolExecutionError` at the command
boundary; render via `toText()`/`toJson()`.

## F3 — `setup` cannot repair markitdown (HIGH)

Three faults stack:

1. `docmd setup markitdown` -> `Unknown capability`. The root help advertises
   `setup <capability>  Install the tools DocMD needs (pandoc, LibreOffice, docling,
   markitdown)`, naming tools that are not accepted values. Capabilities are only
   `{all, pdf, docx}` (`install_plan.dart:32`).
2. The `pdf` capability omits markitdown (`install_plan.dart:39`) although markitdown
   *is* the wired PDF import engine.
3. `buildSetupPlan` skips any tool reported present (`install_plan.dart:67`). Fed by
   F1's false positive, `setup all` omits markitdown from the plan entirely — verified:

```
docmd setup all
  docling — Default PDF ingestion engine
    uv tool install docling
  (markitdown absent)
```

So the one command meant to fix the machine refuses to.

**Fix:** per-tool capabilities; base "present" on the F1 functional probe; add
`--force` to reinstall a present-but-broken tool.

## F4 — Absolute paths baked into canonical Markdown (HIGH)

`--extract-media=${layout.assetsDirPath}` passes an **absolute** path
(`pandoc_docx_backend.dart:45`), so pandoc writes machine-specific paths into the
canonical document:

```html
<img src="C:\Users\44358590\Code\lab\mi_proyecto_1\out/refinanciado\...docmd\assets\media\image1.png" ...>
```

The package is not portable — commit it, zip it, or move it and every image breaks.
This contradicts ADR-0002's premise that the package is the portable unit.

Consequence: `_normalizeAssetReferences` (`pandoc_docx_backend.dart:63-78`) is **dead
code**. It rewrites `(assets/` -> `(../assets/`, a relative prefix pandoc never emits
when `--extract-media` is absolute. It has never fired in production.

**Fix:** run pandoc with `workingDirectory` = package root and a relative
`--extract-media=assets`; keep normalization as a guard with a test that fails if it
stops matching.

## F5 — Round-trip silently drops every image (HIGH)

Pandoc's gfm writer emits raw `<img>` HTML for images carrying width/height (25 tags
over 18 distinct files here); pandoc's **docx writer silently drops raw HTML**. Import
-> render therefore loses all imagery with no warning.

Measured, same input:

| Path | Output |
|---|---|
| Original docx | 1,835,570 B |
| `document.md` as-is (raw `<img>`) -> docx | **12,755 B** |
| `<img src="X">` rewritten to `![](X)` -> docx | **1,668,016 B** |

**Fix:** normalize `<img>` -> `![](...)` during import. Restores fidelity and makes
the canonical Markdown genuinely Markdown rather than HTML-in-Markdown.

## F6 — Fidelity loss is never reported (MEDIUM)

Import prints `status: converted` and nothing else. Whether the canonical document
kept every image, or none of them, reads identically. Under F5 that silence hid total
image loss; the user could only discover it by diffing file sizes.

Corpus measurement (after instrumenting): this docx yields **18 extracted, 18
referenced, 0 orphans**. An earlier estimate in this report of "6 orphans" was wrong —
it came from a miscount of the `<img>` tags before the accounting existed. The `.emf`
vector objects *are* referenced. The residual size gap between the original
(1,835,570 B) and the round trip (1,667,847 B) is pandoc's re-encoding, not lost media.

The reporting is still worth having: orphans are a real class of loss for other
inputs, and "18/18 referenced" is the only cheap proof that an import kept what it
found.

**Fix:** report `media extracted / referenced / orphaned`; warn when orphans > 0.

## F7 — `render --pptx` / `--xlsx` advertised but unimplemented (MEDIUM)

Root help: "Render canonical content to DOCX, PDF, PPTX, or XLSX". Both flags are
declared and parse, then always fail:

```
docmd render specification.md --pptx  -> Error: Unsupported output format: pptx
docmd render specification.md --xlsx  -> Error: Unsupported output format: xlsx
```

A flag that exists solely to reject its own use is worse than an absent flag.

**Fix:** either implement via LibreOffice (present on this machine) or remove the
flags and the help claim. Do not ship a flag that only errors.

## F8 — PPTX/XLSX import is a placeholder (MEDIUM, known)

`doctor` is honest here. `import` yields `status: package-only` and a stub document.
The original is preserved in `assets/original/`, so no data loss. Two of six corpus
files are pptx, so this is the corpus's largest functional gap.

**Fix:** real extraction is a feature, not a bugfix — scope separately.

## F9 — Mock infidelity is the root cause of the blind spot (MEDIUM)

`test/import_test.dart:83-93`'s fake pandoc writes `# Imported from docx`. Real pandoc
emits raw `<img>` tags with absolute src. F4 and F5 are invisible to the suite because
the mock asserts a fiction. `test/pdf_ingestion_test.dart` sets the correct house
standard — it replicates docling's real output shape (`<stem>.md` + `<stem>_artifacts/`).
The docx mock does not meet that bar.

`test/fixtures/analisis.docx` has no images, so the real-tool integration test cannot
catch F4/F5 either.

**Fix:** upgrade the docx mock to emit real pandoc output; add an image-bearing
fixture.

## F10 — `upgrade.dart` bypasses the DI seam (LOW)

`lib/modules/global/commands/upgrade.dart:395,412,419,449` call `Process.run`
directly (powershell, tar, chmod) instead of the injected `ProcessRunner`. Those paths
are untestable; `upgrade_test.dart` only covers what `UpgradeDeps` reaches.

## Not a defect — ruled out

**Non-ASCII paths.** `import "...Nano crédito - Día de pago.pdf"` returned
`Input file not found`, which looked like a docmd encoding bug. It is not: `Copy-Item`
failed identically on the same string, and passing the name read from the filesystem
(`(Get-ChildItem -Filter "*Nano*").Name`) reaches the backend normally. The mangling
was in the calling shell. **docmd handles accented paths correctly.**

---

## Dependency order

```
F1 (functional probe)
 ├─> F3 (setup consumes the probe)
 └─> F2 (surface the failure properly)
F9 (honest mocks)
 └─> F4, F5, F6 (only observable once mocks tell the truth)
F7, F8, F10 independent
```

F1 first: until the probe is honest, no PDF path can be verified end-to-end on this
machine. F9 before F4/F5: without a truthful mock, TDD cannot produce a red test.
