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

bool isDocmdPackagePath(String inputPath) {
  return Directory(inputPath).existsSync() &&
      File(p.join(inputPath, 'manifest.yaml')).existsSync();
}
