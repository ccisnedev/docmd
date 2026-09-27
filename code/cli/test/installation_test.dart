import 'dart:convert';

import 'package:modular_cli_sdk/modular_cli_sdk.dart';
import 'package:modular_cli_sdk/testing.dart';
import 'package:test/test.dart';

const _config = CliInstallationConfig(
  repository: 'ccisnedev/docmd',
  tagPrefix: 'v',
  executable: 'docmd',
  alias: 'dm',
  assets: {'linux': 'docmd-linux-x64', 'windows': 'docmd-windows-x64.exe'},
);

void main() {
  group('UpgradeCommand (docmd_cli via modular_cli_sdk fakes)', () {
    test('installs a newer release over the resolved executable', () async {
      final fileSystem = _FakeFileSystem(
        resolve: {'docmd': '/usr/local/bin/docmd'},
        regularFiles: {'/usr/local/bin/docmd'},
      );
      final command = UpgradeCommand(
        UpgradeInput(),
        config: _config,
        releaseSource: _FakeReleaseSource([
          const CliRelease(
            tagName: 'v9.9.9',
            assets: [
              CliReleaseAsset(
                name: 'docmd-linux-x64',
                downloadUrl: 'https://example.com/docmd-linux-x64',
              ),
            ],
          ),
        ]),
        downloader: _FakeDownloader(utf8.encode('new binary')),
        fileSystem: fileSystem,
        platform: _FakePlatform('linux'),
        currentVersion: '0.1.0',
      );

      final output = await applyCommand(command);

      expect(output.exitCode, equals(ExitCode.ok));
      expect(output.installedVersion, equals('9.9.9'));
      expect(
        output.stepsCompleted,
        equals(['docmd-linux-x64', '/usr/local/bin/docmd']),
      );
      expect(fileSystem.written, hasLength(1));
      expect(fileSystem.written.single.path, equals('/usr/local/bin/docmd'));
    });

    test('has nothing to do when already on the latest version', () async {
      final fileSystem = _FakeFileSystem(
        resolve: {'docmd': '/usr/local/bin/docmd'},
      );
      final command = UpgradeCommand(
        UpgradeInput(),
        config: _config,
        releaseSource: _FakeReleaseSource([
          const CliRelease(tagName: 'v0.1.0', assets: []),
        ]),
        downloader: _FakeDownloader(const []),
        fileSystem: fileSystem,
        platform: _FakePlatform('linux'),
        currentVersion: '0.1.0',
      );

      final output = await applyCommand(command);

      expect(command.nothingToDo, contains('already on the latest version'));
      expect(output.stepsCompleted, isEmpty);
      expect(fileSystem.written, isEmpty);
    });
  });

  group('UninstallCommand (docmd_cli via modular_cli_sdk fakes)', () {
    test(
      'schedules removal instead of deleting outright on Windows (issue #12)',
      () async {
        final fileSystem = _FakeFileSystem(
          resolve: {'docmd': r'C:\tools\docmd.exe', 'dm': null},
        );
        final launcher = _FakeProcessLauncher(currentPid: 4242);
        final command = UninstallCommand(
          UninstallInput(),
          config: _config,
          fileSystem: fileSystem,
          platform: _FakePlatform('windows'),
          processLauncher: launcher,
        );

        final output = await applyCommand(command);

        expect(output.exitCode, equals(ExitCode.ok));
        expect(output.removed, isEmpty);
        expect(output.scheduled, equals([r'C:\tools\docmd.exe']));
        expect(fileSystem.renamed, hasLength(1));
        expect(fileSystem.renamed.single.from, equals(r'C:\tools\docmd.exe'));
        expect(
          fileSystem.renamed.single.to,
          equals(r'C:\tools\docmd.exe.uninstall-4242.old'),
        );
        expect(launcher.cleanupCalls, hasLength(1));
        expect(launcher.cleanupCalls.single['parentPid'], equals(4242));
      },
    );

    test(
      'removes the alias and the executable outright on Linux, unlike Windows',
      () async {
        final fileSystem = _FakeFileSystem(
          resolve: {
            'docmd': '/home/test/.local/bin/docmd',
            'dm': '/home/test/.local/bin/dm',
          },
          sameFileFn: (a, b) => true,
        );
        final command = UninstallCommand(
          UninstallInput(),
          config: _config,
          fileSystem: fileSystem,
          platform: _FakePlatform('linux'),
          processLauncher: _FakeProcessLauncher(),
        );

        final output = await applyCommand(command);

        expect(output.exitCode, equals(ExitCode.ok));
        expect(output.scheduled, isEmpty);
        expect(
          output.removed,
          equals(['/home/test/.local/bin/dm', '/home/test/.local/bin/docmd']),
        );
        expect(
          fileSystem.deleted,
          equals(['/home/test/.local/bin/dm', '/home/test/.local/bin/docmd']),
        );
      },
    );

    test('has nothing to do when the executable is not on PATH', () async {
      final fileSystem = _FakeFileSystem(resolve: {'docmd': null, 'dm': null});
      final command = UninstallCommand(
        UninstallInput(),
        config: _config,
        fileSystem: fileSystem,
        platform: _FakePlatform('linux'),
        processLauncher: _FakeProcessLauncher(),
      );

      final output = await applyCommand(command);

      expect(command.nothingToDo, contains('is not on PATH'));
      expect(output.removed, isEmpty);
      expect(output.scheduled, isEmpty);
    });

    test(
      'reports a file-access-denied failure, keeping what already ran, when a delete fails',
      () async {
        final fileSystem = _FakeFileSystem(
          resolve: {
            'docmd': '/home/test/.local/bin/docmd',
            'dm': '/home/test/.local/bin/dm',
          },
          sameFileFn: (a, b) => true,
          failDeleteOf: '/home/test/.local/bin/docmd',
        );
        final command = UninstallCommand(
          UninstallInput(),
          config: _config,
          fileSystem: fileSystem,
          platform: _FakePlatform('linux'),
          processLauncher: _FakeProcessLauncher(),
        );

        try {
          await applyCommand(command);
          fail('expected a CommandException');
        } on CommandException catch (e) {
          expect(e.id, equals('file-access-denied'));
          expect(e.exitCode, equals(ExitCode.genericError));
          expect(e.details?['removed'], equals(['/home/test/.local/bin/dm']));
        }
      },
    );
  });
}

class _FakeFileSystem implements CliFileSystem {
  _FakeFileSystem({
    Map<String, String?> resolve = const {},
    Set<String> regularFiles = const {},
    bool Function(String a, String b)? sameFileFn,
    this.failDeleteOf,
  }) : _resolve = resolve,
       _regularFiles = regularFiles,
       _sameFileFn = sameFileFn;

  final Map<String, String?> _resolve;
  final Set<String> _regularFiles;
  final bool Function(String a, String b)? _sameFileFn;
  final String? failDeleteOf;

  final List<String> deleted = [];
  final List<({String from, String to})> renamed = [];
  final List<({String path, List<int> bytes})> written = [];

  @override
  String? resolveOnPath(String name) => _resolve[name];

  @override
  Future<void> writeExecutable(
    String path,
    List<int> bytes, {
    required Future<void> Function() revalidate,
  }) async {
    await revalidate();
    written.add((path: path, bytes: bytes));
  }

  @override
  Future<void> delete(String path) async {
    if (path == failDeleteOf) {
      throw Exception('permission denied');
    }
    deleted.add(path);
  }

  @override
  Future<void> rename(String from, String to) async {
    renamed.add((from: from, to: to));
  }

  @override
  String canonicalize(String path) => path;

  @override
  bool sameFile(String a, String b) => _sameFileFn?.call(a, b) ?? (a == b);

  @override
  bool isRegularFile(String path) => _regularFiles.contains(path);
}

class _FakePlatform implements CliPlatform {
  _FakePlatform(this.operatingSystem);

  @override
  final String operatingSystem;
}

class _FakeProcessLauncher implements CliProcessLauncher {
  _FakeProcessLauncher({this.currentPid = 1});

  @override
  final int currentPid;

  final List<Map<String, Object?>> cleanupCalls = [];

  @override
  Future<void> startCleanupWorker(Map<String, Object?> payload) async {
    cleanupCalls.add(payload);
  }
}

class _FakeReleaseSource implements CliReleaseSource {
  _FakeReleaseSource(this.releases);

  final List<CliRelease> releases;

  @override
  Future<List<CliRelease>> listReleases(String repository) async => releases;
}

class _FakeDownloader implements CliDownloader {
  _FakeDownloader(this.bytes);

  final List<int> bytes;

  @override
  Future<List<int>> download(String url) async => bytes;
}
