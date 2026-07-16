library;

import 'dart:io';

import 'package:cli_router/cli_router.dart';
import 'package:modular_cli_sdk/modular_cli_sdk.dart';
import 'package:path/path.dart' as p;

import '../../../src/ingestion/ingestion_registry.dart';
import '../../../src/package_layout.dart';
import '../../../src/process_runner.dart';

class ImportInput extends Input {
  final String inputPath;
  final String? outputDir;
  final bool overwrite;
  final bool suffix;

  ImportInput({
    required this.inputPath,
    this.outputDir,
    this.overwrite = false,
    this.suffix = false,
  });

  factory ImportInput.fromCliRequest(CliRequest req) {
    final outputDir = req.flagString('output-dir') ?? req.flagString('output');

    return ImportInput(
      inputPath: req.params['input'] ?? '',
      outputDir: outputDir?.trim().isEmpty == true ? null : outputDir?.trim(),
      overwrite: req.flagBool('overwrite'),
      suffix: req.flagBool('suffix'),
    );
  }

  static final List<CliParam> params = [
    CliParam.positional('input', description: 'Path to the document to import'),
    CliParam.string(
      'output-dir',
      description: 'Directory to create the DocMD package in',
    ),
    CliParam.string('output', description: 'Alias of --output-dir'),
    CliParam.boolean('overwrite', description: 'Replace an existing package'),
    CliParam.boolean(
      'suffix',
      description: 'Create a numbered copy when the package already exists',
    ),
  ];

  @override
  List<CliParam> get schemaFields => params;

  @override
  Map<String, dynamic> toJson() => {
    'inputPath': inputPath,
    'outputDir': outputDir,
    'overwrite': overwrite,
    'suffix': suffix,
  };
}

class ImportOutput extends Output {
  final String inputPath;
  final String packagePath;
  final String manifestPath;
  final String canonicalDocumentPath;
  final String originalSourcePath;
  final String status;

  ImportOutput({
    required this.inputPath,
    required this.packagePath,
    required this.manifestPath,
    required this.canonicalDocumentPath,
    required this.originalSourcePath,
    required this.status,
  });

  @override
  Map<String, dynamic> toJson() => {
    'inputPath': inputPath,
    'packagePath': packagePath,
    'manifestPath': manifestPath,
    'canonicalDocumentPath': canonicalDocumentPath,
    'originalSourcePath': originalSourcePath,
    'status': status,
  };

  @override
  int get exitCode => ExitCode.ok;

  @override
  String toText() {
    return [
      'DocMD import scaffold',
      '  input: $inputPath',
      '  package: $packagePath',
      '  manifest: $manifestPath',
      '  document: $canonicalDocumentPath',
      '  status: $status',
    ].join('\n');
  }
}

class ImportCommand implements Command<ImportInput, ImportOutput> {
  @override
  final ImportInput input;
  final IngestionRegistry _registry;

  ImportCommand(
    this.input, {
    ProcessRunner? processRunner,
    IngestionRegistry? registry,
  }) : _registry =
           registry ?? IngestionRegistry.defaults(processRunner: processRunner);

  @override
  String? validate() {
    if (input.overwrite && input.suffix) {
      return 'Choose either --overwrite or --suffix when the target package already exists.';
    }

    if (input.inputPath.isEmpty) {
      return 'Input file required. Use: docmd import <input>';
    }
    final source = File(input.inputPath);
    if (!source.existsSync()) {
      return 'Input file not found: ${input.inputPath}';
    }

    final extension = p.extension(source.path).toLowerCase();
    if (!_supportedExtensions.contains(extension)) {
      return 'Unsupported input format: $extension';
    }

    if (input.outputDir != null && File(input.outputDir!).existsSync()) {
      return 'Output directory points to a file: ${input.outputDir}';
    }

    final layout = DocmdPackageLayout.forImportedFile(
      source.path,
      outputDir: input.outputDir,
    );
    if (layout.exists && !input.overwrite && !input.suffix) {
      return 'Package already exists: ${layout.rootPath}. Use --overwrite to replace it or --suffix to create a copy.';
    }

    return null;
  }

  @override
  Future<ImportOutput> execute() async {
    final source = File(input.inputPath).absolute;
    final layout = _resolveLayout(source.path);
    final sourceFormat = p.extension(source.path).toLowerCase().replaceFirst('.', '');

    if (input.overwrite && layout.exists) {
      Directory(layout.rootPath).deleteSync(recursive: true);
    }

    layout.createSkeleton();
    layout.copyOriginalSource(source);

    final backend = _registry.backendFor(sourceFormat);
    if (backend == null) {
      throw UnsupportedError('Unsupported import format: $sourceFormat');
    }
    final result = await backend.ingest(
      source: source,
      format: sourceFormat,
      layout: layout,
    );
    final status = result.status;

    layout.writeManifest(
      kind: _inferKind(sourceFormat),
      sourceFilename: p.basename(source.path),
      sourceFormat: sourceFormat,
      importStatus: status,
    );

    return ImportOutput(
      inputPath: input.inputPath,
      packagePath: layout.rootPath,
      manifestPath: layout.manifestPath,
      canonicalDocumentPath: layout.canonicalDocumentPath,
      originalSourcePath: p.join(layout.originalsDirPath, p.basename(source.path)),
      status: status,
    );
  }

  DocmdPackageLayout _resolveLayout(String sourcePath) {
    final baseLayout = DocmdPackageLayout.forImportedFile(
      sourcePath,
      outputDir: input.outputDir,
    );
    if (!input.suffix || !baseLayout.exists) {
      return baseLayout;
    }

    final parentDir = p.dirname(baseLayout.rootPath);
    final baseName = p.basenameWithoutExtension(baseLayout.rootPath);

    for (var index = 2; ; index += 1) {
      final candidate = DocmdPackageLayout(
        p.join(parentDir, '$baseName-$index.docmd'),
      );
      if (!candidate.exists) {
        return candidate;
      }
    }
  }

  String _inferKind(String sourceFormat) {
    switch (sourceFormat) {
      case 'pptx':
        return 'deck';
      case 'xlsx':
        return 'sheet';
      default:
        return 'document';
    }
  }
}

const Set<String> _supportedExtensions = {
  '.md',
  '.markdown',
  '.docx',
  '.pdf',
  '.pptx',
  '.xlsx',
};
