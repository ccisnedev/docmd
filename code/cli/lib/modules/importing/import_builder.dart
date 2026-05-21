import 'package:modular_cli_sdk/modular_cli_sdk.dart';

import 'commands/import_file.dart';

void buildImportModule(ModuleBuilder m) {
  m.command<ImportInput, ImportOutput>(
    '<input>',
    (req) => ImportCommand(ImportInput.fromCliRequest(req)),
    description: 'Import an external document into a DocMD package scaffold',
  );
}
