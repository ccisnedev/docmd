import 'dart:io';

import 'package:test/test.dart';

import 'package:docmd_cli/src/tool_locator.dart';

void main() {
  group('tool locator', () {
    test('finds LibreOffice in the standard Windows install directory', () {
      final resolved = resolveLibreOfficeExecutable(
        deps: ToolLocatorDeps(
          platform: 'windows',
          programFiles: r'C:\Program Files',
          programFilesX86: r'C:\Program Files (x86)',
          fileExists: (path) =>
              path == r'C:\Program Files\LibreOffice\program\soffice.exe',
          runSync: (_, __) => ProcessResult(0, 1, '', ''),
        ),
      );

      expect(
        resolved,
        equals(r'C:\Program Files\LibreOffice\program\soffice.exe'),
      );
    });

    test('prefers the first executable found on PATH', () {
      final resolved = resolvePandocExecutable(
        deps: ToolLocatorDeps(
          platform: 'linux',
          fileExists: (path) => path == '/usr/bin/pandoc',
          runSync: (_, __) => ProcessResult(0, 0, '/usr/bin/pandoc\n', ''),
        ),
      );

      expect(resolved, equals('/usr/bin/pandoc'));
    });

    test('returns null when no executable can be found', () {
      final resolved = resolveLibreOfficeExecutable(
        deps: ToolLocatorDeps(
          platform: 'linux',
          fileExists: (_) => false,
          runSync: (_, __) => ProcessResult(0, 1, '', ''),
        ),
      );

      expect(resolved, isNull);
    });
  });
}