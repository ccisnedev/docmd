import 'package:modular_cli_sdk/modular_cli_sdk.dart';

import 'commands/tui.dart';

/// `version`, `doctor`, `upgrade` and `uninstall` are no longer registered
/// here: they are owned by `modular_cli_sdk`'s `VersionPlugin`, `DoctorPlugin`
/// and `InstallationPlugin`, registered in `docmd_cli.dart`. Only the bare
/// `docmd` summary (`tui`) is still docmd's own.
void buildGlobalModule(ModuleBuilder m) {
  m.query<TuiInput, TuiOutput>(
    '',
    (req) => TuiCommand(TuiInput.fromCliRequest(req)),
    globals: true,
    contract: TuiInput.contract,
    description: 'Display DocMD summary and available workflows',
  );
}
