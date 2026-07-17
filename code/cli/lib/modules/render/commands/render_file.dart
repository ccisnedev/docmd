library;

import 'dart:io';

import 'package:cli_router/cli_router.dart';
import 'package:modular_cli_sdk/modular_cli_sdk.dart';
import 'package:path/path.dart' as p;

import '../../../src/package_layout.dart';
import '../../../src/process_runner.dart';
import '../../../src/tool_locator.dart';

class RenderInput extends Input {
  final String inputPath;
  final String format;

  RenderInput({required this.inputPath, required this.format});

  factory RenderInput.fromCliRequest(CliRequest req) {
    return RenderInput(
      inputPath: req.params['input'] ?? '',
      format: req.flagBool('pdf')
          ? 'pdf'
          : req.flagBool('pptx')
              ? 'pptx'
              : 'docx',
    );
  }

  // docx and pptx are native pandoc writers; pdf is pandoc→LibreOffice. No
  // --xlsx: pandoc has no xlsx writer, so declaring it would only reject its
  // own use. It returns with a real renderer, not before.
  static final List<CliParam> params = [
    CliParam.positional(
      'input',
      description: 'Markdown file or DocMD package to render',
    ),
    CliParam.boolean('pdf', description: 'Render to PDF'),
    CliParam.boolean('pptx', description: 'Render to PPTX'),
  ];

  @override
  List<CliParam> get schemaFields => params;

  @override
  Map<String, dynamic> toJson() => {
    'inputPath': inputPath,
    'format': format,
  };
}

class RenderOutput extends Output {
  final String inputPath;
  final String sourceMarkdownPath;
  final String outputPath;
  final String format;
  final String status;

  RenderOutput({
    required this.inputPath,
    required this.sourceMarkdownPath,
    required this.outputPath,
    required this.format,
    required this.status,
  });

  @override
  Map<String, dynamic> toJson() => {
    'inputPath': inputPath,
    'sourceMarkdownPath': sourceMarkdownPath,
    'outputPath': outputPath,
    'format': format,
    'status': status,
  };

  @override
  int get exitCode => ExitCode.ok;

  @override
  String toText() {
    return [
      'DocMD render scaffold',
      '  input: $inputPath',
      '  source: $sourceMarkdownPath',
      '  output: $outputPath',
      '  format: $format',
      '  status: $status',
    ].join('\n');
  }
}

class RenderCommand implements Command<RenderInput, RenderOutput> {
  @override
  final RenderInput input;
  final ProcessRunner _runProcess;

  RenderCommand(this.input, {ProcessRunner? processRunner})
    : _runProcess = processRunner ?? runProcess;

  @override
  String? validate() {
    if (input.inputPath.isEmpty) {
      return 'Input path required. Use: docmd render <input>';
    }
    if (!File(input.inputPath).existsSync() &&
        !Directory(input.inputPath).existsSync()) {
      return 'Input path not found: ${input.inputPath}';
    }

    if (!_supportedFormats.contains(input.format)) {
      return 'Unsupported output format: ${input.format}';
    }

    if (Directory(input.inputPath).existsSync() &&
        !isDocmdPackagePath(input.inputPath)) {
      return 'Input directory is not a DocMD package: ${input.inputPath}';
    }

    final markdownSource = _resolveMarkdownSource();
    if (markdownSource == null) {
      return 'Render input must be a Markdown file or a DocMD package.';
    }

    return null;
  }

  @override
  Future<RenderOutput> execute() async {
    final markdownSource = _resolveMarkdownSource()!;
    final outputPath = _inferOutputPath(input.inputPath, input.format);

    switch (input.format) {
      case 'docx':
        await _renderViaPandoc(markdownSource, outputPath, to: 'docx');
      case 'pptx':
        await _renderViaPandoc(markdownSource, outputPath, to: 'pptx');
      default:
        await _renderToPdf(markdownSource, outputPath);
    }

    return RenderOutput(
      inputPath: input.inputPath,
      sourceMarkdownPath: markdownSource,
      outputPath: outputPath,
      format: input.format,
      status: 'rendered',
    );
  }

  String? _resolveMarkdownSource() {
    if (File(input.inputPath).existsSync()) {
      final extension = p.extension(input.inputPath).toLowerCase();
      if (extension == '.md' || extension == '.markdown') {
        return input.inputPath;
      }
      return null;
    }

    final layout = DocmdPackageLayout(input.inputPath);
    final canonicalDocument = File(layout.canonicalDocumentPath);
    if (canonicalDocument.existsSync()) {
      return canonicalDocument.path;
    }
    return null;
  }

  String _inferOutputPath(String inputPath, String format) {
    if (Directory(inputPath).existsSync()) {
      final layout = DocmdPackageLayout(inputPath);
      return p.join(layout.exportsDirPath, '${layout.packageName}.$format');
    }

    final parent = p.dirname(inputPath);
    final name = p.basenameWithoutExtension(inputPath);
    return p.join(parent, '$name.$format');
  }

  /// Renders through a native pandoc writer (docx, pptx). The resource path lets
  /// pandoc resolve the package's extracted media when embedding images.
  Future<void> _renderViaPandoc(
    String markdownSource,
    String outputPath, {
    required String to,
  }) async {
    Directory(p.dirname(outputPath)).createSync(recursive: true);

    final result = await _runProcess('pandoc', [
      markdownSource,
      '-f',
      'markdown',
      '-t',
      to,
      '--resource-path',
      _resourcePathFor(markdownSource),
      '-o',
      outputPath,
    ]);

    if (result.exitCode != 0) {
      throw ProcessException(
        'pandoc',
        [],
        'Pandoc render failed with exit code ${result.exitCode}: ${result.stderr}',
        result.exitCode,
      );
    }
  }

  Future<void> _renderToPdf(String markdownSource, String outputPath) async {
    final tempDir = Directory.systemTemp.createTempSync('docmd_render_');
    final tempDocxPath = p.join(
      tempDir.path,
      '${p.basenameWithoutExtension(outputPath)}.docx',
    );

    try {
      await _renderViaPandoc(markdownSource, tempDocxPath, to: 'docx');

      final outputDir = p.dirname(outputPath);
      Directory(outputDir).createSync(recursive: true);

      final sofficeExecutable = resolveLibreOfficeExecutable() ??
          (Platform.isWindows ? 'soffice.exe' : 'soffice');
      final result = await _runProcess(sofficeExecutable, [
        '--headless',
        '--convert-to',
        'pdf',
        tempDocxPath,
        '--outdir',
        outputDir,
      ]);

      if (result.exitCode != 0) {
        throw ProcessException(
          sofficeExecutable,
          [],
          'LibreOffice PDF render failed with exit code ${result.exitCode}: ${result.stderr}',
          result.exitCode,
        );
      }

      final generatedPdf = p.join(
        outputDir,
        '${p.basenameWithoutExtension(tempDocxPath)}.pdf',
      );

      if (!File(generatedPdf).existsSync()) {
        throw StateError('Expected rendered PDF was not created: $generatedPdf');
      }
    } finally {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
  }

  String _resourcePathFor(String markdownSource) {
    final sourceDir = p.dirname(markdownSource);
    final paths = <String>{sourceDir};

    final packageRoot = p.dirname(sourceDir);
    if (File(p.join(packageRoot, 'manifest.yaml')).existsSync()) {
      paths.add(packageRoot);
    }

    return paths.join(Platform.isWindows ? ';' : ':');
  }
}

const Set<String> _supportedFormats = {'docx', 'pptx', 'pdf'};
