import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

    // origin/main's doctor reported one capability per import/render
    // format, projected from the installed tools. The DoctorPlugin
    // migration keeps that report as one doctor check per capability.
    test('reports every import and render capability when both tools are found', () async {
      final plugin = DocmdDoctorChecksPlugin(
        resolvePandocExecutable: () => '/usr/bin/pandoc',
        resolveLibreOfficeExecutable: () => '/usr/bin/soffice',
      );

      final checks = await _contributedChecks(plugin);
      final byName = {for (final c in checks) c.name: await c.run()};

      expect(
        byName.keys,
        containsAll([
          'import md',
          'import docx',
          'import pdf',
          'import pptx',
          'import xlsx',
          'render docx',
          'render pdf',
        ]),
      );
      expect(byName['import docx']!.status, equals(CliCheckStatus.ok));
      expect(byName['import docx']!.message, contains('available (pandoc)'));
      expect(byName['import md']!.message, contains('available (passthrough)'));
      expect(byName['render pdf']!.status, equals(CliCheckStatus.ok));
      expect(
        byName['render pdf']!.message,
        contains('available (pandoc+libreoffice)'),
      );
    });

    test('warns on a capability a missing tool disables, with its hint', () async {
      final plugin = DocmdDoctorChecksPlugin(
        resolvePandocExecutable: () => null,
        resolveLibreOfficeExecutable: () => null,
      );

      final checks = await _contributedChecks(plugin);
      final byName = {for (final c in checks) c.name: await c.run()};

      expect(byName['import docx']!.status, equals(CliCheckStatus.warning));
      expect(byName['import docx']!.message, contains('docmd setup docx'));
      expect(byName['render docx']!.status, equals(CliCheckStatus.warning));
      expect(byName['render pdf']!.status, equals(CliCheckStatus.warning));
      expect(byName['render pdf']!.message, contains('docmd setup docx'));
      expect(byName['render pdf']!.message, contains('docmd setup pdf'));
      expect(byName['import pdf']!.status, equals(CliCheckStatus.ok));
    });

    // xlsx has no real engine yet: that is a fact about docmd, not about
    // this machine, so it is reported without turning doctor into a
    // warning on every installation.
    test('reports the unwired xlsx import as unavailable without a warning', () async {
      final plugin = DocmdDoctorChecksPlugin(
        resolvePandocExecutable: () => '/usr/bin/pandoc',
        resolveLibreOfficeExecutable: () => '/usr/bin/soffice',
      );

      final checks = await _contributedChecks(plugin);
      final byName = {for (final c in checks) c.name: await c.run()};

      expect(byName['import xlsx']!.status, equals(CliCheckStatus.ok));
      expect(byName['import xlsx']!.message, contains('unavailable (placeholder)'));
      expect(byName['import xlsx']!.message, contains('planned'));
    });

    test(
      'declares its manifest id and requires the doctor extension point',
      () {
        final plugin = DocmdDoctorChecksPlugin();
        expect(plugin.manifest.id, equals('docmd.doctor_checks'));
        expect(plugin.manifest.requires, contains('modular_cli.doctor'));
      },
    );

    test(
      'runs a real ModularCli doctor invocation end-to-end and reports success',
      () async {
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

        final result = await _run(cli, ['doctor', '--json']);

        expect(result.exitCode, equals(0));
        final json = jsonDecode(result.stdout) as Map<String, dynamic>;
        final checks = (json['checks'] as List).cast<Map<String, dynamic>>();
        expect(
          checks,
          containsAll([
            containsPair('name', 'pandoc'),
            containsPair('name', 'libreoffice'),
          ]),
        );
        expect(checks.every((c) => c['status'] == 'ok'), isTrue);
      },
    );

    test(
      'runs a real ModularCli doctor invocation end-to-end and reports a failing check',
      () async {
        final cli =
            ModularCli(suggestionDistance: 2, name: 'docmd', version: '0.0.0')
              ..plugin(const DoctorPlugin())
              ..plugin(
                DocmdDoctorChecksPlugin(
                  resolvePandocExecutable: () => null,
                  resolveLibreOfficeExecutable: () => '/usr/bin/soffice',
                ),
              );

        cli.buildPlugins();

        final result = await _run(cli, ['doctor', '--json']);

        expect(result.exitCode, isNot(equals(0)));
        final json = jsonDecode(result.stderr) as Map<String, dynamic>;
        final error = json['error'] as Map<String, dynamic>;
        expect(error['id'], equals('doctor-check-failed'));
        final checks = (error['checks'] as List).cast<Map<String, dynamic>>();
        final pandoc = checks.singleWhere((c) => c['name'] == 'pandoc');
        expect(pandoc['status'], equals('error'));
        final libreoffice = checks.singleWhere(
          (c) => c['name'] == 'libreoffice',
        );
        expect(libreoffice['status'], equals('ok'));
      },
    );
  });
}

/// Runs [args] on [cli] and captures both streams, the same way
/// `runDocmd`/the extension's `DocmdCli.run` drive a `ModularCli`.
Future<({int exitCode, String stdout, String stderr})> _run(
  ModularCli cli,
  List<String> args,
) async {
  final stdoutController = StreamController<List<int>>();
  final stderrController = StreamController<List<int>>();
  final stdoutBytes = <int>[];
  final stderrBytes = <int>[];

  stdoutController.stream.listen(stdoutBytes.addAll);
  stderrController.stream.listen(stderrBytes.addAll);

  final stdoutSink = IOSink(stdoutController.sink);
  final stderrSink = IOSink(stderrController.sink);

  try {
    final exitCode = await cli.run(
      args,
      stdout: stdoutSink,
      stderr: stderrSink,
    );

    await stdoutSink.flush();
    await stderrSink.flush();
    await stdoutSink.close();
    await stderrSink.close();

    return (
      exitCode: exitCode,
      stdout: utf8.decode(stdoutBytes).trim(),
      stderr: utf8.decode(stderrBytes).trim(),
    );
  } finally {
    await stdoutController.close();
    await stderrController.close();
  }
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
