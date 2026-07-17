import 'package:test/test.dart';

import 'package:docmd_cli/modules/global/commands/doctor.dart';
import 'package:docmd_cli/src/version_check.dart';

void main() {
  group('Doctor Command', () {
    test('reports located tool paths and an available update', () async {
      final output = await DoctorCommand(
        DoctorInput(),
        resolvePandocExecutable: () => '/usr/bin/pandoc',
        resolveLibreOfficeExecutable: () => r'C:\Program Files\LibreOffice\program\soffice.exe',
        versionChecker: ({required currentVersion}) async => const VersionCheckResult(
          latestVersion: '0.0.5',
          updateAvailable: true,
        ),
      ).execute();

      expect(output.exitCode, equals(0));
      expect(output.checks, containsPair('pandoc', true));
      expect(output.checks, containsPair('libreoffice', true));
      expect(output.paths['libreoffice'], contains('soffice.exe'));
      expect(output.latestVersion, equals('0.0.5'));
      expect(output.updateAvailable, isTrue);
      expect(output.toText(), contains('Run `docmd upgrade`'));
    });

    test('reports per-capability import and render availability', () async {
      final output = await DoctorCommand(
        DoctorInput(),
        resolvePandocExecutable: () => '/usr/bin/pandoc',
        resolveLibreOfficeExecutable: () => '/usr/bin/soffice',
        versionChecker: ({required currentVersion}) async =>
            const VersionCheckResult(updateAvailable: false),
      ).execute();

      final byKey = {
        for (final c in output.capabilities) '${c.direction}:${c.format}': c,
      };
      expect(byKey['import:md']!.available, isTrue);
      expect(byKey['import:docx']!.engine, equals('pandoc'));
      expect(byKey['import:docx']!.available, isTrue);
      expect(byKey['render:docx']!.available, isTrue);
      expect(byKey['render:pdf']!.available, isTrue);
      expect(output.toText(), contains('Capabilities'));
    });

    test('pdf and pptx import are always available — no engine to install', () async {
      // The pure-Dart engines have no external dependency, so their availability
      // does not vary with what is installed.
      final output = await DoctorCommand(
        DoctorInput(),
        resolvePandocExecutable: () => null,
        resolveLibreOfficeExecutable: () => null,
        versionChecker: ({required currentVersion}) async =>
            const VersionCheckResult(updateAvailable: false),
      ).execute();

      final byKey = {
        for (final c in output.capabilities) '${c.direction}:${c.format}': c,
      };
      expect(byKey['import:pdf']!.engine, equals('docmd'));
      expect(byKey['import:pdf']!.available, isTrue);
      expect(byKey['import:pptx']!.engine, equals('docmd'));
      expect(byKey['import:pptx']!.available, isTrue);
    });

    test('import docx and pdf render become unavailable without pandoc', () async {
      final output = await DoctorCommand(
        DoctorInput(),
        resolvePandocExecutable: () => null,
        resolveLibreOfficeExecutable: () => '/usr/bin/soffice',
        versionChecker: ({required currentVersion}) async =>
            const VersionCheckResult(updateAvailable: false),
      ).execute();

      final byKey = {
        for (final c in output.capabilities) '${c.direction}:${c.format}': c,
      };
      expect(byKey['import:docx']!.available, isFalse);
      expect(byKey['import:docx']!.hint, isNotNull);
      expect(byKey['render:pdf']!.available, isFalse);
    });

    test('fails when LibreOffice is missing', () async {
      final output = await DoctorCommand(
        DoctorInput(),
        resolvePandocExecutable: () => '/usr/bin/pandoc',
        resolveLibreOfficeExecutable: () => null,
        versionChecker: ({required currentVersion}) async => const VersionCheckResult(
          updateAvailable: false,
        ),
      ).execute();

      expect(output.exitCode, equals(1));
      expect(output.checks, containsPair('libreoffice', false));
      expect(output.toText(), contains('libreoffice: MISSING'));
    });
  });
}