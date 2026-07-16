library;

import 'dart:io';

import 'package:cli_router/cli_router.dart';
import 'package:modular_cli_sdk/modular_cli_sdk.dart';

import '../../../src/process_runner.dart';
import '../../../src/setup/install_plan.dart';
import '../../../src/tool_locator.dart';

class SetupInput extends Input {
  final String capability;
  final bool apply;

  SetupInput({this.capability = 'all', this.apply = false});

  factory SetupInput.fromCliRequest(CliRequest req) {
    final capability = (req.params['capability'] ?? 'all').trim();
    return SetupInput(
      capability: capability.isEmpty ? 'all' : capability,
      apply: req.flagBool('apply'),
    );
  }

  // Terraform-style, matching `iq issue publish`: `--plan` is the safe default
  // and carries no value the command reads; `--apply` executes.
  static final List<CliParam> params = [
    CliParam.positional(
      'capability',
      description: 'What to provision: all, pdf, or docx (default: all)',
    ),
    CliParam.boolean(
      'plan',
      description: 'Preview the install plan without changing anything (default)',
    ),
    CliParam.boolean(
      'apply',
      description: 'Execute the install plan',
    ),
  ];

  @override
  List<CliParam> get schemaFields => params;

  @override
  Map<String, dynamic> toJson() => {'capability': capability, 'apply': apply};
}

class StepResult {
  final String tool;
  final String command;
  final int exitCode;

  const StepResult({
    required this.tool,
    required this.command,
    required this.exitCode,
  });

  bool get ok => exitCode == 0;

  Map<String, dynamic> toJson() => {
    'tool': tool,
    'command': command,
    'exitCode': exitCode,
  };
}

class SetupOutput extends Output {
  final String capability;
  final List<InstallStep> plan;
  final bool executed;
  final List<StepResult> results;

  SetupOutput({
    required this.capability,
    required this.plan,
    required this.executed,
    required this.results,
  });

  bool get allOk => results.every((r) => r.ok);

  @override
  Map<String, dynamic> toJson() => {
    'capability': capability,
    'executed': executed,
    'plan': plan.map((s) => s.toJson()).toList(),
    if (executed) 'results': results.map((r) => r.toJson()).toList(),
  };

  @override
  int get exitCode => executed && !allOk ? 1 : ExitCode.ok;

  @override
  String toText() {
    if (plan.isEmpty) {
      return 'DocMD setup: everything required for "$capability" is already installed.';
    }

    final lines = <String>['DocMD setup plan ($capability):', ''];
    for (final step in plan) {
      lines.add('  ${step.tool} — ${step.description}');
      lines.add('    ${step.display}');
    }

    if (!executed) {
      lines.add('');
      lines.add('This is a plan. Re-run with --apply to execute these steps.');
      return lines.join('\n');
    }

    lines.add('');
    lines.add('Results:');
    for (final result in results) {
      final status = result.ok ? 'OK' : 'FAILED (exit ${result.exitCode})';
      lines.add('  ${result.tool}: $status');
    }
    if (!allOk) {
      lines.add('');
      lines.add('Some steps failed. Run the commands above manually to finish.');
    }
    return lines.join('\n');
  }
}

class SetupCommand implements Command<SetupInput, SetupOutput> {
  @override
  final SetupInput input;

  final String _platform;
  final ProcessRunner _runProcess;
  final String? Function() _resolvePandoc;
  final String? Function() _resolveLibreOffice;
  final String? Function() _resolveUv;
  final String? Function() _resolveDocling;
  final String? Function() _resolveMarkitdown;

  SetupCommand(
    this.input, {
    String? platform,
    ProcessRunner? processRunner,
    String? Function()? resolvePandoc,
    String? Function()? resolveLibreOffice,
    String? Function()? resolveUv,
    String? Function()? resolveDocling,
    String? Function()? resolveMarkitdown,
  }) : _platform = platform ?? Platform.operatingSystem,
       _runProcess = processRunner ?? runProcess,
       _resolvePandoc = resolvePandoc ?? (() => resolvePandocExecutable()),
       _resolveLibreOffice =
           resolveLibreOffice ?? (() => resolveLibreOfficeExecutable()),
       _resolveUv = resolveUv ?? (() => resolveUvExecutable()),
       _resolveDocling = resolveDocling ?? (() => resolveDoclingExecutable()),
       _resolveMarkitdown =
           resolveMarkitdown ?? (() => resolveMarkitdownExecutable());

  @override
  String? validate() {
    if (!setupCapabilities.contains(input.capability)) {
      return 'Unknown capability "${input.capability}". '
          'Choose one of: ${setupCapabilities.join(', ')}.';
    }
    return null;
  }

  @override
  Future<SetupOutput> execute() async {
    final plan = buildSetupPlan(
      platform: _platform,
      capability: input.capability,
      hasPandoc: _resolvePandoc() != null,
      hasLibreOffice: _resolveLibreOffice() != null,
      hasUv: _resolveUv() != null,
      hasDocling: _resolveDocling() != null,
      hasMarkitdown: _resolveMarkitdown() != null,
    );

    final results = <StepResult>[];
    if (input.apply) {
      for (final step in plan) {
        final result = await _runProcess(step.executable, step.args);
        results.add(StepResult(
          tool: step.tool,
          command: step.display,
          exitCode: result.exitCode,
        ));
        // Stop after a failed uv install: the uv-tool steps that follow would
        // fail anyway without uv on PATH.
        if (result.exitCode != 0 && step.tool == 'uv') {
          break;
        }
      }
    }

    return SetupOutput(
      capability: input.capability,
      plan: plan,
      executed: input.apply,
      results: results,
    );
  }
}
