library;

import 'package:modular_cli_sdk/modular_cli_sdk.dart';

import '../../../src/tool_locator.dart';

/// Contributes docmd's own doctor checks (Pandoc and LibreOffice
/// availability) to the `doctor.checks` extension point [DoctorPlugin]
/// declares. `doctor` itself is owned entirely by `modular_cli_sdk`'s own
/// [DoctorPlugin]; this plugin only adds the two checks that are specific to
/// docmd's own import/render tooling.
class DocmdDoctorChecksPlugin implements CliPlugin {
  DocmdDoctorChecksPlugin({
    String? Function()? resolvePandocExecutable,
    String? Function()? resolveLibreOfficeExecutable,
  }) : _resolvePandocExecutable =
           resolvePandocExecutable ?? resolvePandocExecutableDefault,
       _resolveLibreOfficeExecutable =
           resolveLibreOfficeExecutable ?? resolveLibreOfficeExecutableDefault;

  final String? Function() _resolvePandocExecutable;
  final String? Function() _resolveLibreOfficeExecutable;

  @override
  CliPluginManifest get manifest => const CliPluginManifest(
    id: 'docmd.doctor_checks',
    displayName: 'DocMD doctor checks',
    version: '1.0.0',
    hostApiVersion: '^$cliPluginHostApiVersion',
    requires: ['modular_cli.doctor'],
  );

  @override
  void setup(CliPluginHost host) {
    host.contribute<CliDoctorCheck>(
      DoctorPlugin.extensionPoint,
      CliDoctorCheck(name: 'pandoc', run: _checkPandoc),
    );
    host.contribute<CliDoctorCheck>(
      DoctorPlugin.extensionPoint,
      CliDoctorCheck(name: 'libreoffice', run: _checkLibreOffice),
    );
  }

  Future<CliCheckResult> _checkPandoc() async {
    final path = _resolvePandocExecutable();
    return path != null
        ? CliCheckResult(
            status: CliCheckStatus.ok,
            message: 'pandoc found at $path',
          )
        : const CliCheckResult(
            status: CliCheckStatus.error,
            message:
                'pandoc was not found. Install it: `docmd setup docx` '
                '(https://pandoc.org/installing.html)',
          );
  }

  Future<CliCheckResult> _checkLibreOffice() async {
    final path = _resolveLibreOfficeExecutable();
    return path != null
        ? CliCheckResult(
            status: CliCheckStatus.ok,
            message: 'libreoffice found at $path',
          )
        : const CliCheckResult(
            status: CliCheckStatus.error,
            message:
                'libreoffice was not found. Install it: `docmd setup pdf` '
                '(https://www.libreoffice.org/download)',
          );
  }
}

String? resolvePandocExecutableDefault() => resolvePandocExecutable();

String? resolveLibreOfficeExecutableDefault() => resolveLibreOfficeExecutable();
