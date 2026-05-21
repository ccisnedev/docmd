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
docmd import <input>
docmd render <input> [--pdf]
```

`docmd render` defaults to `.docx` output.
