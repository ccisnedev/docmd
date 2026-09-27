import 'package:modular_cli_sdk/modular_cli_sdk.dart';

import 'commands/setup.dart';

void buildSetupModule(ModuleBuilder m) {
  m.query<SetupInput, SetupOutput>(
    '<capability>',
    (req) => SetupCommand(SetupInput.fromCliRequest(req)),
    globals: false,
    contract: SetupInput.contract,
    description: 'Install the tools DocMD needs (pandoc, LibreOffice)',
  );
}
