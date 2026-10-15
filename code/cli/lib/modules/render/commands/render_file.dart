library;

import 'dart:io';

import 'package:cli_router/cli_router.dart';
import 'package:modular_cli_sdk/modular_cli_sdk.dart';
import 'package:path/path.dart' as p;

import '../../../src/package_layout.dart';
import '../../../src/process_runner.dart';
import '../../../src/render/front_matter.dart';
import '../../../src/tool_locator.dart';

class RenderInput extends Input {
  final String inputPath;
  final String format;

  RenderInput({required this.inputPath, required this.format});

  factory RenderInput.fromCliRequest(CliRequest req) {
    final inputPath = req.param('input') ?? '';
    final requested = req.flagBool('pdf')
        ? 'pdf'
        : req.flagBool('pptx')
            ? 'pptx'
            : req.flagBool('docx')
                ? 'docx'
                : null;

    return RenderInput(
      inputPath: inputPath,
      format: formatFor(inputPath, requested: requested),
    );
  }

  /// A deck renders back to a deck. Defaulting every package to docx turned
  /// `render` on an imported `.pptx` into a silent format change, and the
  /// extension had no way to ask for pptx at all. An explicit flag still wins.
  static String formatFor(String inputPath, {String? requested}) {
    if (requested != null) {
      return requested;
    }
    if (!isDocmdPackagePath(inputPath)) {
      return 'docx';
    }
    return _formatForKind[DocmdPackageLayout(inputPath).kind] ?? 'docx';
  }

  // docx and pptx are native pandoc writers; pdf is pandoc→Typst (LibreOffice as fallback). No
  // --xlsx: pandoc has no xlsx writer, so declaring it would only reject its
  // own use. It returns with a real renderer, not before.
  static final CliContract contract = CliContract(
    positionals: [
      CliPositional.string(
        'input',
        required: true,
        description: 'Markdown file or DocMD package to render',
      ),
    ],
    options: [
      CliParam.flag(
        'pdf',
        abbr: null,
        repeatable: false,
        description: 'Render to PDF',
      ),
      CliParam.flag(
        'pptx',
        abbr: null,
        repeatable: false,
        description: 'Render to PPTX',
      ),
      CliParam.flag(
        'docx',
        abbr: null,
        repeatable: false,
        description: 'Render to DOCX (the default, except for deck packages)',
      ),
    ],
  );

  @override
  Map<String, dynamic> toJson() => {'inputPath': inputPath, 'format': format};
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

class RenderCommand implements Query<RenderInput, RenderOutput> {
  @override
  final RenderInput input;
  final ProcessRunner _runProcess;
  final String? Function() _locateTypst;

  RenderCommand(
    this.input, {
    ProcessRunner? processRunner,
    String? Function()? typstLocator,
  }) : _runProcess = processRunner ?? runProcess,
       _locateTypst = typstLocator ?? resolveTypstExecutable;

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

  /// Renders through a native pandoc writer (docx, pptx, typst). The resource
  /// path lets pandoc resolve the package's extracted media when embedding
  /// images. Paths are made absolute so a [workingDirectory] cannot change
  /// what they point at.
  Future<void> _renderViaPandoc(
    String markdownSource,
    String outputPath, {
    required String to,
    List<String> extraArgs = const [],
    String? workingDirectory,
  }) async {
    Directory(p.dirname(outputPath)).createSync(recursive: true);
    final source = p.absolute(markdownSource);

    final result = await _runProcess('pandoc', [
      source,
      '-f',
      'markdown',
      '-t',
      to,
      ...extraArgs,
      ..._frontMatterArgs(source),
      '--resource-path',
      _resourcePathFor(source),
      '-o',
      p.absolute(outputPath),
    ], workingDirectory: workingDirectory);

    if (result.exitCode != 0) {
      throw ProcessException(
        'pandoc',
        [],
        'Pandoc render failed with exit code ${result.exitCode}: ${result.stderr}',
        result.exitCode,
      );
    }
  }

  /// PDF through pandoc's Typst writer and typst (ADR 0003): both outputs then
  /// come from the same pandoc AST. LibreOffice is the fallback when typst is
  /// not installed.
  Future<void> _renderToPdf(String markdownSource, String outputPath) async {
    final typst = _locateTypst();
    if (typst == null) {
      return _renderToPdfViaLibreOffice(markdownSource, outputPath);
    }
    // pandoc writes its intermediate .typ in the working directory, which may
    // be read-only (a shell started in C:\) and is never the package's to
    // litter: give it a scratch directory of its own.
    final scratch = Directory.systemTemp.createTempSync('docmd_render_');
    try {
      await _renderViaPandoc(
        markdownSource,
        outputPath,
        to: 'typst',
        extraArgs: [
          '--pdf-engine',
          typst,
          // pandoc extracts media to the temp dir and hands typst a
          // root-relative path to it (/Users/.../media-x/a.svg); typst reads
          // that against --root, which defaults to the working directory.
          '--pdf-engine-opt=--root=${p.rootPrefix(scratch.absolute.path)}',
        ],
        workingDirectory: scratch.path,
      );
    } finally {
      if (scratch.existsSync()) {
        scratch.deleteSync(recursive: true);
      }
    }
  }

  Future<void> _renderToPdfViaLibreOffice(
    String markdownSource,
    String outputPath,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync('docmd_render_');
    final tempDocxPath = p.join(
      tempDir.path,
      '${p.basenameWithoutExtension(outputPath)}.docx',
    );

    try {
      await _renderViaPandoc(markdownSource, tempDocxPath, to: 'docx');

      final outputDir = p.dirname(outputPath);
      Directory(outputDir).createSync(recursive: true);

      final sofficeExecutable =
          resolveLibreOfficeExecutable() ??
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
        throw StateError(
          'Expected rendered PDF was not created: $generatedPdf',
        );
      }
    } finally {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
  }

  /// Writer options pandoc reads only from the command line, taken from the
  /// source's front matter so every format gets the same ones (ADR 0003).
  List<String> _frontMatterArgs(String markdownSource) {
    final frontMatter = FrontMatter.parse(
      File(markdownSource).readAsStringSync(),
    );
    return [if (frontMatter.flag('number-sections')) '--number-sections'];
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

/// Package kind -> the format it renders back to by default. `sheet` is absent
/// because pandoc has no xlsx writer; it falls through to docx.
const Map<String?, String> _formatForKind = {'deck': 'pptx', 'document': 'docx'};
