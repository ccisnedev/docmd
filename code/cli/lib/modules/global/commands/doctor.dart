library;

import 'dart:io';

import 'package:cli_router/cli_router.dart';
import 'package:modular_cli_sdk/modular_cli_sdk.dart';

class DoctorInput extends Input {
  DoctorInput();

  factory DoctorInput.fromCliRequest(CliRequest req) => DoctorInput();

  @override
  Map<String, dynamic> toJson() => {};
}

class DoctorOutput extends Output {
  final Map<String, bool> checks;

  DoctorOutput({required this.checks});

  @override
  Map<String, dynamic> toJson() => {'checks': checks};

  @override
  int get exitCode => checks.values.every((value) => value) ? 0 : 1;

  @override
  String toText() {
    final lines = <String>['DocMD prerequisite check'];

    for (final entry in checks.entries) {
      final status = entry.value ? 'OK' : 'MISSING';
      lines.add('  ${entry.key}: $status');
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

  DoctorCommand(this.input);

  @override
  String? validate() => null;

  @override
  Future<DoctorOutput> execute() async {
    return DoctorOutput(
      checks: {
        'pandoc': _existsOnPath('pandoc'),
        'libreoffice': _existsOnPath(Platform.isWindows ? 'soffice.exe' : 'soffice'),
      },
    );
  }

  bool _existsOnPath(String executable) {
    final lookup = Platform.isWindows ? 'where' : 'which';
    final result = Process.runSync(lookup, [executable]);
    return result.exitCode == 0;
  }
}
