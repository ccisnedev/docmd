library;

import 'dart:io' as io;

import 'package:modular_cli_sdk/modular_cli_sdk.dart';

import 'modules/benchmark/benchmark_builder.dart';
import 'modules/global/global_builder.dart';
import 'modules/importing/import_builder.dart';
import 'modules/render/render_builder.dart';
import 'modules/setup/setup_builder.dart';

Future<int> runDocmd(List<String> args, {io.IOSink? stdout, io.IOSink? stderr}) async {
  final cli = ModularCli();

  cli.module('', (m) => buildGlobalModule(m));
  cli.module('import', (m) => buildImportModule(m));
  cli.module('render', (m) => buildRenderModule(m));
  cli.module('bench', (m) => buildBenchmarkModule(m));
  cli.module('setup', (m) => buildSetupModule(m));

  return cli.run(args, stdout: stdout, stderr: stderr);
}
