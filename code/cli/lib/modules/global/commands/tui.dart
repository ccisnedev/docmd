library;

import 'package:cli_router/cli_router.dart';
import 'package:modular_cli_sdk/modular_cli_sdk.dart';

import '../../../src/version.dart';

class TuiInput extends Input {
  TuiInput();

  factory TuiInput.fromCliRequest(CliRequest req) => TuiInput();

  @override
  Map<String, dynamic> toJson() => {};
}

class TuiOutput extends Output {
  final String name;
  final String version;

  TuiOutput({required this.name, required this.version});

  @override
  Map<String, dynamic> toJson() => {'name': name, 'version': version};

  @override
  int get exitCode => ExitCode.ok;

  @override
  String toText() {
    return [
      'DocMD CLI v$version',
      '',
      'Markdown-first document runtime for developers and AI workflows.',
      '',
      'Commands:',
      '  version        Print CLI version',
      '  doctor         Check local prerequisites',
      '  import <input> Create a DocMD package scaffold from an external file',
      '  render <input> Render canonical content to a shareable output format',
    ].join('\n');
  }
}

class TuiCommand implements Command<TuiInput, TuiOutput> {
  @override
  final TuiInput input;

  TuiCommand(this.input);

  @override
  String? validate() => null;

  @override
  Future<TuiOutput> execute() async {
    return TuiOutput(name: 'DocMD', version: docmdVersion);
  }
}
