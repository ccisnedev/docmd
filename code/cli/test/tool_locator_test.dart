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
          // `where` finds nothing (not on PATH), but the binary in Program Files
          // runs fine — so the version probe succeeds.
          runSync: (executable, arguments) => executable == 'where'
              ? ProcessResult(0, 1, '', '')
              : ProcessResult(0, 0, 'LibreOffice 7.6', ''),
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
          runSync: (_, _) => ProcessResult(0, 0, '/usr/bin/pandoc\n', ''),
        ),
      );

      expect(resolved, equals('/usr/bin/pandoc'));
    });

    test('returns null when no executable can be found', () {
      final resolved = resolveLibreOfficeExecutable(
        deps: ToolLocatorDeps(
          platform: 'linux',
          fileExists: (_) => false,
          runSync: (_, _) => ProcessResult(0, 1, '', ''),
        ),
      );

      expect(resolved, isNull);
    });

    // Regression: a tool is only "found" if it actually runs. Presence on PATH is
    // not enough — a pip/pipx shim outlives its package and stays on disk after
    // the module is gone, so `where` still reports it while every invocation
    // exits non-zero.
    test('skips a PATH candidate that exists but fails to run', () {
      // Mirrors a real machine: a stale C:\Python311 shim shadows a working
      // uv-installed binary later on PATH.
      const shim = r'C:\Python311\Scripts\markitdown.exe';
      const working = r'C:\Users\dev\.local\bin\markitdown.exe';

      final resolved = resolveMarkitdownExecutable(
        deps: ToolLocatorDeps(
          platform: 'windows',
          fileExists: (_) => true,
          runSync: (executable, arguments) {
            if (executable == 'where') {
              return ProcessResult(0, 0, '$shim\r\n$working\r\n', '');
            }
            if (executable == shim) {
              return ProcessResult(
                0,
                1,
                '',
                "ModuleNotFoundError: No module named 'markitdown'",
              );
            }
            return ProcessResult(0, 0, 'markitdown 0.1.5', '');
          },
        ),
      );

      expect(resolved, equals(working));
    });

    test('returns null when every candidate on PATH fails to run', () {
      final resolved = resolveMarkitdownExecutable(
        deps: ToolLocatorDeps(
          platform: 'windows',
          fileExists: (_) => true,
          runSync: (executable, arguments) {
            if (executable == 'where') {
              return ProcessResult(0, 0, 'a.exe\r\nb.exe\r\n', '');
            }
            return ProcessResult(0, 1, '', 'boom');
          },
        ),
      );

      expect(resolved, isNull);
    });

    test('verifies a Windows install-directory candidate before accepting it', () {
      // The Program Files fallback deserves the same scrutiny as PATH hits.
      final resolved = resolveExecutable(
        'thing.exe',
        deps: ToolLocatorDeps(
          platform: 'windows',
          fileExists: (_) => true,
          runSync: (executable, arguments) => executable == 'where'
              ? ProcessResult(0, 1, '', '')
              : ProcessResult(0, 1, '', 'corrupt install'),
        ),
        windowsCandidates: [r'C:\Program Files\Thing\thing.exe'],
        probeArgs: const ['--version'],
      );

      expect(resolved, isNull);
    });

    test('skips a PATH hit that where reports but disk does not have', () {
      // `where` can report stale cache entries; the old code returned the first
      // line regardless of whether the file was actually there.
      final resolved = resolvePandocExecutable(
        deps: ToolLocatorDeps(
          platform: 'linux',
          fileExists: (path) => path == '/opt/pandoc/pandoc',
          runSync: (_, _) =>
              ProcessResult(0, 0, '/ghost/pandoc\n/opt/pandoc/pandoc\n', ''),
        ),
      );

      expect(resolved, equals('/opt/pandoc/pandoc'));
    });

    // Regression guard for a real hang: `soffice --version` never returns on
    // Windows, so probing LibreOffice would wedge every `doctor` invocation.
    // Presence must remain sufficient for it.
    test('never executes LibreOffice while resolving it', () {
      final probed = <String>[];

      final resolved = resolveLibreOfficeExecutable(
        deps: ToolLocatorDeps(
          platform: 'windows',
          programFiles: r'C:\Program Files',
          fileExists: (path) =>
              path == r'C:\Program Files\LibreOffice\program\soffice.exe',
          runSync: (executable, arguments) {
            probed.add(executable);
            return ProcessResult(0, 1, '', '');
          },
        ),
      );

      expect(
        resolved,
        equals(r'C:\Program Files\LibreOffice\program\soffice.exe'),
      );
      expect(
        probed.where((e) => e.contains('soffice')),
        isEmpty,
        reason: 'soffice --version hangs on Windows; it must never be probed',
      );
    });
  });
}