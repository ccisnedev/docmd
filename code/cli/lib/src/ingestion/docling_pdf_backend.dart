library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../package_layout.dart';
import '../process_runner.dart';
import '../tool_locator.dart';
import 'ingestion_backend.dart';

/// Ingests PDF into Markdown using docling — the default PDF engine, chosen for
/// its layout analysis, table structure, and OCR (the capabilities that decide
/// the LLM-ingestion thesis).
///
/// docling's CLI writes `<stem>.md` into an `--output` directory and, in
/// `referenced` image mode, emits image artifacts alongside it. This backend
/// runs docling into a temporary directory, then relocates the produced
/// Markdown and every image artifact into the DocMD package, rewriting asset
/// references so they resolve from `content/document.md`.
class DoclingPdfBackend implements IngestionBackend {
  final ProcessRunner _runProcess;
  final bool Function() _isAvailable;

  DoclingPdfBackend({ProcessRunner? processRunner, bool Function()? isAvailable})
    : _runProcess = processRunner ?? runProcess,
      _isAvailable =
          isAvailable ?? (() => resolveDoclingExecutable() != null);

  @override
  String get engineId => 'docling';

  @override
  Set<String> get formats => const {'pdf'};

  @override
  bool isAvailable() => _isAvailable();

  @override
  bool get isFallback => false;

  @override
  Future<IngestionResult> ingest({
    required File source,
    required String format,
    required DocmdPackageLayout layout,
  }) async {
    final tempDir = Directory.systemTemp.createTempSync('docmd_docling_');
    try {
      final result = await _runProcess('docling', [
        source.path,
        '--to',
        'md',
        '--image-export-mode',
        'referenced',
        '--output',
        tempDir.path,
      ]);

      if (result.exitCode != 0) {
        throw ProcessException(
          'docling',
          [],
          'docling import failed with exit code ${result.exitCode}: ${result.stderr}',
          result.exitCode,
        );
      }

      final produced = _findMarkdown(tempDir);
      if (produced == null) {
        throw StateError('docling produced no Markdown in ${tempDir.path}');
      }

      var markdown = produced.readAsStringSync();
      final assetsDir = Directory(layout.assetsDirPath)
        ..createSync(recursive: true);

      // Relocate every non-Markdown entry (docling's image artifacts) into the
      // package assets and rewrite references. docling's artifact folder name is
      // version-dependent, so this derives the name from what was actually
      // written rather than hard-coding it.
      for (final entity in tempDir.listSync()) {
        if (p.equals(entity.path, produced.path)) continue;
        final name = p.basename(entity.path);
        _moveInto(entity, p.join(assetsDir.path, name));
        markdown = _rewriteAssetReferences(markdown, name);
      }

      File(layout.canonicalDocumentPath).writeAsStringSync(markdown);
      return const IngestionResult('converted');
    } finally {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
  }

  File? _findMarkdown(Directory dir) {
    for (final entity in dir.listSync()) {
      if (entity is File &&
          p.extension(entity.path).toLowerCase() == '.md') {
        return entity;
      }
    }
    return null;
  }

  void _moveInto(FileSystemEntity entity, String destination) {
    if (entity is Directory) {
      final dest = Directory(destination)..createSync(recursive: true);
      for (final child in entity.listSync(recursive: true)) {
        if (child is File) {
          final relative = p.relative(child.path, from: entity.path);
          final target = p.join(dest.path, relative);
          Directory(p.dirname(target)).createSync(recursive: true);
          child.copySync(target);
        }
      }
    } else if (entity is File) {
      Directory(p.dirname(destination)).createSync(recursive: true);
      entity.copySync(destination);
    }
  }

  String _rewriteAssetReferences(String markdown, String assetName) {
    return markdown
        .replaceAll('](./$assetName/', '](../assets/$assetName/')
        .replaceAll(']($assetName/', '](../assets/$assetName/')
        .replaceAll('](./$assetName)', '](../assets/$assetName)')
        .replaceAll(']($assetName)', '](../assets/$assetName)');
  }
}
