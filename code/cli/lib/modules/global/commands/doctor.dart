library;

import 'package:cli_router/cli_router.dart';
import 'package:modular_cli_sdk/modular_cli_sdk.dart';

import '../../../src/tool_locator.dart';
import '../../../src/version.dart';
import '../../../src/version_check.dart';

class DoctorInput extends Input {
  DoctorInput();

  factory DoctorInput.fromCliRequest(CliRequest req) => DoctorInput();

  @override
  Map<String, dynamic> toJson() => {};
}

class DoctorOutput extends Output {
  final Map<String, bool> checks;
  final Map<String, String> paths;
  final String currentVersion;
  final String? latestVersion;
  final bool updateAvailable;

  DoctorOutput({
    required this.checks,
    required this.paths,
    required this.currentVersion,
    this.latestVersion,
    required this.updateAvailable,
  });

  @override
  Map<String, dynamic> toJson() => {
    'checks': checks,
    'paths': paths,
    'currentVersion': currentVersion,
    if (latestVersion != null) 'latestVersion': latestVersion,
    'updateAvailable': updateAvailable,
  };

  @override
  int get exitCode => checks.values.every((value) => value) ? 0 : 1;

  @override
  String toText() {
    final lines = <String>[
      'DocMD prerequisite check',
      '  docmd: $currentVersion',
    ];

    if (latestVersion != null) {
      final versionStatus = updateAvailable
          ? 'UPDATE AVAILABLE ($latestVersion)'
          : 'up to date';
      lines.add('  update: $versionStatus');
    }

    for (final entry in checks.entries) {
      final status = entry.value ? 'OK' : 'MISSING';
      final pathSuffix = paths[entry.key] == null ? '' : ' (${paths[entry.key]})';
      lines.add('  ${entry.key}: $status$pathSuffix');
    }

    if (updateAvailable) {
      lines.add('');
      lines.add('Run `docmd upgrade` to install the latest release.');
    }

    if (!checks.values.every((value) => value)) {
      lines.add('');
      lines.add('Install the missing tools before using import and render workflows.');
    }

    return lines.join('\n');
  }
}

class DoctorCommand implements Command<DoctorInput, DoctorOutput> {
  @override
  final DoctorInput input;

  final String? Function() _resolvePandocExecutable;
  final String? Function() _resolveLibreOfficeExecutable;
  final Future<VersionCheckResult> Function({required String currentVersion}) _versionChecker;

  DoctorCommand(
    this.input, {
    String? Function()? resolvePandocExecutable,
    String? Function()? resolveLibreOfficeExecutable,
    Future<VersionCheckResult> Function({required String currentVersion})? versionChecker,
  }) : _resolvePandocExecutable = resolvePandocExecutable ?? resolvePandocExecutableDefault,
       _resolveLibreOfficeExecutable = resolveLibreOfficeExecutable ?? resolveLibreOfficeExecutableDefault,
       _versionChecker = versionChecker ?? checkLatestVersion;

  @override
  String? validate() => null;

  @override
  Future<DoctorOutput> execute() async {
    final pandocPath = _resolvePandocExecutable();
    final libreOfficePath = _resolveLibreOfficeExecutable();
    final versionResult = await _versionChecker(currentVersion: docmdVersion);

    return DoctorOutput(
      checks: {
        'pandoc': pandocPath != null,
        'libreoffice': libreOfficePath != null,
      },
      paths: {
        ...?(pandocPath == null ? null : {'pandoc': pandocPath}),
        ...?(libreOfficePath == null ? null : {'libreoffice': libreOfficePath}),
      },
      currentVersion: docmdVersion,
      latestVersion: versionResult.latestVersion,
      updateAvailable: versionResult.updateAvailable,
    );
  }
}

String? resolvePandocExecutableDefault() => resolvePandocExecutable();

String? resolveLibreOfficeExecutableDefault() => resolveLibreOfficeExecutable();
