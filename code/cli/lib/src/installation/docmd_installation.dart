library;

import 'dart:io';

import 'package:modular_cli_sdk/modular_cli_sdk.dart';
import 'package:path/path.dart' as p;

import '../process_runner.dart';

/// The `InstallationPlugin` config for docmd's own `upgrade`/`uninstall`,
/// replacing docmd's hand-rolled commands and `PlatformOps` abstraction.
///
/// No alias: docmd has never had one. `CliInstallationConfig.alias` being
/// optional (SDK issue #35) is exactly what makes this possible without
/// forcing a dummy value — `upgrade`/`uninstall` never touched an alias
/// shim anyway (that remains docmd's own install script's job), so nothing
/// about their own behavior changes; only the doctor "release" check's hint
/// names `docmd` instead.
///
/// [postUpgradeSteps] and [preUninstallSteps] restore the one piece of
/// docmd-specific behavior the plugin's own steps do not cover: the Linux
/// `~/.local/bin/docmd` symlink docmd's own `install.sh` creates and that
/// docmd's PATH actually depends on (not `installDir/bin`, which is what the
/// plugin's own `UnsetFromPath` assumes and what `LinuxPlatformOps` treats as
/// a no-op to write — see the PR body's parity table for why that mismatch
/// is reported rather than forced away), and the `chmod 755` docmd's own
/// upgrade always applied to the freshly extracted binary.
final CliInstallationConfig docmdInstallationConfig = CliInstallationConfig(
  repository: 'ccisnedev/docmd',
  executable: 'docmd',
  assets: const {
    'linux': 'docmd-linux-x64.tar.gz',
    'windows': 'docmd-windows-x64.zip',
  },
  postUpgradeSteps: (installDir, platformOps) {
    if (platformOps is! LinuxPlatformOps) return const [];
    final binaryPath = p.join(installDir, 'bin', 'docmd');
    return [
      MakeExecutable(binaryPath: binaryPath),
      LinkUserBin(platformOps: platformOps, binaryPath: binaryPath),
    ];
  },
  preUninstallSteps: (installDir, platformOps) {
    if (platformOps is! LinuxPlatformOps) return const [];
    return [UnlinkUserBin(platformOps: platformOps)];
  },
);

/// Restores docmd's own `chmod 755` on the freshly extracted Linux binary.
///
/// `LinuxPlatformOps.expandArchive` (`tar xzf`) trusts the archive's own
/// permission bits; docmd's old `upgrade` never did, and always set the
/// executable bit explicitly after extraction. This step preserves that
/// guarantee instead of silently dropping it.
class MakeExecutable implements Step {
  MakeExecutable({required this.binaryPath, ProcessRunner? processRunner})
    : _run = processRunner ?? runProcess;

  final String binaryPath;
  final ProcessRunner _run;

  @override
  Preview preview() =>
      Preview(verb: 'chmod', target: binaryPath, detail: '755');

  @override
  Future<Outcome> perform(StepContext context) async {
    final result = await _run('chmod', ['755', binaryPath]);
    if (result.exitCode != 0) {
      throw ProcessException(
        'chmod',
        ['755', binaryPath],
        '${result.stderr}'.trim(),
        result.exitCode,
      );
    }
    return Outcome(verb: 'chmod', target: binaryPath);
  }
}

/// Recreates docmd's own `~/.local/bin/docmd -> installDir/bin/docmd`
/// symlink after an upgrade, mirroring the old (now removed)
/// `LinuxPlatformOps.linkIntoUserPath`.
class LinkUserBin implements Step {
  LinkUserBin({required this.platformOps, required this.binaryPath});

  final PlatformOps platformOps;
  final String binaryPath;

  @override
  Preview preview() => Preview(
    verb: 'link',
    target: _resolveLinkPath() ?? '~/.local/bin/docmd',
    detail: '-> $binaryPath',
  );

  @override
  Future<Outcome> perform(StepContext context) async {
    final linkPath = _resolveLinkPath();
    if (linkPath == null) {
      throw StateError(
        'Unable to resolve the home directory to link docmd into PATH.',
      );
    }

    Directory(p.posix.dirname(linkPath)).createSync(recursive: true);
    final link = Link(linkPath);
    if (link.existsSync()) {
      link.deleteSync();
    } else if (File(linkPath).existsSync()) {
      File(linkPath).deleteSync();
    }
    link.createSync(binaryPath);

    return Outcome(verb: 'link', target: linkPath, values: {'to': binaryPath});
  }

  String? _resolveLinkPath() {
    final home = platformOps.getEnvVariable('HOME');
    if (home == null || home.isEmpty) return null;
    return p.posix.join(home, '.local', 'bin', 'docmd');
  }
}

/// Removes the `~/.local/bin/docmd` symlink [LinkUserBin] manages, mirroring
/// the old uninstall command's own symlink cleanup.
class UnlinkUserBin implements Step {
  UnlinkUserBin({required this.platformOps});

  final PlatformOps platformOps;

  @override
  Preview preview() => Preview(
    verb: 'unlink',
    target: _resolveLinkPath() ?? '~/.local/bin/docmd',
  );

  @override
  Future<Outcome> perform(StepContext context) async {
    final linkPath = _resolveLinkPath();
    if (linkPath == null) {
      throw StateError(
        'Unable to resolve the home directory to unlink docmd from PATH.',
      );
    }

    final link = Link(linkPath);
    if (link.existsSync()) {
      link.deleteSync();
    } else if (File(linkPath).existsSync()) {
      File(linkPath).deleteSync();
    }

    return Outcome(verb: 'unlink', target: linkPath);
  }

  String? _resolveLinkPath() {
    final home = platformOps.getEnvVariable('HOME');
    if (home == null || home.isEmpty) return null;
    return p.posix.join(home, '.local', 'bin', 'docmd');
  }
}
