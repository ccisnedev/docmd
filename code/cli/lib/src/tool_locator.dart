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

  return resolveExecutable(
    resolvedDeps.platform == 'windows' ? 'pandoc.exe' : 'pandoc',
    deps: resolvedDeps,
    windowsCandidates: [
      if ((resolvedDeps.programFiles ?? Platform.environment['ProgramFiles']) != null)
        p.join(
          resolvedDeps.programFiles ?? Platform.environment['ProgramFiles']!,
          'Pandoc',
          'pandoc.exe',
        ),
      if ((resolvedDeps.programFilesX86 ?? Platform.environment['ProgramFiles(x86)']) != null)
        p.join(
          resolvedDeps.programFilesX86 ?? Platform.environment['ProgramFiles(x86)']!,
          'Pandoc',
          'pandoc.exe',
        ),
    ],
  );
}

String? resolveLibreOfficeExecutable({ToolLocatorDeps? deps}) {
  final resolvedDeps = deps ?? ToolLocatorDeps();

  return resolveExecutable(
    resolvedDeps.platform == 'windows' ? 'soffice.exe' : 'soffice',
    deps: resolvedDeps,
    windowsCandidates: [
      if ((resolvedDeps.programFiles ?? Platform.environment['ProgramFiles']) != null)
        p.join(
          resolvedDeps.programFiles ?? Platform.environment['ProgramFiles']!,
          'LibreOffice',
          'program',
          'soffice.exe',
        ),
      if ((resolvedDeps.programFilesX86 ?? Platform.environment['ProgramFiles(x86)']) != null)
        p.join(
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
  if (p.isAbsolute(executable) && deps.fileExists(executable)) {
    return executable;
  }

  final lookup = deps.platform == 'windows' ? 'where' : 'which';
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

  if (deps.platform == 'windows') {
    for (final candidate in windowsCandidates) {
      if (deps.fileExists(candidate)) {
        return candidate;
      }
    }
  }

  return null;
}