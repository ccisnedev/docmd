import 'package:test/test.dart';

import 'package:docmd_cli/docmd_cli.dart';
import 'package:docmd_cli/src/version.dart';

import 'support/memory_sink.dart';

/// Runs `docmd <args>` through the real dispatcher.
Future<(int, String, String)> _run(List<String> args) async {
  final stdout = MemorySink();
  final stderr = MemorySink();
  final code = await runDocmd(args, stdout: stdout.sink, stderr: stderr.sink);
  return (code, await stdout.text(), await stderr.text());
}

// The root options a user reaches for first. On modular_cli_sdk 0.8.3
// `docmd --version` was an unknown option and `docmd --help` printed an empty
// `Usage:` line instead of the commands.
void main() {
  test('--version prints what `version` prints', () async {
    final (code, out, _) = await _run(['--version']);
    final (_, viaRoute, _) = await _run(['version']);
    expect(code, 0);
    expect(out, contains(docmdVersion));
    expect(out, viaRoute);
  });

  test('--help is the catalog, every command included', () async {
    final (code, out, _) = await _run(['--help']);
    expect(code, 0);
    expect(out, contains('Usage: docmd'));
    for (final command in [
      'import',
      'render',
      'setup',
      'bench',
      'doctor',
      'upgrade',
      'uninstall',
    ]) {
      expect(out, contains(command));
    }
  });

  test('an unknown command answers with a hint, not the whole catalog',
      () async {
    final (code, _, err) = await _run(['nonsense']);
    expect(code, isNot(0));
    expect(err, contains('Run "docmd --help" to see every command.'));
    expect(err, isNot(contains('uninstall')));
  });
}
