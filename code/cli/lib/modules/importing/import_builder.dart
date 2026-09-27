import 'package:modular_cli_sdk/modular_cli_sdk.dart';

import 'commands/import_file.dart';

void buildImportModule(ModuleBuilder m) {
  m.query<ImportInput, ImportOutput>(
    '<input>',
    (req) => ImportCommand(ImportInput.fromCliRequest(req)),
    // globals: true so this route accepts the SDK's --json (the VS Code
    // extension always spawns `docmd import <path> ... --json`).
    globals: true,
    contract: ImportInput.contract,
    description: 'Import an external document into a DocMD package scaffold',
  );
}
