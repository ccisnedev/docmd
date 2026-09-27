// modular_cli_sdk's own InstallationPlugin declares Upgrade*/Uninstall*
// types with the same names as docmd's hand-rolled upgrade/uninstall
// commands below. docmd does not use InstallationPlugin, so hide its
// installation-plugin exports to keep docmd's own types unambiguous.
import 'package:modular_cli_sdk/modular_cli_sdk.dart'
    hide
        UpgradeInput,
        UpgradeOutput,
        UpgradeCommand,
        UninstallInput,
        UninstallOutput,
        UninstallCommand;

import 'commands/tui.dart';
import 'commands/uninstall.dart';
import 'commands/upgrade.dart';

/// `version` and `doctor` are no longer registered here: they are owned by
/// `modular_cli_sdk`'s `VersionPlugin` and `DoctorPlugin`, registered in
/// `docmd_cli.dart`. `upgrade` and `uninstall` remain docmd's own, backed by
/// `PlatformOps`.
void buildGlobalModule(ModuleBuilder m) {
  m.query<TuiInput, TuiOutput>(
    '',
    (req) => TuiCommand(TuiInput.fromCliRequest(req)),
    globals: true,
    contract: TuiInput.contract,
    description: 'Display DocMD summary and available workflows',
  );

  m.query<UpgradeInput, UpgradeOutput>(
    'upgrade',
    (req) => UpgradeCommand(UpgradeInput.fromCliRequest(req)),
    globals: true,
    contract: UpgradeInput.contract,
    description: 'Download and install the latest DocMD release',
  );

  m.query<UninstallInput, UninstallOutput>(
    'uninstall',
    (req) => UninstallCommand(UninstallInput.fromCliRequest(req)),
    globals: true,
    contract: UninstallInput.contract,
    description: 'Remove the managed DocMD CLI installation from this machine',
  );
}
