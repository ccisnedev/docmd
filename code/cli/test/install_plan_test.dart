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

    // markitdown is the engine `doctor` actually reports for PDF import, so a
    // machine provisioned for "pdf" without it is not provisioned for PDF.
    test('pdf capability provisions the whole PDF toolchain, markitdown included', () {
      final plan = buildSetupPlan(platform: 'linux', capability: 'pdf');
      expect(
        toolsFor(plan),
        equals(['pandoc', 'libreoffice', 'uv', 'docling', 'markitdown']),
      );
    });

    // The root help lists the tool names, so the tool names must work as
    // arguments. Naming one repairs exactly it.
    test('a single tool can be named as its own capability', () {
      expect(
        toolsFor(buildSetupPlan(platform: 'linux', capability: 'pandoc')),
        equals(['pandoc']),
      );
      expect(
        toolsFor(buildSetupPlan(platform: 'linux', capability: 'libreoffice')),
        equals(['libreoffice']),
      );
    });

    test('a uv-installed tool named alone still brings uv with it', () {
      expect(
        toolsFor(buildSetupPlan(platform: 'linux', capability: 'markitdown')),
        equals(['uv', 'markitdown']),
      );
      expect(
        toolsFor(buildSetupPlan(platform: 'linux', capability: 'docling')),
        equals(['uv', 'docling']),
      );
    });

    test('every capability name is a valid capability', () {
      for (final capability in setupCapabilities) {
        expect(
          buildSetupPlan(platform: 'linux', capability: capability),
          isNotEmpty,
          reason: '"$capability" is offered but plans nothing',
        );
      }
    });

    // Without this, a tool that is present but broken can never be reinstalled:
    // it is reported present, so it is skipped, so it stays broken.
    test('force replans tools that are already present', () {
      final plan = buildSetupPlan(
        platform: 'linux',
        capability: 'markitdown',
        hasUv: true,
        hasMarkitdown: true,
        force: true,
      );
      expect(toolsFor(plan), equals(['uv', 'markitdown']));
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
