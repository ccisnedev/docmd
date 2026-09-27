import 'package:test/test.dart';

import 'package:docmd_cli/modules/global/commands/uninstall.dart';

void main() {
  group('Uninstall Command', () {
    test('schedules managed uninstall on Windows', () async {
      final scheduled = <List<String>>[];

      final command = UninstallCommand(
        UninstallInput(),
        deps: UninstallDeps(
          platform: 'windows',
          localAppData: r'C:\Users\test\AppData\Local',
          homeDirectory: r'C:\Users\test',
          directoryExists: (_) => true,
          fileExists: (_) => false,
          deleteDirectory: (_) {},
          deleteFile: (_) {},
          scheduleWindowsRemoval: (installDir, binDir) async {
            scheduled.add([installDir, binDir]);
          },
        ),
      );

      final output = await command.execute();

      expect(output.status, equals('scheduled'));
      expect(output.removed, isTrue);
      expect(output.installPath, endsWith(r'docmd'));
      expect(scheduled, hasLength(1));
      expect(scheduled.single.first, equals(output.installPath));
      expect(scheduled.single.last, endsWith(r'docmd\bin'));
    });

    test('removes managed install and symlink on Linux', () async {
      final deletedDirectories = <String>[];
      final deletedFiles = <String>[];

      final command = UninstallCommand(
        UninstallInput(),
        deps: UninstallDeps(
          platform: 'linux',
          homeDirectory: '/home/test',
          directoryExists: (targetPath) => targetPath == '/home/test/.docmd',
          fileExists: (targetPath) => targetPath == '/home/test/.local/bin/docmd',
          deleteDirectory: deletedDirectories.add,
          deleteFile: deletedFiles.add,
          scheduleWindowsRemoval: (_, _) async {
            fail('Windows uninstall should not run on Linux');
          },
        ),
      );

      final output = await command.execute();

      expect(output.status, equals('removed'));
      expect(output.removed, isTrue);
      expect(deletedDirectories, equals(['/home/test/.docmd']));
      expect(deletedFiles, equals(['/home/test/.local/bin/docmd']));
    });
  });
}