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
        // Inject PDF engines explicitly so the report is deterministic and does
        // not depend on what happens to be installed on the test machine.
        resolveDoclingExecutable: () => null,
        resolveMarkitdownExecutable: () => null,
        versionChecker: ({required currentVersion}) async =>
            const VersionCheckResult(updateAvailable: false),
      ).execute();

      final byKey = {
        for (final c in output.capabilities) '${c.direction}:${c.format}': c,
      };
      expect(byKey['import:md']!.available, isTrue);
      expect(byKey['import:docx']!.engine, equals('pandoc'));
      expect(byKey['import:docx']!.available, isTrue);
      // With no PDF engine installed, pdf import falls back to the placeholder.
      expect(byKey['import:pdf']!.available, isFalse);
      expect(byKey['import:pdf']!.hint, isNotNull);
      expect(byKey['render:docx']!.available, isTrue);
      expect(byKey['render:pdf']!.available, isTrue);
      expect(output.toText(), contains('Capabilities'));
    });

    test('reports docling as the PDF import engine when it is installed', () async {
      final output = await DoctorCommand(
        DoctorInput(),
        resolvePandocExecutable: () => '/usr/bin/pandoc',
        resolveLibreOfficeExecutable: () => '/usr/bin/soffice',
        resolveDoclingExecutable: () => '/usr/bin/docling',
        resolveMarkitdownExecutable: () => null,
        versionChecker: ({required currentVersion}) async =>
            const VersionCheckResult(updateAvailable: false),
      ).execute();

      final pdf = output.capabilities
          .firstWhere((c) => c.direction == 'import' && c.format == 'pdf');
      expect(pdf.engine, equals('docling'));
      expect(pdf.available, isTrue);
    });

    test('reports markitdown as the PDF engine when only markitdown is installed', () async {
      final output = await DoctorCommand(
        DoctorInput(),
        resolvePandocExecutable: () => '/usr/bin/pandoc',
        resolveLibreOfficeExecutable: () => '/usr/bin/soffice',
        resolveDoclingExecutable: () => null,
        resolveMarkitdownExecutable: () => '/usr/bin/markitdown',
        versionChecker: ({required currentVersion}) async =>
            const VersionCheckResult(updateAvailable: false),
      ).execute();

      final pdf = output.capabilities
          .firstWhere((c) => c.direction == 'import' && c.format == 'pdf');
      expect(pdf.engine, equals('markitdown'));
      expect(pdf.available, isTrue);
    });

    test('PDF import is unavailable with a setup hint when no engine is installed', () async {
      final output = await DoctorCommand(
        DoctorInput(),
        resolvePandocExecutable: () => '/usr/bin/pandoc',
        resolveLibreOfficeExecutable: () => '/usr/bin/soffice',
        resolveDoclingExecutable: () => null,
        resolveMarkitdownExecutable: () => null,
        versionChecker: ({required currentVersion}) async =>
            const VersionCheckResult(updateAvailable: false),
      ).execute();

      final pdf = output.capabilities
          .firstWhere((c) => c.direction == 'import' && c.format == 'pdf');
      expect(pdf.available, isFalse);
      expect(pdf.engine, equals('placeholder'));
      expect(pdf.hint, contains('docmd setup pdf'));
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