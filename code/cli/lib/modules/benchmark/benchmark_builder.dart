import 'package:modular_cli_sdk/modular_cli_sdk.dart';

import 'commands/bench.dart';

void buildBenchmarkModule(ModuleBuilder m) {
  m.query<BenchInput, BenchOutput>(
    '<corpus>',
    (req) => BenchCommand(BenchInput.fromCliRequest(req)),
    globals: true,
    contract: BenchInput.contract,
    description:
        'Benchmark ingestion engines on a corpus (docmd vs docling vs markitdown)',
  );
}
