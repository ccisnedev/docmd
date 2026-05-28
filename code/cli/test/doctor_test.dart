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