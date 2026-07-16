import 'package:modular_cli_sdk/modular_cli_sdk.dart';

import 'commands/bench.dart';

void buildBenchmarkModule(ModuleBuilder m) {
  m.command<BenchInput, BenchOutput>(
    '<corpus>',
    (req) => BenchCommand(BenchInput.fromCliRequest(req)),
    description: 'Benchmark ingestion engines on a corpus (docmd vs docling vs markitdown)',
    params: BenchInput.params,
  );
}
