# DocMD for VS Code

DocMD for VS Code is the primary interactive frontend for the DocMD ecosystem.

The extension does not own document import or render logic directly. It invokes
 the local `docmd` runtime and turns those workflows into editor-native commands.

## Runtime Installation

End users do not need to preinstall the CLI manually.

1. Install the extension.
2. Run `DocMD: Import File`, `DocMD: Render File`, `DocMD: Run Doctor`, or `DocMD: Install CLI`.
3. If the runtime is missing, the extension offers to download the latest GitHub release and retry the command.

Managed install locations:

- Windows: `%LOCALAPPDATA%\docmd\bin\docmd.exe`
- Linux: `~/.docmd/bin/docmd`

## Module Layout

- `src/core` wires activation and shared services.
- `src/modules` contains user-facing modules such as doctor, import, and render.
- `src/infrastructure` contains concrete adapters such as the `docmd` process wrapper and output logging.
- `src/shared` contains reusable helpers and error presentation.

## Local Testing

Use the extension from VS Code's Extension Development Host:

1. Open the repository root in VS Code so the workspace uses the root `.vscode` launch and task configuration.
2. Install dependencies in this folder with `npm install`.
3. Ensure the local toolchain is available:
	- `dart` for the sibling CLI in `../cli`
	- `pandoc` for DOCX import and DOCX export
	- `soffice` or LibreOffice for PDF export
4. Run the `Run Extension` launch configuration with F5 from the repository root window.
5. In the Extension Development Host, run `DocMD: Run Doctor` from the Command Palette.
6. Run `DocMD: Import File`, choose a `.docx`, and wait for the editor webview to open.
7. Edit the Markdown in the left pane and press `Save`.
8. Use `Open Raw` to verify the persisted `content/document.md` file.
9. Use `Export DOCX` or `Export PDF` in the editor toolbar, or run `DocMD: Render File`.

During local development the extension resolves the CLI in this order:

- `DOCMD_CLI_PATH` when explicitly set
- `../cli/build/bin/docmd(.exe)` when a local build exists
- `dart run bin/main.dart` from the sibling `../cli` project
- the managed install directory used by `DocMD: Install CLI`
- `docmd` from the system `PATH`
