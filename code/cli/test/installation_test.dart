import 'dart:io';

import 'package:modular_cli_sdk/modular_cli_sdk.dart';
import 'package:modular_cli_sdk/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:docmd_cli/src/installation/docmd_installation.dart';

import 'support/installation_doubles.dart';
import 'support/memory_sink.dart';

void main() {
  group('docmdInstallationConfig', () {
    test('has no alias: docmd has never had one', () {
      expect(docmdInstallationConfig.alias, isNull);
    });

    test('names the repository and executable', () {
      expect(docmdInstallationConfig.repository, equals('ccisnedev/docmd'));
      expect(docmdInstallationConfig.executable, equals('docmd'));
    });

    test('names the same release assets the old PlatformOps did', () {
      expect(
        docmdInstallationConfig.assets,
        equals({
          'linux': 'docmd-linux-x64.tar.gz',
          'windows': 'docmd-windows-x64.zip',
        }),
      );
    });

    test('postUpgradeSteps adds chmod and the user-bin symlink on Linux', () {
      final steps = docmdInstallationConfig.postUpgradeSteps!(
        '/home/test/.docmd',
        LinuxPlatformOps(
          binaryName: 'docmd',
          assetName: 'docmd-linux-x64.tar.gz',
        ),
      );

      expect(steps, hasLength(2));
      expect(steps[0], isA<MakeExecutable>());
      expect(steps[1], isA<LinkUserBin>());
    });

    test('postUpgradeSteps adds nothing on Windows', () {
      final steps = docmdInstallationConfig.postUpgradeSteps!(
        r'C:\Users\test\AppData\Local\docmd',
        WindowsPlatformOps(
          binaryName: 'docmd.exe',
          assetName: 'docmd-windows-x64.zip',
        ),
      );

      expect(steps, isEmpty);
    });

    test('preUninstallSteps removes the user-bin symlink on Linux', () {
      final steps = docmdInstallationConfig.preUninstallSteps!(
        '/home/test/.docmd',
        LinuxPlatformOps(
          binaryName: 'docmd',
          assetName: 'docmd-linux-x64.tar.gz',
        ),
      );

      expect(steps, hasLength(1));
      expect(steps.single, isA<UnlinkUserBin>());
    });

    test('preUninstallSteps adds nothing on Windows', () {
      final steps = docmdInstallationConfig.preUninstallSteps!(
        r'C:\Users\test\AppData\Local\docmd',
        WindowsPlatformOps(
          binaryName: 'docmd.exe',
          assetName: 'docmd-windows-x64.zip',
        ),
      );

      expect(steps, isEmpty);
    });
  });

  group('MakeExecutable', () {
    test('previews the chmod', () {
      final step = MakeExecutable(binaryPath: '/home/test/.docmd/bin/docmd');
      final preview = step.preview();

      expect(preview.verb, equals('chmod'));
      expect(preview.target, equals('/home/test/.docmd/bin/docmd'));
      expect(preview.detail, equals('755'));
    });

    test('runs chmod 755 on the binary', () async {
      String? exe;
      List<String>? args;
      final step = MakeExecutable(
        binaryPath: '/home/test/.docmd/bin/docmd',
        processRunner: (executable, arguments, {workingDirectory}) async {
          exe = executable;
          args = arguments;
          return ProcessResult(0, 0, '', '');
        },
      );

      final outcome = await runCommand(_SingleStepCommand(step));

      expect(exe, equals('chmod'));
      expect(args, equals(['755', '/home/test/.docmd/bin/docmd']));
      expect(outcome.outcomes.single.verb, equals('chmod'));
    });

    test('throws when chmod fails', () async {
      final step = MakeExecutable(
        binaryPath: '/home/test/.docmd/bin/docmd',
        processRunner: (executable, arguments, {workingDirectory}) async =>
            ProcessResult(0, 1, '', 'no such file'),
      );

      expect(
        () => step.perform(_fakeStepContext()),
        throwsA(isA<ProcessException>()),
      );
    });
  });

  group('LinkUserBin', () {
    late Directory home;
    setUp(
      () => home = Directory.systemTemp.createTempSync('docmd_linkuserbin_'),
    );
    tearDown(() {
      if (home.existsSync()) home.deleteSync(recursive: true);
    });

    test('previews the link target', () {
      final step = LinkUserBin(
        platformOps: FakePlatformOps(fakeEnvValue: home.path),
        binaryPath: '/opt/docmd/bin/docmd',
      );

      final preview = step.preview();
      expect(preview.verb, equals('link'));
      expect(
        preview.target,
        equals(p.posix.join(home.path, '.local', 'bin', 'docmd')),
      );
      expect(preview.detail, equals('-> /opt/docmd/bin/docmd'));
    });

    test(
      'creates ~/.local/bin/docmd pointing at the installed binary',
      () async {
        final binary = File(p.join(home.path, 'installed-docmd'))
          ..writeAsStringSync('bin');
        final step = LinkUserBin(
          platformOps: FakePlatformOps(fakeEnvValue: home.path),
          binaryPath: binary.path,
        );

        await step.perform(_fakeStepContext());

        final link = Link(p.posix.join(home.path, '.local', 'bin', 'docmd'));
        expect(link.existsSync(), isTrue);
        expect(link.targetSync(), equals(binary.path));
      },
      skip: Platform.isWindows ? 'symlink creation requires Linux' : null,
    );

    test('throws when the home directory cannot be resolved', () {
      final step = LinkUserBin(
        platformOps: FakePlatformOps(fakeEnvValue: null),
        binaryPath: '/opt/docmd/bin/docmd',
      );

      expect(
        () => step.perform(_fakeStepContext()),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('UnlinkUserBin', () {
    late Directory home;
    setUp(
      () => home = Directory.systemTemp.createTempSync('docmd_unlinkuserbin_'),
    );
    tearDown(() {
      if (home.existsSync()) home.deleteSync(recursive: true);
    });

    test(
      'removes an existing ~/.local/bin/docmd symlink',
      () async {
        final binDir = Directory(p.join(home.path, '.local', 'bin'))
          ..createSync(recursive: true);
        final linkPath = p.join(binDir.path, 'docmd');
        Link(linkPath).createSync(p.join(home.path, 'elsewhere', 'docmd'));

        final step = UnlinkUserBin(
          platformOps: FakePlatformOps(fakeEnvValue: home.path),
        );
        await step.perform(_fakeStepContext());

        expect(Link(linkPath).existsSync(), isFalse);
      },
      skip: Platform.isWindows ? 'symlink creation requires Linux' : null,
    );

    test('does nothing when there is no symlink to remove', () async {
      final step = UnlinkUserBin(
        platformOps: FakePlatformOps(fakeEnvValue: home.path),
      );

      final outcome = await step.perform(_fakeStepContext());

      expect(outcome.verb, equals('unlink'));
    });

    test('throws when the home directory cannot be resolved', () {
      final step = UnlinkUserBin(
        platformOps: FakePlatformOps(fakeEnvValue: null),
      );

      expect(
        () => step.perform(_fakeStepContext()),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('upgrade wiring through docmdInstallationConfig', () {
    test('downloads and applies a newer release', () async {
      final downloader = FakeDownloader();
      final ops = FakePlatformOps(
        assetName: docmdInstallationConfig.assets[Platform.operatingSystem]!,
      );
      final installDir = Directory.systemTemp.createTempSync(
        'docmd_upgrade_wiring_',
      );
      addTearDown(() {
        if (installDir.existsSync()) installDir.deleteSync(recursive: true);
      });
      final binary = File(p.join(installDir.path, 'bin', 'docmd'))
        ..createSync(recursive: true)
        ..writeAsStringSync('outgoing');

      final output = await applyCommand(
        UpgradeCommand(
          UpgradeInput(installDir: installDir.path),
          config: docmdInstallationConfig,
          currentVersion: '0.2.3',
          releaseSource: FakeReleaseSource(
            releases: [_release('v99.0.0', asset: ops.assetName)],
          ),
          platformOps: ops,
          downloader: downloader.call,
          progress: MemorySink().sink,
          runningExecutable: binary.path,
        ),
      );

      expect(output.upgraded, isTrue);
      expect(output.newVersion, equals('99.0.0'));
      expect(downloader.requested, isNotEmpty);
      expect(ops.calls, contains(contains('expandArchive')));
    });

    test('reports no upgrade when already on the latest version', () async {
      final ops = FakePlatformOps(
        assetName: docmdInstallationConfig.assets[Platform.operatingSystem]!,
      );

      final output = await applyCommand(
        UpgradeCommand(
          UpgradeInput(installDir: '/fake/dir'),
          config: docmdInstallationConfig,
          currentVersion: '0.2.3',
          releaseSource: FakeReleaseSource(
            releases: [_release('v0.2.3', asset: ops.assetName)],
          ),
          platformOps: ops,
          progress: MemorySink().sink,
        ),
      );

      expect(output.upgraded, isFalse);
      expect(output.reason, equals('Already on the latest version'));
      expect(ops.calls, isEmpty);
    });
  });

  group('uninstall wiring through docmdInstallationConfig', () {
    test('plans unset then delete, matching the old removal shape', () async {
      final previews = await previewCommand(
        UninstallCommand(
          UninstallInput(installDir: '/fake/dir'),
          config: docmdInstallationConfig,
          platformOps: FakePlatformOps(),
        ),
      );

      expect(previews.map((preview) => preview.verb).toList(), [
        'unset',
        'delete',
      ]);
    });

    test('schedules deletion of the install directory', () async {
      final installDir = Directory.systemTemp.createTempSync(
        'docmd_uninstall_wiring_',
      );
      addTearDown(() {
        if (installDir.existsSync()) installDir.deleteSync(recursive: true);
      });
      final ops = FakePlatformOps();

      await applyCommand(
        UninstallCommand(
          UninstallInput(installDir: installDir.path),
          config: docmdInstallationConfig,
          platformOps: ops,
        ),
      );

      expect(ops.calls, contains('scheduleDeletion(${installDir.path})'));
    });
  });

  group('doctor "release" check (docmdInstallationConfig, no alias)', () {
    test('names docmd, not an alias, in the upgrade hint', () async {
      final cli =
          ModularCli(suggestionDistance: 2, name: 'docmd', version: '0.2.3')
            ..plugin(const DoctorPlugin())
            ..plugin(
              InstallationPlugin(
                config: docmdInstallationConfig,
                releaseSource: FakeReleaseSource(
                  releases: [
                    _release('v99.0.0', asset: 'docmd-linux-x64.tar.gz'),
                  ],
                ),
                platformOps: FakePlatformOps(),
              ),
            );

      final out = MemorySink();
      final code = await cli.run(['doctor'], stdout: out.sink);

      expect(code, equals(0));
      final text = await out.text();
      expect(text, contains('Run "docmd upgrade --apply" to install it.'));
    });
  });
}

CliRelease _release(
  String tag, {
  required String asset,
  String url = 'https://dl.example.test/asset',
}) => CliRelease(
  tagName: tag,
  assets: [CliReleaseAsset(name: asset, downloadUrl: url)],
);

/// Drives a single [Step] through [runCommand]/[applyCommand] without a real
/// [Input]/[Output] pair — [MakeExecutable]'s own success path is exercised
/// this way; its failure path calls [Step.perform] directly instead, since a
/// thrown [ProcessException] there is exactly what [runCommand] is meant to
/// surface as a [StepFailure], not a raw throw.
class _SingleStepCommand implements Command<_NoInput, _NoOutput> {
  _SingleStepCommand(this._step);

  final Step _step;

  @override
  final _NoInput input = _NoInput();

  @override
  String? validate() => null;

  @override
  Future<List<Step>> steps() async => [_step];

  @override
  _NoOutput describe(Execution execution) => _NoOutput();
}

class _NoInput extends Input {
  @override
  Map<String, dynamic> toJson() => {};
}

class _NoOutput extends Output {
  @override
  Map<String, dynamic> toJson() => {};

  @override
  int get exitCode => 0;
}

/// A [StepContext] with nothing in it: none of this file's steps read a
/// prior step's outcome, so an empty one satisfies [Step.perform]'s
/// signature without needing a real [PreviewExecutor] run.
StepContext _fakeStepContext() => StepContext(<Step, Outcome>{});
