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

String? resolveExecutable(
  String executable, {
  required ToolLocatorDeps deps,
  List<String> windowsCandidates = const [],
}) {
  final pathContext = _pathContext(deps.platform);

  if (pathContext.isAbsolute(executable) && deps.fileExists(executable)) {
    return executable;
  }

  final lookup = _isWindowsPlatform(deps.platform) ? 'where' : 'which';
  final lookupResult = deps.runSync(lookup, [executable]);
  if (lookupResult.exitCode == 0) {
    final stdout = '${lookupResult.stdout ?? ''}';
    for (final line in stdout.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (deps.fileExists(trimmed)) {
        return trimmed;
      }
      return trimmed;
    }
  }

  if (_isWindowsPlatform(deps.platform)) {
    for (final candidate in windowsCandidates) {
      if (deps.fileExists(candidate)) {
        return candidate;
      }
    }
  }

  return null;
}

p.Context _pathContext(String platform) {
  return p.Context(
    style: _isWindowsPlatform(platform) ? p.Style.windows : p.Style.posix,
  );
}

bool _isWindowsPlatform(String platform) {
  return platform == 'windows' || platform == 'win32';
}