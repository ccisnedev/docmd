library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../package_layout.dart';
import '../process_runner.dart';
import '../tool_locator.dart';
import 'ingestion_backend.dart';

/// Package-relative directory names, matching [DocmdPackageLayout].
const String _assetsDirName = 'assets';
const String _mediaDirName = 'media';

/// Converts `.docx` sources to GitHub-flavored Markdown via Pandoc, extracting
/// media into the package's assets directory and rewriting asset references so
/// they resolve from `content/document.md`.
class PandocDocxBackend implements IngestionBackend {
  final ProcessRunner _runProcess;
  final String? Function() _resolveExecutable;
  final bool Function() _isAvailable;

  PandocDocxBackend({
    ProcessRunner? processRunner,
    String? Function()? executableResolver,
    bool Function()? isAvailable,
  }) : _runProcess = processRunner ?? runProcess,
       _resolveExecutable = executableResolver ?? resolvePandocExecutable,
       _isAvailable =
           isAvailable ??
           (() => (executableResolver ?? resolvePandocExecutable)() != null);

  @override
  String get engineId => 'pandoc';

  @override
  Set<String> get formats => const {'docx'};

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
    // Run pandoc *inside* the package with a relative media dir. Passing an
    // absolute --extract-media makes pandoc write absolute, machine-specific
    // paths into the canonical document, which destroys package portability.
    final result = await _runProcess(
      _resolveExecutable() ?? 'pandoc',
      [
        source.path,
        '-t',
        'gfm',
        '--wrap=none',
        '--extract-media=$_assetsDirName',
        '-o',
        layout.canonicalDocumentPath,
      ],
      workingDirectory: layout.rootPath,
    );

    if (result.exitCode != 0) {
      throw ProcessException(
        'pandoc',
        [],
        'Pandoc import failed with exit code ${result.exitCode}: ${result.stderr}',
        result.exitCode,
      );
    }

    _normalizeCanonicalDocument(layout);
    return _accountForMedia(layout);
  }

  void _normalizeCanonicalDocument(DocmdPackageLayout layout) {
    final file = File(layout.canonicalDocumentPath);
    if (!file.existsSync()) {
      return;
    }

    var content = file.readAsStringSync();
    content = _rewriteImgTagsToMarkdown(content);
    content = _makeAssetReferencesRelative(content, layout);
    file.writeAsStringSync(content);
  }

  /// pandoc's gfm writer emits raw `<img>` for any image carrying width/height,
  /// and its docx writer silently drops raw HTML — so an `<img>` here means every
  /// image disappears on render. Markdown syntax survives the round trip; the
  /// size attributes do not, which is the deliberate trade.
  String _rewriteImgTagsToMarkdown(String content) {
    final imgTag = RegExp(r'''<img\s+[^>]*?src=["']([^"']+)["'][^>]*?/?>''');
    return content.replaceAllMapped(imgTag, (match) => '![](${match.group(1)})');
  }

  /// References must resolve from `content/document.md`, one level below the
  /// package root that assets sit in.
  String _makeAssetReferencesRelative(String content, DocmdPackageLayout layout) {
    final assetsPrefixes = <String>[
      // Absolute, in case a future pandoc resolves the media dir eagerly.
      '${layout.assetsDirPath}${Platform.pathSeparator}',
      '$_assetsDirName/',
      '$_assetsDirName\\',
    ];

    var normalized = content;
    for (final prefix in assetsPrefixes) {
      normalized = normalized.replaceAll('($prefix', '(../$_assetsDirName/');
      normalized = normalized.replaceAll('="$prefix', '="../$_assetsDirName/');
      normalized = normalized.replaceAll("='$prefix", "='../$_assetsDirName/");
    }
    // pandoc uses the platform separator inside the rewritten reference.
    return normalized.replaceAllMapped(
      RegExp(r'!\[\]\(\.\./' + _assetsDirName + r'/([^)]+)\)'),
      (match) => '![](../$_assetsDirName/${match.group(1)!.replaceAll('\\', '/')})',
    );
  }

  /// Counts what landed in assets versus what the document points at, so import
  /// can tell the user about fidelity loss instead of reporting a bare success.
  ///
  /// Scoped to the media directory on purpose: `assets/original/` holds the
  /// source document, which is stored deliberately and is not media.
  IngestionResult _accountForMedia(DocmdPackageLayout layout) {
    final mediaDir = Directory(p.join(layout.assetsDirPath, _mediaDirName));
    if (!mediaDir.existsSync()) {
      return const IngestionResult('converted');
    }

    final content = File(layout.canonicalDocumentPath).existsSync()
        ? File(layout.canonicalDocumentPath).readAsStringSync()
        : '';

    final extracted = mediaDir
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) =>
            p.relative(f.path, from: layout.assetsDirPath).replaceAll('\\', '/'))
        .toList()
      ..sort();

    final orphans = extracted
        .where((relative) => !content.contains(relative))
        .toList();

    return IngestionResult(
      'converted',
      mediaExtracted: extracted.length,
      mediaReferenced: extracted.length - orphans.length,
      orphanedMedia: orphans,
    );
  }
}
