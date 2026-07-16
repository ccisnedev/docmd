import 'package:test/test.dart';

import 'package:docmd_cli/src/setup/install_plan.dart';

void main() {
  group('buildSetupPlan', () {
    List<String> toolsFor(List<InstallStep> steps) =>
        steps.map((s) => s.tool).toList();

    test('all-capability plan on Linux installs every engine via apt/uv', () {
      final plan = buildSetupPlan(platform: 'linux', capability: 'all');
      expect(
        toolsFor(plan),
        equals(['pandoc', 'libreoffice', 'uv', 'docling', 'markitdown']),
      );
      final pandoc = plan.firstWhere((s) => s.tool == 'pandoc');
      expect(pandoc.executable, equals('sudo'));
      expect(pandoc.display, contains('apt-get install -y pandoc'));
    });

    test('uv precedes the tools it bootstraps', () {
      final plan = buildSetupPlan(platform: 'linux', capability: 'all');
      final uvIndex = toolsFor(plan).indexOf('uv');
      final doclingIndex = toolsFor(plan).indexOf('docling');
      expect(uvIndex, lessThan(doclingIndex));
    });

    test('Windows plan uses winget for pandoc and powershell for uv', () {
      final plan = buildSetupPlan(platform: 'windows', capability: 'all');
      final pandoc = plan.firstWhere((s) => s.tool == 'pandoc');
      expect(pandoc.executable, equals('winget'));
      expect(pandoc.args, contains('JohnMacFarlane.Pandoc'));

      final uv = plan.firstWhere((s) => s.tool == 'uv');
      expect(uv.executable, equals('powershell'));
      expect(uv.display, contains('astral.sh/uv/install.ps1'));
    });

    test('macOS plan uses brew, with a cask for LibreOffice', () {
      final plan = buildSetupPlan(platform: 'macos', capability: 'all');
      final libre = plan.firstWhere((s) => s.tool == 'libreoffice');
      expect(libre.executable, equals('brew'));
      expect(libre.args, containsAllInOrder(['install', '--cask', 'libreoffice']));
    });

    test('docx capability only provisions pandoc', () {
      final plan = buildSetupPlan(platform: 'linux', capability: 'docx');
      expect(toolsFor(plan), equals(['pandoc']));
    });

    test('pdf capability provisions the docling import + render toolchain', () {
      final plan = buildSetupPlan(platform: 'linux', capability: 'pdf');
      expect(
        toolsFor(plan),
        equals(['pandoc', 'libreoffice', 'uv', 'docling']),
      );
    });

    test('already-installed tools are skipped', () {
      final plan = buildSetupPlan(
        platform: 'linux',
        capability: 'all',
        hasPandoc: true,
        hasUv: true,
      );
      expect(toolsFor(plan), equals(['libreoffice', 'docling', 'markitdown']));
    });

    test('an all-present machine yields an empty plan', () {
      final plan = buildSetupPlan(
        platform: 'macos',
        capability: 'all',
        hasPandoc: true,
        hasLibreOffice: true,
        hasUv: true,
        hasDocling: true,
        hasMarkitdown: true,
      );
      expect(plan, isEmpty);
    });

    test('markitdown installs with the [all] extra via uv', () {
      final plan = buildSetupPlan(platform: 'linux', capability: 'all');
      final markitdown = plan.firstWhere((s) => s.tool == 'markitdown');
      expect(markitdown.executable, equals('uv'));
      expect(markitdown.args, containsAllInOrder(['tool', 'install', 'markitdown[all]']));
    });
  });
}
