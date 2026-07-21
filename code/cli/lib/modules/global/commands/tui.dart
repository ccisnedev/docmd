library;

import 'package:cli_router/cli_router.dart';
import 'package:modular_cli_sdk/modular_cli_sdk.dart';

import '../../../src/version.dart';
import '../../../src/version_check.dart';

class TuiInput extends Input {
  TuiInput();

  factory TuiInput.fromCliRequest(CliRequest req) => TuiInput();

  static const List<CliParam> params = [];

  @override
  List<CliParam> get schemaFields => params;

  @override
  Map<String, dynamic> toJson() => {};
}

class TuiOutput extends Output {
  final String name;
  final String version;
  final String? latestVersion;
  final bool updateAvailable;

  TuiOutput({
    required this.name,
    required this.version,
    this.latestVersion,
    this.updateAvailable = false,
  });

  @override
  Map<String, dynamic> toJson() => {
    'name': name,
    'version': version,
    'updateAvailable': updateAvailable,
    if (latestVersion != null) 'latestVersion': latestVersion,
  };

  @override
  int get exitCode => ExitCode.ok;

  @override
  String toText() {
    final lines = [
      'DocMD CLI v$version',
      '',
      'Markdown-first document runtime for developers and AI workflows.',
      '',
      'Commands:',
      '  version        Print CLI version',
      '  doctor         Check local prerequisites',
      '  import <input> Create a DocMD package scaffold from an external file',
      '  render <input> Render canonical content to a shareable output format',
    ];
    if (updateAvailable && latestVersion != null) {
      lines.add('');
      lines.add('Update available: v$version → v$latestVersion — run `docmd upgrade`');
    }
    return lines.join('\n');
  }
}

class TuiCommand implements Command<TuiInput, TuiOutput> {
  @override
  final TuiInput input;

  final Future<VersionCheckResult> Function({required String currentVersion})?
  _versionChecker;

  TuiCommand(
    this.input, {
    Future<VersionCheckResult> Function({required String currentVersion})?
    versionChecker,
  }) : _versionChecker = versionChecker;

  @override
  String? validate() => null;

  @override
  Future<TuiOutput> execute() async {
    final checker = _versionChecker ?? checkLatestVersion;

    String? latestVersion;
    var updateAvailable = false;
    // Non-blocking: the summary prints on every bare `docmd`, so a slow or
    // failing network check must never delay or break it.
    try {
      final result = await checker(currentVersion: docmdVersion);
      if (result.updateAvailable && result.latestVersion != null) {
        latestVersion = result.latestVersion;
        updateAvailable = true;
      }
    } catch (_) {
      // Offline or rate-limited: stay silent rather than surface an error.
    }

    return TuiOutput(
      name: 'DocMD',
      version: docmdVersion,
      latestVersion: latestVersion,
      updateAvailable: updateAvailable,
    );
  }
}
