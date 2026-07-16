import 'package:modular_cli_sdk/modular_cli_sdk.dart';

import 'commands/setup.dart';

void buildSetupModule(ModuleBuilder m) {
  m.command<SetupInput, SetupOutput>(
    '<capability>',
    (req) => SetupCommand(SetupInput.fromCliRequest(req)),
    description: 'Install the tools DocMD needs (pandoc, LibreOffice, docling, markitdown)',
    params: SetupInput.params,
  );
}
