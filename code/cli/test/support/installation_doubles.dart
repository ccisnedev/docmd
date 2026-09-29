/// Doubles for docmd's `InstallationPlugin` wiring: fakes for the release
/// lookup, the download, and the platform ops `upgrade`/`uninstall` drive
/// through, so a test never reaches the network, extracts a real archive, or
/// touches a real PATH.
///
/// Modeled on `modular_cli_sdk`'s own `test/plugins/installation_doubles.dart`
/// (macss's and inquiry's `FakePlatformOps` before that): a calls list a test
/// asserts against, rather than a mock framework.
library;

import 'dart:io';

import 'package:modular_cli_sdk/modular_cli_sdk.dart';

class FakeReleaseSource implements CliReleaseSource {
  FakeReleaseSource({this.releases = const [], this.error});

  final List<CliRelease> releases;
  final Object? error;

  int latestReleaseCalls = 0;
  int listReleasesCalls = 0;

  @override
  Future<CliRelease?> latestRelease(String repository) async {
    latestReleaseCalls++;
    if (error != null) throw error!;
    return releases.isEmpty ? null : releases.first;
  }

  @override
  Future<List<CliRelease>> listReleases(String repository) async {
    listReleasesCalls++;
    if (error != null) throw error!;
    return releases;
  }
}

/// A callable stand-in for [Downloader]: `FakeDownloader()` itself is a
/// `Future<void> Function(String, String)`, so it can be passed anywhere a
/// [Downloader] is expected.
class FakeDownloader {
  FakeDownloader({this.error});

  final Object? error;

  final List<String> requested = [];

  Future<void> call(String url, String destination) async {
    requested.add(url);
    if (error != null) throw error!;
  }
}

/// A [PlatformOps] that records every call instead of touching a real
/// archive, environment, or child process. Deliberately does **not** extend
/// [LinuxPlatformOps]/[WindowsPlatformOps]: `docmdInstallationConfig`'s
/// `postUpgradeSteps`/`preUninstallSteps` gate docmd's own extra Linux steps
/// on `platformOps is LinuxPlatformOps`, so a fake standing in for either
/// platform never triggers them — exactly what a test of the base
/// upgrade/uninstall wiring (not docmd's own added steps) wants.
class FakePlatformOps implements PlatformOps {
  FakePlatformOps({
    this.binaryName = 'docmd',
    this.assetName = 'docmd-linux-x64.tar.gz',
    this.fakeEnvValue,
  });

  @override
  final String binaryName;

  @override
  final String assetName;

  final String? fakeEnvValue;

  final List<String> calls = [];

  @override
  Future<void> expandArchive(String archivePath, String destDir) async {
    calls.add('expandArchive($archivePath, $destDir)');
  }

  @override
  String? getEnvVariable(String name) {
    calls.add('getEnvVariable($name)');
    return fakeEnvValue;
  }

  @override
  Future<void> setEnvVariable(String name, String value) async {
    calls.add('setEnvVariable($name, $value)');
  }

  @override
  Future<ProcessResult> runPostInstall(
    String installDir, {
    Duration? timeout,
  }) async {
    calls.add('runPostInstall($installDir)');
    return ProcessResult(0, 0, '', '');
  }

  @override
  Future<void> scheduleDeletion(String dir) async {
    calls.add('scheduleDeletion($dir)');
  }
}
