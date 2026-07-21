import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:docmd_cli/src/platform/platform_ops.dart';

void main() {
  group('LinuxPlatformOps', () {
    test('names the linux asset and binary', () {
      final ops = LinuxPlatformOps();
      expect(ops.assetName, equals('docmd-linux-x64.tar.gz'));
      expect(ops.binaryName, equals('docmd'));
    });

    test('expands a .tar.gz with tar', () async {
      String? exe;
      List<String>? args;
      final ops = LinuxPlatformOps(
        processRunner: (executable, arguments, {workingDirectory}) async {
          exe = executable;
          args = arguments;
          return ProcessResult(0, 0, '', '');
        },
      );

      await ops.expandArchive('/tmp/docmd.tar.gz', '/home/u/.docmd');

      expect(exe, equals('tar'));
      expect(args, equals(['xzf', '/tmp/docmd.tar.gz', '-C', '/home/u/.docmd']));
    });

    test('makes the binary executable with chmod 755', () async {
      final calls = <List<String>>[];
      final ops = LinuxPlatformOps(
        processRunner: (executable, arguments, {workingDirectory}) async {
          calls.add([executable, ...arguments]);
          return ProcessResult(0, 0, '', '');
        },
      );

      await ops.makeExecutable('/home/u/.docmd/bin/docmd');

      expect(calls.single, equals(['chmod', '755', '/home/u/.docmd/bin/docmd']));
    });

    test('throws when a shell command fails', () async {
      final ops = LinuxPlatformOps(
        processRunner: (executable, arguments, {workingDirectory}) async =>
            ProcessResult(0, 1, '', 'tar: broken archive'),
      );

      expect(
        () => ops.expandArchive('/tmp/x.tar.gz', '/dest'),
        throwsA(isA<ProcessException>()),
      );
    });
  });

  group('WindowsPlatformOps', () {
    test('names the windows asset and binary', () {
      final ops = WindowsPlatformOps();
      expect(ops.assetName, equals('docmd-windows-x64.zip'));
      expect(ops.binaryName, equals('docmd.exe'));
    });

    test('expands a .zip with PowerShell Expand-Archive', () async {
      String? exe;
      List<String>? args;
      final ops = WindowsPlatformOps(
        processRunner: (executable, arguments, {workingDirectory}) async {
          exe = executable;
          args = arguments;
          return ProcessResult(0, 0, '', '');
        },
      );

      await ops.expandArchive(r'C:\Temp\docmd.zip', r'C:\Users\u\AppData\Local\docmd');

      expect(exe, equals('powershell'));
      expect(args, contains('-NoProfile'));
      final command = args!.last;
      expect(command, contains('Expand-Archive'));
      expect(command, contains(r'C:\Temp\docmd.zip'));
      expect(command, contains(r'C:\Users\u\AppData\Local\docmd'));
      expect(command, contains('-Force'));
    });

    test('makeExecutable is a no-op — Windows has no execute bit', () async {
      var ran = false;
      final ops = WindowsPlatformOps(
        processRunner: (executable, arguments, {workingDirectory}) async {
          ran = true;
          return ProcessResult(0, 0, '', '');
        },
      );

      await ops.makeExecutable(r'C:\Users\u\AppData\Local\docmd\bin\docmd.exe');

      expect(ran, isFalse);
    });
  });

  group('WindowsPlatformOps install steps', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('docmd_winops_'));
    tearDown(() => dir.deleteSync(recursive: true));

    // Windows locks a running .exe, so upgrade must move it aside before writing
    // the new one over the same path.
    test('backs up the running binary before it is replaced', () async {
      final binary = File(p.join(dir.path, 'docmd.exe'))..writeAsStringSync('old');

      await WindowsPlatformOps()
          .backupRunningBinary(binary.path, runningExecutable: binary.path);

      expect(binary.existsSync(), isFalse);
      expect(File('${binary.path}.bak').readAsStringSync(), equals('old'));
    });

    test('does not back up a binary that is not the running one', () async {
      final binary = File(p.join(dir.path, 'docmd.exe'))..writeAsStringSync('old');

      await WindowsPlatformOps().backupRunningBinary(
        binary.path,
        runningExecutable: p.join(dir.path, 'something-else.exe'),
      );

      expect(binary.existsSync(), isTrue);
      expect(File('${binary.path}.bak').existsSync(), isFalse);
    });

    test('overwrites a stale backup from a prior upgrade', () async {
      final binary = File(p.join(dir.path, 'docmd.exe'))..writeAsStringSync('new');
      File('${binary.path}.bak').writeAsStringSync('stale');

      await WindowsPlatformOps()
          .backupRunningBinary(binary.path, runningExecutable: binary.path);

      expect(File('${binary.path}.bak').readAsStringSync(), equals('new'));
    });

    test('removeBackup deletes the .bak file', () async {
      final binary = p.join(dir.path, 'docmd.exe');
      File('$binary.bak').writeAsStringSync('bak');

      await WindowsPlatformOps().removeBackup(binary);

      expect(File('$binary.bak').existsSync(), isFalse);
    });

    test('linkIntoUserPath is a no-op — the install dir is on PATH', () async {
      // Should not throw even with a null home, and creates nothing.
      await WindowsPlatformOps()
          .linkIntoUserPath(p.join(dir.path, 'docmd.exe'), userHome: null);
      expect(dir.listSync(), isEmpty);
    });
  });

  group('LinuxPlatformOps install steps', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('docmd_linuxops_'));
    tearDown(() => dir.deleteSync(recursive: true));

    // Linux can overwrite a running binary in place (the inode survives).
    test('does not back up the running binary', () async {
      final binary = File(p.join(dir.path, 'docmd'))..writeAsStringSync('old');

      await LinuxPlatformOps()
          .backupRunningBinary(binary.path, runningExecutable: binary.path);

      expect(binary.existsSync(), isTrue);
      expect(File('${binary.path}.bak').existsSync(), isFalse);
    });

    test('links the binary into ~/.local/bin', () async {
      final binary = File(p.join(dir.path, 'docmd'))..writeAsStringSync('bin');
      final home = Directory(p.join(dir.path, 'home'))..createSync();

      await LinuxPlatformOps()
          .linkIntoUserPath(binary.path, userHome: home.path);

      final link = Link(p.join(home.path, '.local', 'bin', 'docmd'));
      expect(link.existsSync(), isTrue);
      expect(link.targetSync(), equals(binary.path));
    }, skip: Platform.isWindows ? 'symlink creation requires Linux' : null);

    test('throws when there is no home directory to link into', () {
      expect(
        () => LinuxPlatformOps().linkIntoUserPath('/opt/docmd/bin/docmd', userHome: null),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('PlatformOps.forPlatform', () {
    test('picks the implementation for the platform string', () {
      expect(PlatformOps.forPlatform('linux'), isA<LinuxPlatformOps>());
      expect(PlatformOps.forPlatform('windows'), isA<WindowsPlatformOps>());
      expect(PlatformOps.forPlatform('win32'), isA<WindowsPlatformOps>());
    });

    test('returns null for an unsupported platform', () {
      expect(PlatformOps.forPlatform('macos'), isNull);
    });
  });
}
