import 'package:test/test.dart';

import 'package:docmd_cli/src/setup/install_plan.dart';

void main() {
  group('buildSetupPlan', () {
    List<String> toolsFor(List<InstallStep> steps) =>
        steps.map((s) => s.tool).toList();

    // Import is pure Dart (pdf/pptx) or Pandoc (docx); render needs Pandoc and,
    // for PDF, Typst (ADR 0003). LibreOffice is only the PDF fallback, so it is
    // installed on request, not by default. No Python engines.
    test('all-capability plan installs pandoc and typst', () {
      final plan = buildSetupPlan(platform: 'linux', capability: 'all');
      expect(toolsFor(plan), equals(['pandoc', 'typst']));
      final pandoc = plan.firstWhere((s) => s.tool == 'pandoc');
      expect(pandoc.executable, equals('sudo'));
      expect(pandoc.display, contains('apt-get install -y pandoc'));
    });

    test('Windows plan uses winget for pandoc and typst', () {
      final plan = buildSetupPlan(platform: 'windows', capability: 'all');
      final pandoc = plan.firstWhere((s) => s.tool == 'pandoc');
      expect(pandoc.executable, equals('winget'));
      expect(pandoc.args, contains('JohnMacFarlane.Pandoc'));
      final typst = plan.firstWhere((s) => s.tool == 'typst');
      expect(typst.executable, equals('winget'));
      expect(typst.args, contains('Typst.Typst'));
    });

    test('macOS plan uses brew for typst', () {
      final plan = buildSetupPlan(platform: 'macos', capability: 'all');
      final typst = plan.firstWhere((s) => s.tool == 'typst');
      expect(typst.executable, equals('brew'));
      expect(typst.args, equals(['install', 'typst']));
    });

    // Typst is not packaged by apt on the common distributions; its README
    // points Linux users at the snap.
    test('Linux plan installs typst from its snap', () {
      final plan = buildSetupPlan(platform: 'linux', capability: 'typst');
      final typst = plan.single;
      expect(typst.executable, equals('sudo'));
      expect(typst.args, equals(['snap', 'install', 'typst']));
      expect(typst.display, equals('sudo snap install typst'));
    });

    test('macOS installs LibreOffice from a cask when asked for it', () {
      final plan = buildSetupPlan(platform: 'macos', capability: 'libreoffice');
      final libre = plan.single;
      expect(libre.executable, equals('brew'));
      expect(libre.args, containsAllInOrder(['install', '--cask', 'libreoffice']));
    });

    test('docx capability only provisions pandoc', () {
      final plan = buildSetupPlan(platform: 'linux', capability: 'docx');
      expect(toolsFor(plan), equals(['pandoc']));
    });

    // PDF import needs no tool (pure Dart); the pdf capability provisions the
    // render toolchain — pandoc and typst.
    test('pdf capability provisions the render toolchain', () {
      final plan = buildSetupPlan(platform: 'linux', capability: 'pdf');
      expect(toolsFor(plan), equals(['pandoc', 'typst']));
    });

    // The root help lists the tool names, so the tool names must work as
    // arguments. Naming one repairs exactly it.
    test('a single tool can be named as its own capability', () {
      for (final tool in ['pandoc', 'typst', 'libreoffice']) {
        expect(
          toolsFor(buildSetupPlan(platform: 'linux', capability: tool)),
          equals([tool]),
        );
      }
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
        hasTypst: true,
        force: true,
      );
      expect(toolsFor(plan), equals(['pandoc', 'typst']));
    });

    test('already-installed tools are skipped', () {
      final plan = buildSetupPlan(
        platform: 'linux',
        capability: 'all',
        hasPandoc: true,
      );
      expect(toolsFor(plan), equals(['typst']));
    });

    test('an all-present machine yields an empty plan', () {
      final plan = buildSetupPlan(
        platform: 'macos',
        capability: 'all',
        hasPandoc: true,
        hasTypst: true,
      );
      expect(plan, isEmpty);
    });
  });
}
