library;

import 'dart:io';

import '../process_runner.dart';

/// Cross-platform abstraction for the OS-specific shell operations `upgrade`
/// needs: naming the release asset and binary, extracting the archive, and
/// setting the execute bit.
///
/// Modelled on the sibling `inquiry` CLI's PlatformOps. It exists so the
/// platform-varying commands are polymorphic (no `if (platform == 'windows')`
/// scattered through the command) and, because each implementation takes the
/// shared [ProcessRunner], so the exact shell commands are unit-testable — the
/// gap that let a broken self-updater ship unnoticed.
abstract class PlatformOps {
  /// The compiled binary name for this platform (`docmd` or `docmd.exe`).
  String get binaryName;

  /// The release asset name for this platform.
  String get assetName;

  /// Extracts [archivePath] into [destDir] (tar on Linux, Expand-Archive on
  /// Windows). Throws [ProcessException] if the command fails.
  Future<void> expandArchive(String archivePath, String destDir);

  /// Marks [path] executable. A no-op on Windows, which has no execute bit.
  Future<void> makeExecutable(String path);

  /// The implementation for [platform] (`windows`/`win32`/`linux`), or null when
  /// the platform is unsupported so the caller can report it gracefully.
  static PlatformOps? forPlatform(String platform, {ProcessRunner? processRunner}) {
    switch (platform) {
      case 'windows':
      case 'win32':
        return WindowsPlatformOps(processRunner: processRunner);
      case 'linux':
        return LinuxPlatformOps(processRunner: processRunner);
      default:
        return null;
    }
  }
}

class LinuxPlatformOps implements PlatformOps {
  final ProcessRunner _runProcess;

  LinuxPlatformOps({ProcessRunner? processRunner})
    : _runProcess = processRunner ?? runProcess;

  @override
  String get binaryName => 'docmd';

  @override
  String get assetName => 'docmd-linux-x64.tar.gz';

  @override
  Future<void> expandArchive(String archivePath, String destDir) async {
    await _run('tar', ['xzf', archivePath, '-C', destDir]);
  }

  @override
  Future<void> makeExecutable(String path) async {
    await _run('chmod', ['755', path]);
  }

  Future<void> _run(String executable, List<String> arguments) async {
    final result = await _runProcess(executable, arguments);
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        arguments,
        '${result.stderr}'.trim(),
        result.exitCode,
      );
    }
  }
}

class WindowsPlatformOps implements PlatformOps {
  final ProcessRunner _runProcess;

  WindowsPlatformOps({ProcessRunner? processRunner})
    : _runProcess = processRunner ?? runProcess;

  @override
  String get binaryName => 'docmd.exe';

  @override
  String get assetName => 'docmd-windows-x64.zip';

  @override
  Future<void> expandArchive(String archivePath, String destDir) async {
    final result = await _runProcess('powershell', [
      '-NoProfile',
      '-Command',
      "Expand-Archive -Path '$archivePath' -DestinationPath '$destDir' -Force",
    ]);
    if (result.exitCode != 0) {
      throw ProcessException(
        'powershell',
        ['Expand-Archive', archivePath, destDir],
        '${result.stderr}'.trim(),
        result.exitCode,
      );
    }
  }

  @override
  Future<void> makeExecutable(String path) async {
    // No execute bit on Windows.
  }
}
