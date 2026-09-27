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

Options always come before the operand: `docmd` follows strict POSIX ordering,
so `docmd render --pdf report.md` parses but `docmd render report.md --pdf`
is rejected.

`docmd render` defaults to `.docx` output.
`docmd doctor` reports the status of each local prerequisite check.
