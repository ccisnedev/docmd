import 'package:modular_cli_sdk/modular_cli_sdk.dart';

import 'commands/tui.dart';

/// `version` and `doctor` are owned by `modular_cli_sdk`'s `VersionPlugin`
/// and `DoctorPlugin`; `upgrade` and `uninstall` are owned by its
/// `InstallationPlugin`. All three are registered in `docmd_cli.dart`. Only
/// the bare `docmd` summary route remains docmd's own.
void buildGlobalModule(ModuleBuilder m) {
  m.query<TuiInput, TuiOutput>(
    '',
    (req) => TuiCommand(TuiInput.fromCliRequest(req)),
    globals: true,
    contract: TuiInput.contract,
    description: 'Display DocMD summary and available workflows',
  );
}
