import 'package:test/test.dart';

import 'package:docmd_cli/modules/global/commands/upgrade.dart';
import 'package:docmd_cli/src/platform/platform_ops.dart';
import 'package:docmd_cli/src/version.dart';

/// Records the platform operations the upgrade flow drives, so the test can
/// assert what got extracted and made executable without touching the OS.
class _FakePlatformOps implements PlatformOps {
  final List<List<String>> expanded = [];
  final List<String> executables = [];

  @override
  String get assetName => 'docmd-linux-x64.tar.gz';

  @override
  String get binaryName => 'docmd';

  @override
  Future<void> expandArchive(String archivePath, String destDir) async {
    expanded.add([archivePath, destDir]);
  }

  @override
  Future<void> makeExecutable(String path) async {
    executables.add(path);
  }
}

void main() {
  group('Upgrade Command', () {
    test('returns absent when the managed install directory does not exist', () async {
      var fetched = false;

      final output = await UpgradeCommand(
        UpgradeInput(),
        deps: UpgradeDeps(
          platform: 'linux',
          homeDirectory: '/home/test',
          directoryExists: (_) => false,
          fetchJson: (_, _) async {
            fetched = true;
            return {};
          },
        ),
      ).execute();

      expect(output.status, equals('absent'));
      expect(output.upgraded, isFalse);
      expect(fetched, isFalse);
    });

    test('reports already on the latest version without downloading', () async {
      var downloaded = false;

      final output = await UpgradeCommand(
        UpgradeInput(),
        deps: UpgradeDeps(
          platform: 'linux',
          homeDirectory: '/home/test',
          directoryExists: (_) => true,
          fetchJson: (_, _) async => {
            'tag_name': 'v$docmdVersion',
            'assets': <Map<String, dynamic>>[],
          },
          downloadFile: (_, _, _) async {
            downloaded = true;
          },
        ),
      ).execute();

      expect(output.status, equals('up-to-date'));
      expect(output.upgraded, isFalse);
      expect(downloaded, isFalse);
      expect(output.toText(), equals('Already on the latest version.'));
    });

    test('downloads and applies a newer Linux release', () async {
      final createdDirectories = <String>[];
      final symlinks = <List<String>>[];
      final deleted = <String>[];
      final downloads = <List<String>>[];
      final platformOps = _FakePlatformOps();

      // A version that stays ahead of the real one across future bumps, so this
      // "a newer release exists" test does not need editing every release.
      const newer = '99.0.0';

      final output = await UpgradeCommand(
        UpgradeInput(),
        deps: UpgradeDeps(
          platform: 'linux',
          homeDirectory: '/home/test',
          platformOps: platformOps,
          directoryExists: (path) => path == '/home/test/.docmd',
          fetchJson: (_, _) async => {
            'tag_name': 'v$newer',
            'assets': [
              {
                'name': 'docmd-linux-x64.tar.gz',
                'browser_download_url': 'https://example.test/docmd-linux-x64.tar.gz',
              },
            ],
          },
          downloadFile: (url, destPath, headers) async {
            downloads.add([url, destPath, headers['User-Agent'] ?? '']);
          },
          // Production reality: `docmd version` has no toText(), so the binary
          // prints the labelled JSON "version: 99.0.0". The reported version must
          // NOT be scraped from this — it comes from the release tag.
          execFile: (executable, arguments) async => 'version: $newer',
          ensureDirectory: (path) async {
            createdDirectories.add(path);
          },
          ensureSymlink: (targetPath, linkPath) async {
            symlinks.add([targetPath, linkPath]);
          },
          deletePath: (path) async {
            deleted.add(path);
          },
          tempDirectoryPath: () => '/tmp',
        ),
      ).execute();

      expect(output.status, equals('upgraded'));
      expect(output.upgraded, isTrue);
      expect(output.newVersion, equals(newer));
      // The upgrade line shows the clean tag version, not "version: 99.0.0".
      expect(output.toText(), equals('Upgraded: $docmdVersion -> $newer'));
      expect(downloads.single.first, contains('docmd-linux-x64.tar.gz'));
      // Extraction and the execute bit go through the platform seam.
      expect(
        platformOps.expanded.single,
        equals(['/tmp/docmd-$newer-docmd-linux-x64.tar.gz', '/home/test/.docmd']),
      );
      expect(platformOps.executables.single, equals('/home/test/.docmd/bin/docmd'));
      expect(
        symlinks.single,
        equals(['/home/test/.docmd/bin/docmd', '/home/test/.local/bin/docmd']),
      );
      expect(createdDirectories, contains('/home/test/.docmd'));
      expect(createdDirectories, contains('/home/test/.local/bin'));
      expect(deleted, contains('/tmp/docmd-$newer-docmd-linux-x64.tar.gz'));
    });
  });
}