# DocMD CLI

The `docmd` CLI is the local runtime for DocMD.

It is responsible for:

- importing external files into DocMD packages
- validating local prerequisites
- rendering canonical packages into shareable formats
- exposing a stable command surface for the VS Code extension

## Install

Windows:

```powershell
irm https://docmd.ccisne.dev/install.ps1 | iex
```

Linux:

```bash
curl -fsSL https://docmd.ccisne.dev/install.sh | bash
```

## Commands

```text
docmd
docmd version
docmd doctor
docmd upgrade
docmd uninstall
docmd import [options] <input>
docmd render [--pdf] <input>
```

Options may come before or after the operand: `docmd render --pdf report.md`
and `docmd render report.md --pdf` both parse. With `POSIXLY_CORRECT` set,
`docmd` follows strict POSIX ordering and rejects an option after the operand.

`docmd render` defaults to `.docx` output.
`docmd doctor` reports each local prerequisite (Pandoc, LibreOffice), each
import and render capability, and whether a newer release is available.
