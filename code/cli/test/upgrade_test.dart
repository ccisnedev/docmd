import 'package:test/test.dart';

import 'package:docmd_cli/modules/global/commands/upgrade.dart';
import 'package:docmd_cli/src/version.dart';

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
      final extracted = <List<String>>[];
      final chmodCalls = <List<String>>[];
      final deleted = <String>[];
      final downloads = <List<String>>[];

      final output = await UpgradeCommand(
        UpgradeInput(),
        deps: UpgradeDeps(
          platform: 'linux',
          homeDirectory: '/home/test',
          directoryExists: (path) => path == '/home/test/.docmd',
          fetchJson: (_, _) async => {
            'tag_name': 'v0.0.6',
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
          extractTarGz: (archivePath, destDir) async {
            extracted.add([archivePath, destDir]);
          },
          execFile: (executable, arguments) async => '0.0.6',
          ensureDirectory: (path) async {
            createdDirectories.add(path);
          },
          chmodPath: (path, mode) async {
            chmodCalls.add([path, mode]);
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
      expect(output.newVersion, equals('0.0.6'));
      expect(downloads.single.first, contains('docmd-linux-x64.tar.gz'));
      expect(extracted.single, equals(['/tmp/docmd-0.0.6-docmd-linux-x64.tar.gz', '/home/test/.docmd']));
      expect(chmodCalls.single, equals(['/home/test/.docmd/bin/docmd', '755']));
      expect(
        symlinks.single,
        equals(['/home/test/.docmd/bin/docmd', '/home/test/.local/bin/docmd']),
      );
      expect(createdDirectories, contains('/home/test/.docmd'));
      expect(createdDirectories, contains('/home/test/.local/bin'));
      expect(deleted, contains('/tmp/docmd-0.0.6-docmd-linux-x64.tar.gz'));
    });
  });
}