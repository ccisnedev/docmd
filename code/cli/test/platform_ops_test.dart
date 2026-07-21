import 'dart:io';

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
