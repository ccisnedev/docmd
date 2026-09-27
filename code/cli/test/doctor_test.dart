import 'package:cli_router/cli_router.dart';
import 'package:modular_cli_sdk/modular_cli_sdk.dart';
import 'package:test/test.dart';

import 'package:docmd_cli/modules/global/commands/doctor.dart';

void main() {
  group('DocmdDoctorChecksPlugin', () {
    test('reports ok for pandoc and libreoffice when both are found', () async {
      final plugin = DocmdDoctorChecksPlugin(
        resolvePandocExecutable: () => '/usr/bin/pandoc',
        resolveLibreOfficeExecutable: () =>
            r'C:\Program Files\LibreOffice\program\soffice.exe',
      );

      final checks = await _contributedChecks(plugin);
      final byName = {for (final c in checks) c.name: await c.run()};

      expect(byName['pandoc']!.status, equals(CliCheckStatus.ok));
      expect(byName['pandoc']!.message, contains('/usr/bin/pandoc'));
      expect(byName['libreoffice']!.status, equals(CliCheckStatus.ok));
      expect(byName['libreoffice']!.message, contains('soffice.exe'));
    });

    test('reports an error for a missing tool with an install hint', () async {
      final plugin = DocmdDoctorChecksPlugin(
        resolvePandocExecutable: () => null,
        resolveLibreOfficeExecutable: () => '/usr/bin/soffice',
      );

      final checks = await _contributedChecks(plugin);
      final byName = {for (final c in checks) c.name: await c.run()};

      expect(byName['pandoc']!.status, equals(CliCheckStatus.error));
      expect(byName['pandoc']!.message, contains('docmd setup docx'));
      expect(byName['libreoffice']!.status, equals(CliCheckStatus.ok));
    });

    test(
      'declares its manifest id and requires the doctor extension point',
      () {
        final plugin = DocmdDoctorChecksPlugin();
        expect(plugin.manifest.id, equals('docmd.doctor_checks'));
        expect(plugin.manifest.requires, contains('modular_cli.doctor'));
      },
    );

    test('wires into a real ModularCli doctor run end-to-end', () async {
      final cli =
          ModularCli(suggestionDistance: 2, name: 'docmd', version: '0.0.0')
            ..plugin(const DoctorPlugin())
            ..plugin(
              DocmdDoctorChecksPlugin(
                resolvePandocExecutable: () => '/usr/bin/pandoc',
                resolveLibreOfficeExecutable: () => '/usr/bin/soffice',
              ),
            );

      cli.buildPlugins();

      final entry = cli.catalog.forName('doctor');
      expect(entry, isNotNull);
    });
  });
}

Future<List<CliDoctorCheck>> _contributedChecks(
  DocmdDoctorChecksPlugin plugin,
) async {
  final checks = <CliDoctorCheck>[];
  final host = _CapturingHost(checks);
  plugin.setup(host);
  return checks;
}

/// A minimal [CliPluginHost] that only records [contribute] calls, enough to
/// exercise [DocmdDoctorChecksPlugin.setup] without a real [ModularCli].
class _CapturingHost implements CliPluginHost {
  _CapturingHost(this._checks);

  final List<CliDoctorCheck> _checks;

  @override
  void contribute<T>(String extensionPointId, T value) {
    if (value is CliDoctorCheck) {
      _checks.add(value);
    }
  }

  @override
  List<T> contributions<T>(String extensionPointId) => const [];

  @override
  void declareExtensionPoint<T>(String id) {}

  @override
  CliHostMetadata metadata() =>
      const CliHostMetadata(name: 'docmd', version: '0.0.0');

  @override
  void registerCommand<I extends Input, O extends Output>(
    String route,
    Command<I, O> Function(CliRequest req) commandFactory, {
    String? description,
    required bool globals,
    CliContract contract = CliContract.none,
  }) {}

  @override
  void registerQuery<I extends Input, O extends Output>(
    String route,
    Query<I, O> Function(CliRequest req) queryFactory, {
    String? description,
    required bool globals,
    CliContract contract = CliContract.none,
  }) {}
}
