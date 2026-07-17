import 'dart:io';

import 'package:test/test.dart';

import 'package:docmd_cli/modules/setup/commands/setup.dart';

void main() {
  group('SetupCommand', () {
    String? none() => null;
    String? present() => '/usr/bin/tool';

    test('validate() rejects an unknown capability', () {
      final cmd = SetupCommand(SetupInput(capability: 'xlsx'), platform: 'linux');
      expect(cmd.validate(), contains('Unknown capability'));
    });

    test('defaults to a dry-run preview that does not execute anything', () async {
      var invocations = 0;
      final cmd = SetupCommand(
        SetupInput(capability: 'all'),
        platform: 'linux',
        resolvePandoc: none,
        resolveLibreOffice: none,
        processRunner: (exe, args, {workingDirectory}) async {
          invocations += 1;
          return ProcessResult(0, 0, '', '');
        },
      );

      final output = await cmd.execute();

      expect(output.executed, isFalse);
      expect(invocations, equals(0));
      expect(output.plan, isNotEmpty);
      expect(output.toText(), contains('--apply to execute'));
      expect(output.exitCode, equals(0));
    });

    test('--apply executes each planned step through the runner', () async {
      final executed = <String>[];
      final cmd = SetupCommand(
        SetupInput(capability: 'docx', apply: true),
        platform: 'linux',
        resolvePandoc: none,
        resolveLibreOffice: present,
        processRunner: (exe, args, {workingDirectory}) async {
          executed.add('$exe ${args.join(' ')}');
          return ProcessResult(0, 0, '', '');
        },
      );

      final output = await cmd.execute();

      expect(output.executed, isTrue);
      expect(output.results, hasLength(1));
      expect(output.results.single.tool, equals('pandoc'));
      expect(executed.single, contains('apt-get install -y pandoc'));
      expect(output.exitCode, equals(0));
    });

    test('an all-present machine reports nothing to do', () async {
      final cmd = SetupCommand(
        SetupInput(capability: 'all'),
        platform: 'macos',
        resolvePandoc: present,
        resolveLibreOffice: present,
      );

      final output = await cmd.execute();
      expect(output.plan, isEmpty);
      expect(output.toText(), contains('already installed'));
    });

    test('reports a non-zero exit when a planned step fails', () async {
      final cmd = SetupCommand(
        SetupInput(capability: 'all', apply: true),
        platform: 'linux',
        resolvePandoc: none,
        resolveLibreOffice: none,
        processRunner: (exe, args, {workingDirectory}) async =>
            ProcessResult(0, exe == 'sudo' ? 1 : 0, '', 'boom'),
      );

      final output = await cmd.execute();

      expect(output.allOk, isFalse);
      expect(output.exitCode, equals(1));
    });
  });
}
