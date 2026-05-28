import 'package:modular_cli_sdk/modular_cli_sdk.dart';

import 'commands/doctor.dart';
import 'commands/tui.dart';
import 'commands/uninstall.dart';
import 'commands/upgrade.dart';
import 'commands/version.dart';

void buildGlobalModule(ModuleBuilder m) {
  m.command<TuiInput, TuiOutput>(
    '',
    (req) => TuiCommand(TuiInput.fromCliRequest(req)),
    description: 'Display DocMD summary and available workflows',
  );

  m.command<VersionInput, VersionOutput>(
    'version',
    (req) => VersionCommand(VersionInput.fromCliRequest(req)),
    description: 'Print the current DocMD CLI version',
  );

  m.command<DoctorInput, DoctorOutput>(
    'doctor',
    (req) => DoctorCommand(DoctorInput.fromCliRequest(req)),
    description: 'Verify local prerequisites such as Pandoc and LibreOffice',
  );

  m.command<UpgradeInput, UpgradeOutput>(
    'upgrade',
    (req) => UpgradeCommand(UpgradeInput.fromCliRequest(req)),
    description: 'Download and install the latest DocMD release',
  );

  m.command<UninstallInput, UninstallOutput>(
    'uninstall',
    (req) => UninstallCommand(UninstallInput.fromCliRequest(req)),
    description: 'Remove the managed DocMD CLI installation from this machine',
  );
}
