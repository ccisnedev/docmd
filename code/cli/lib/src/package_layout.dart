library;

import 'dart:io';

import 'package:path/path.dart' as p;

class DocmdPackageLayout {
  final String rootPath;

  DocmdPackageLayout(this.rootPath);

  factory DocmdPackageLayout.forImportedFile(
    String inputPath, {
    String? outputDir,
  }) {
    final source = File(inputPath).absolute;
    final packageParentDir = outputDir == null
        ? source.parent.path
        : p.absolute(outputDir);
    return DocmdPackageLayout(
      p.join(
        packageParentDir,
        '${p.basenameWithoutExtension(source.path)}.docmd',
      ),
    );
  }

  String get manifestPath => p.join(rootPath, 'manifest.yaml');

  String get contentDirPath => p.join(rootPath, 'content');

  String get canonicalDocumentPath => p.join(contentDirPath, 'document.md');

  String get assetsDirPath => p.join(rootPath, 'assets');

  String get originalsDirPath => p.join(assetsDirPath, 'original');

  String get dataDirPath => p.join(rootPath, 'data');

  String get exportsDirPath => p.join(rootPath, 'exports');

  String get packageName => p.basenameWithoutExtension(rootPath);

  /// The `kind:` recorded in the manifest (`document`, `deck`, `sheet`), or null
  /// when there is no readable manifest. Read line-wise rather than through a
  /// YAML parser because [writeManifest] emits it as a flat top-level key, and
  /// the CLI stays dependency-free for it.
  String? get kind {
    final manifest = File(manifestPath);
    if (!manifest.existsSync()) {
      return null;
    }
    for (final line in manifest.readAsLinesSync()) {
      final match = _kindPattern.firstMatch(line);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }

  bool get exists => Directory(rootPath).existsSync();

  bool get isPackage => File(manifestPath).existsSync();

  void createSkeleton() {
    Directory(contentDirPath).createSync(recursive: true);
    Directory(assetsDirPath).createSync(recursive: true);
    Directory(originalsDirPath).createSync(recursive: true);
    Directory(dataDirPath).createSync(recursive: true);
    Directory(exportsDirPath).createSync(recursive: true);
  }

  void copyOriginalSource(File source) {
    source.copySync(p.join(originalsDirPath, p.basename(source.path)));
  }

  void writeManifest({
    required String kind,
    required String sourceFilename,
    required String sourceFormat,
    required String importStatus,
  }) {
    File(manifestPath).writeAsStringSync(
      _manifestText(
        kind: kind,
        sourceFilename: sourceFilename,
        sourceFormat: sourceFormat,
        importStatus: importStatus,
      ),
    );
  }

  String _manifestText({
    required String kind,
    required String sourceFilename,
    required String sourceFormat,
    required String importStatus,
  }) {
    final escapedFilename = sourceFilename.replaceAll('"', r'\"');

    return [
      'kind: $kind',
      'version: 0.0.1',
      'canonical:',
      '  entry: content/document.md',
      'source:',
      '  filename: "$escapedFilename"',
      '  format: $sourceFormat',
      'import:',
      '  status: $importStatus',
      'created_at: ${DateTime.now().toUtc().toIso8601String()}',
    ].join('\n');
  }
}

final RegExp _kindPattern = RegExp(r'^kind:\s*(\S+)\s*$');

bool isDocmdPackagePath(String inputPath) {
  return Directory(inputPath).existsSync() &&
      File(p.join(inputPath, 'manifest.yaml')).existsSync();
}
