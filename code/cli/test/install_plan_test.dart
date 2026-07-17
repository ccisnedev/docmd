import 'package:test/test.dart';

import 'package:docmd_cli/src/setup/install_plan.dart';

void main() {
  group('buildSetupPlan', () {
    List<String> toolsFor(List<InstallStep> steps) =>
        steps.map((s) => s.tool).toList();

    // Import is pure Dart (pdf/pptx) or Pandoc (docx); the only tools to
    // provision are Pandoc and LibreOffice. No Python engines.
    test('all-capability plan installs pandoc and libreoffice', () {
      final plan = buildSetupPlan(platform: 'linux', capability: 'all');
      expect(toolsFor(plan), equals(['pandoc', 'libreoffice']));
      final pandoc = plan.firstWhere((s) => s.tool == 'pandoc');
      expect(pandoc.executable, equals('sudo'));
      expect(pandoc.display, contains('apt-get install -y pandoc'));
    });

    test('Windows plan uses winget for pandoc', () {
      final plan = buildSetupPlan(platform: 'windows', capability: 'all');
      final pandoc = plan.firstWhere((s) => s.tool == 'pandoc');
      expect(pandoc.executable, equals('winget'));
      expect(pandoc.args, contains('JohnMacFarlane.Pandoc'));
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

    // PDF import needs no tool (pure Dart); the pdf capability provisions the
    // render toolchain — pandoc and LibreOffice.
    test('pdf capability provisions the render toolchain', () {
      final plan = buildSetupPlan(platform: 'linux', capability: 'pdf');
      expect(toolsFor(plan), equals(['pandoc', 'libreoffice']));
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
        capability: 'all',
        hasPandoc: true,
        hasLibreOffice: true,
        force: true,
      );
      expect(toolsFor(plan), equals(['pandoc', 'libreoffice']));
    });

    test('already-installed tools are skipped', () {
      final plan = buildSetupPlan(
        platform: 'linux',
        capability: 'all',
        hasPandoc: true,
      );
      expect(toolsFor(plan), equals(['libreoffice']));
    });

    test('an all-present machine yields an empty plan', () {
      final plan = buildSetupPlan(
        platform: 'macos',
        capability: 'all',
        hasPandoc: true,
        hasLibreOffice: true,
      );
      expect(plan, isEmpty);
    });
  });
}
