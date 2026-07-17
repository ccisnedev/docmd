library;

import 'dart:io';

import 'package:path/path.dart' as p;

typedef ToolRunSync = ProcessResult Function(String executable, List<String> arguments);

class ToolLocatorDeps {
  final String platform;
  final String? programFiles;
  final String? programFilesX86;
  final bool Function(String path) fileExists;
  final ToolRunSync runSync;

  ToolLocatorDeps({
    String? platform,
    this.programFiles,
    this.programFilesX86,
    bool Function(String path)? fileExists,
    ToolRunSync? runSync,
  }) : platform = platform ?? Platform.operatingSystem,
       fileExists = fileExists ?? ((path) => File(path).existsSync()),
       runSync = runSync ?? Process.runSync;
}

String? resolvePandocExecutable({ToolLocatorDeps? deps}) {
  final resolvedDeps = deps ?? ToolLocatorDeps();
  final pathContext = _pathContext(resolvedDeps.platform);

  return resolveExecutable(
    _isWindowsPlatform(resolvedDeps.platform) ? 'pandoc.exe' : 'pandoc',
    deps: resolvedDeps,
    windowsCandidates: [
      if ((resolvedDeps.programFiles ?? Platform.environment['ProgramFiles']) != null)
        pathContext.join(
          resolvedDeps.programFiles ?? Platform.environment['ProgramFiles']!,
          'Pandoc',
          'pandoc.exe',
        ),
      if ((resolvedDeps.programFilesX86 ?? Platform.environment['ProgramFiles(x86)']) != null)
        pathContext.join(
          resolvedDeps.programFilesX86 ?? Platform.environment['ProgramFiles(x86)']!,
          'Pandoc',
          'pandoc.exe',
        ),
    ],
  );
}

/// Deliberately unprobed: `soffice --version` never returns on Windows (it waits
/// on the office process), which would hang every `doctor` run. LibreOffice is a
/// self-contained native install, so presence is a reliable signal here.
String? resolveLibreOfficeExecutable({ToolLocatorDeps? deps}) {
  final resolvedDeps = deps ?? ToolLocatorDeps();
  final pathContext = _pathContext(resolvedDeps.platform);

  return resolveExecutable(
    _isWindowsPlatform(resolvedDeps.platform) ? 'soffice.exe' : 'soffice',
    deps: resolvedDeps,
    windowsCandidates: [
      if ((resolvedDeps.programFiles ?? Platform.environment['ProgramFiles']) != null)
        pathContext.join(
          resolvedDeps.programFiles ?? Platform.environment['ProgramFiles']!,
          'LibreOffice',
          'program',
          'soffice.exe',
        ),
      if ((resolvedDeps.programFilesX86 ?? Platform.environment['ProgramFiles(x86)']) != null)
        pathContext.join(
          resolvedDeps.programFilesX86 ?? Platform.environment['ProgramFiles(x86)']!,
          'LibreOffice',
          'program',
          'soffice.exe',
        ),
    ],
  );
}

/// Args used to prove a Python-installed engine actually runs. Both docling and
/// markitdown ship as console-scripts: uninstalling the package can leave the
/// shim behind, and a stale shim on `PATH` shadows a working install.
const List<String> _pythonToolProbe = ['--version'];

/// Resolves the `docling` PDF ingestion engine. Installed via `uv tool install
/// docling`, so it is expected on `PATH` rather than in a fixed install dir.
String? resolveDoclingExecutable({ToolLocatorDeps? deps}) {
  final resolvedDeps = deps ?? ToolLocatorDeps();
  return resolveExecutable(
    _isWindowsPlatform(resolvedDeps.platform) ? 'docling.exe' : 'docling',
    deps: resolvedDeps,
    probeArgs: _pythonToolProbe,
  );
}

/// Resolves the `markitdown` PDF ingestion engine (lightweight fallback).
/// Installed via `uv tool install 'markitdown[all]'`, so it is expected on
/// `PATH`.
String? resolveMarkitdownExecutable({ToolLocatorDeps? deps}) {
  final resolvedDeps = deps ?? ToolLocatorDeps();
  return resolveExecutable(
    _isWindowsPlatform(resolvedDeps.platform) ? 'markitdown.exe' : 'markitdown',
    deps: resolvedDeps,
    probeArgs: _pythonToolProbe,
  );
}

/// Resolves the `uv` tool runner used to bootstrap docling/markitdown.
String? resolveUvExecutable({ToolLocatorDeps? deps}) {
  final resolvedDeps = deps ?? ToolLocatorDeps();
  return resolveExecutable(
    _isWindowsPlatform(resolvedDeps.platform) ? 'uv.exe' : 'uv',
    deps: resolvedDeps,
  );
}

/// Resolves [executable] to a path that exists on disk and, when [probeArgs] is
/// supplied, actually runs.
///
/// Presence alone is not proof for Python console-scripts: the shim outlives its
/// package, so `where` keeps reporting an executable whose every invocation exits
/// non-zero. Passing [probeArgs] runs each candidate and takes the first that
/// exits 0, so a working install is preferred over a broken one shadowing it.
///
/// [probeArgs] is opt-in rather than the default because probing is not free and
/// not universally safe — notably `soffice --version` never returns on Windows.
/// Only pass it for tools whose presence genuinely fails to imply function.
String? resolveExecutable(
  String executable, {
  required ToolLocatorDeps deps,
  List<String> windowsCandidates = const [],
  List<String>? probeArgs,
}) {
  for (final candidate in _candidatePaths(
    executable,
    deps: deps,
    windowsCandidates: windowsCandidates,
  )) {
    if (!deps.fileExists(candidate)) {
      continue;
    }
    if (_isRunnable(candidate, probeArgs, deps)) {
      return candidate;
    }
  }

  return null;
}

/// Candidate paths in preference order: an absolute path as given, then every
/// `where`/`which` hit, then the known Windows install directories.
Iterable<String> _candidatePaths(
  String executable, {
  required ToolLocatorDeps deps,
  required List<String> windowsCandidates,
}) sync* {
  final pathContext = _pathContext(deps.platform);

  if (pathContext.isAbsolute(executable)) {
    yield executable;
  } else {
    final lookup = _isWindowsPlatform(deps.platform) ? 'where' : 'which';
    final lookupResult = deps.runSync(lookup, [executable]);
    if (lookupResult.exitCode == 0) {
      for (final line in '${lookupResult.stdout ?? ''}'.split(RegExp(r'\r?\n'))) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          yield trimmed;
        }
      }
    }
  }

  if (_isWindowsPlatform(deps.platform)) {
    yield* windowsCandidates;
  }
}

bool _isRunnable(String executable, List<String>? probeArgs, ToolLocatorDeps deps) {
  if (probeArgs == null) {
    return true;
  }
  try {
    return deps.runSync(executable, probeArgs).exitCode == 0;
  } on ProcessException {
    // The OS refused to start it at all — same outcome as a failed probe.
    return false;
  }
}

p.Context _pathContext(String platform) {
  return p.Context(
    style: _isWindowsPlatform(platform) ? p.Style.windows : p.Style.posix,
  );
}

bool _isWindowsPlatform(String platform) {
  return platform == 'windows' || platform == 'win32';
}