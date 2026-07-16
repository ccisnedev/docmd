library;

import 'dart:async';
import 'dart:io';

import 'package:cli_router/cli_router.dart';
import 'package:modular_cli_sdk/modular_cli_sdk.dart';
import 'package:path/path.dart' as p;

class UninstallInput extends Input {
  UninstallInput();

  factory UninstallInput.fromCliRequest(CliRequest req) => UninstallInput();

  static const List<CliParam> params = [];

  @override
  List<CliParam> get schemaFields => params;

  @override
  Map<String, dynamic> toJson() => {};
}

class UninstallOutput extends Output {
  final String status;
  final bool removed;
  final String installPath;

  UninstallOutput({
    required this.status,
    required this.removed,
    required this.installPath,
  });

  @override
  int get exitCode => ExitCode.ok;

  @override
  Map<String, dynamic> toJson() => {
        'status': status,
        'removed': removed,
        'installPath': installPath,
      };

  @override
  String toText() {
    switch (status) {
      case 'scheduled':
        return 'DocMD CLI uninstall scheduled. Restart your shell after this process exits.';
      case 'removed':
        return 'DocMD CLI uninstalled successfully.';
      case 'absent':
        return 'DocMD CLI is not installed.';
      default:
        return 'DocMD CLI uninstall completed.';
    }
  }
}

typedef ScheduleWindowsRemoval = Future<void> Function(String installDir, String binDir);

class UninstallDeps {
  final String platform;
  final String? localAppData;
  final String? homeDirectory;
  final bool Function(String path) directoryExists;
  final bool Function(String path) fileExists;
  final void Function(String path) deleteDirectory;
  final void Function(String path) deleteFile;
  final ScheduleWindowsRemoval scheduleWindowsRemoval;

  UninstallDeps({
    String? platform,
    this.localAppData,
    this.homeDirectory,
    bool Function(String path)? directoryExists,
    bool Function(String path)? fileExists,
    void Function(String path)? deleteDirectory,
    void Function(String path)? deleteFile,
    ScheduleWindowsRemoval? scheduleWindowsRemoval,
  })  : platform = platform ?? (Platform.isWindows ? 'windows' : Platform.operatingSystem),
        directoryExists = directoryExists ?? ((path) => Directory(path).existsSync()),
        fileExists = fileExists ?? ((path) => File(path).existsSync()),
        deleteDirectory =
            deleteDirectory ?? ((path) => Directory(path).deleteSync(recursive: true)),
        deleteFile = deleteFile ?? ((path) => File(path).deleteSync()),
        scheduleWindowsRemoval = scheduleWindowsRemoval ?? _scheduleWindowsRemoval;
}

class UninstallCommand implements Command<UninstallInput, UninstallOutput> {
  @override
  final UninstallInput input;

  final UninstallDeps _deps;

  UninstallCommand(this.input, {UninstallDeps? deps}) : _deps = deps ?? UninstallDeps();

  @override
  String? validate() => null;

  @override
  Future<UninstallOutput> execute() async {
    final installPath = _resolveManagedInstallPath(_deps);
    if (installPath == null) {
      throw UnsupportedError('Unsupported platform: ${_deps.platform}');
    }

    if (!_deps.directoryExists(installPath)) {
      return UninstallOutput(status: 'absent', removed: false, installPath: installPath);
    }

    if (_deps.platform == 'windows') {
      final binDir = _pathContext(_deps).join(installPath, 'bin');
      await _deps.scheduleWindowsRemoval(installPath, binDir);
      return UninstallOutput(status: 'scheduled', removed: true, installPath: installPath);
    }

    if (_deps.platform == 'linux') {
      final linkPath = _pathContext(_deps).join(_requireHomeDirectory(_deps), '.local', 'bin', 'docmd');
      if (_deps.fileExists(linkPath)) {
        _deps.deleteFile(linkPath);
      }

      _deps.deleteDirectory(installPath);
      return UninstallOutput(status: 'removed', removed: true, installPath: installPath);
    }

    throw UnsupportedError('Unsupported platform: ${_deps.platform}');
  }
}

String? _resolveManagedInstallPath(UninstallDeps deps) {
  final paths = _pathContext(deps);

  if (deps.platform == 'windows') {
    final localAppData = deps.localAppData ?? paths.join(_requireHomeDirectory(deps), 'AppData', 'Local');
    return paths.join(localAppData, 'docmd');
  }

  if (deps.platform == 'linux') {
    return paths.join(_requireHomeDirectory(deps), '.docmd');
  }

  return null;
}

String _requireHomeDirectory(UninstallDeps deps) {
  final homeDirectory = deps.homeDirectory ?? Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (homeDirectory == null || homeDirectory.isEmpty) {
    throw StateError('Unable to resolve the current user home directory.');
  }

  return homeDirectory;
}

Future<void> _scheduleWindowsRemoval(String installDir, String binDir) async {
  final tempDir = Directory.systemTemp.createTempSync('docmd_uninstall_');
  final scriptPath = p.join(tempDir.path, 'uninstall.ps1');
  File(scriptPath).writeAsStringSync(
    _windowsUninstallScript(
      installDir: installDir,
      binDir: binDir,
      scriptPath: scriptPath,
      tempDirPath: tempDir.path,
    ),
  );

  await Process.start(
    'powershell',
    ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath],
    mode: ProcessStartMode.detached,
  );
}

String _windowsUninstallScript({
  required String installDir,
  required String binDir,
  required String scriptPath,
  required String tempDirPath,
}) {
  String escape(String value) => value.replaceAll("'", "''");

  return '''













\$ErrorActionPreference = 'SilentlyContinue'

\$installDir = '${escape(installDir)}'
\$binDir = '${escape(binDir)}'
\$scriptPath = '${escape(scriptPath)}'
\$tempDir = '${escape(tempDirPath)}'

\$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
if (\$userPath) {
  \$segments = \$userPath -split ';' | Where-Object {
    \$segment = \$_.Trim()
    if (-not \$segment) { return \$false }
    \$segment.TrimEnd('\\').ToLowerInvariant() -ne \$binDir.TrimEnd('\\').ToLowerInvariant()
  }
  [Environment]::SetEnvironmentVariable('PATH', (\$segments -join ';'), 'User')
}

for (\$attempt = 0; \$attempt -lt 40; \$attempt++) {
  try {
    if (Test-Path \$installDir) {
      Remove-Item \$installDir -Recurse -Force -ErrorAction Stop
    }
    break
  } catch {
    Start-Sleep -Milliseconds 250
  }
}

Remove-Item \$scriptPath -Force -ErrorAction SilentlyContinue
Remove-Item \$tempDir -Force -ErrorAction SilentlyContinue
''';
}

p.Context _pathContext(UninstallDeps deps) {
  return p.Context(style: deps.platform == 'windows' ? p.Style.windows : p.Style.posix);
}