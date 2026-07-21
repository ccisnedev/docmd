library;

import 'dart:io';

import 'package:path/path.dart' as p;

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

  /// Moves the binary at [binaryPath] aside before it is overwritten, when the
  /// OS would otherwise lock it (Windows, and only when [runningExecutable] is
  /// that same binary). A no-op where a running binary can be overwritten in
  /// place (Linux).
  Future<void> backupRunningBinary(
    String binaryPath, {
    required String runningExecutable,
  });

  /// Removes any backup left by [backupRunningBinary]. A no-op where none is made.
  Future<void> removeBackup(String binaryPath);

  /// Links [binaryPath] into the user's PATH (Linux: `~/.local/bin/docmd`). A
  /// no-op where the managed install directory is already the invocation point
  /// (Windows). Throws if it needs [userHome] and it is unresolved.
  Future<void> linkIntoUserPath(String binaryPath, {required String? userHome});

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

  @override
  Future<void> backupRunningBinary(
    String binaryPath, {
    required String runningExecutable,
  }) async {
    // Linux keeps the running process's inode when the file is replaced, so the
    // binary can be overwritten in place — no backup needed.
  }

  @override
  Future<void> removeBackup(String binaryPath) async {}

  @override
  Future<void> linkIntoUserPath(String binaryPath, {required String? userHome}) async {
    if (userHome == null || userHome.isEmpty) {
      throw StateError(
        'Unable to resolve the home directory to link docmd into PATH.',
      );
    }
    final linkPath = p.posix.join(userHome, '.local', 'bin', 'docmd');
    Directory(p.posix.dirname(linkPath)).createSync(recursive: true);

    final link = Link(linkPath);
    if (link.existsSync()) {
      link.deleteSync();
    } else if (File(linkPath).existsSync()) {
      File(linkPath).deleteSync();
    }
    link.createSync(binaryPath);
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

  @override
  Future<void> backupRunningBinary(
    String binaryPath, {
    required String runningExecutable,
  }) async {
    final replacingSelf =
        p.windows.normalize(runningExecutable).toLowerCase() ==
        p.windows.normalize(binaryPath).toLowerCase();
    if (!replacingSelf || !File(binaryPath).existsSync()) {
      return;
    }
    final backup = File('$binaryPath.bak');
    if (backup.existsSync()) {
      backup.deleteSync();
    }
    File(binaryPath).renameSync(backup.path);
  }

  @override
  Future<void> removeBackup(String binaryPath) async {
    final backup = File('$binaryPath.bak');
    if (backup.existsSync()) {
      try {
        backup.deleteSync();
      } on FileSystemException {
        // The just-replaced binary may still be held open; leave it for the
        // next upgrade to clean up.
      }
    }
  }

  @override
  Future<void> linkIntoUserPath(String binaryPath, {required String? userHome}) async {
    // The managed install directory is already the invocation point on Windows.
  }
}
