library;

import 'package:cli_router/cli_router.dart';
import 'package:modular_cli_sdk/modular_cli_sdk.dart';

import '../../../src/ingestion/ingestion_registry.dart';
import '../../../src/ingestion/markdown_passthrough_backend.dart';
import '../../../src/ingestion/pandoc_docx_backend.dart';
import '../../../src/ingestion/pdf_backend.dart';
import '../../../src/ingestion/placeholder_backend.dart';
import '../../../src/ingestion/pptx_backend.dart';
import '../../../src/tool_locator.dart';
import '../../../src/version.dart';
import '../../../src/version_check.dart';

class DoctorInput extends Input {
  DoctorInput();

  factory DoctorInput.fromCliRequest(CliRequest req) => DoctorInput();

  static const List<CliParam> params = [];

  @override
  List<CliParam> get schemaFields => params;

  @override
  Map<String, dynamic> toJson() => {};
}

/// A single import/render capability, projected from installed tools. This is
/// the per-capability view the roadmap calls for; the coarse [DoctorOutput.checks]
/// map is kept alongside for backward compatibility with the VS Code extension.
class Capability {
  final String direction; // 'import' | 'render'
  final String format; // 'docx', 'pdf', ...
  final String engine; // engineId or tool combination
  final bool available;
  final String? hint; // how to make it available, when it is not

  const Capability({
    required this.direction,
    required this.format,
    required this.engine,
    required this.available,
    this.hint,
  });

  Map<String, dynamic> toJson() => {
    'direction': direction,
    'format': format,
    'engine': engine,
    'available': available,
    if (hint != null) 'hint': hint,
  };
}

class DoctorOutput extends Output {
  final Map<String, bool> checks;
  final Map<String, String> paths;
  final List<Capability> capabilities;
  final String currentVersion;
  final String? latestVersion;
  final bool updateAvailable;

  DoctorOutput({
    required this.checks,
    required this.paths,
    required this.capabilities,
    required this.currentVersion,
    this.latestVersion,
    required this.updateAvailable,
  });

  @override
  Map<String, dynamic> toJson() => {
    'checks': checks,
    'paths': paths,
    'capabilities': capabilities.map((c) => c.toJson()).toList(),
    'currentVersion': currentVersion,
    if (latestVersion != null) 'latestVersion': latestVersion,
    'updateAvailable': updateAvailable,
  };

  @override
  int get exitCode => checks.values.every((value) => value) ? 0 : 1;

  @override
  String toText() {
    final lines = <String>[
      'DocMD prerequisite check',
      '  docmd: $currentVersion',
    ];

    if (latestVersion != null) {
      final versionStatus = updateAvailable
          ? 'UPDATE AVAILABLE ($latestVersion)'
          : 'up to date';
      lines.add('  update: $versionStatus');
    }

    for (final entry in checks.entries) {
      final status = entry.value ? 'OK' : 'MISSING';
      final pathSuffix = paths[entry.key] == null ? '' : ' (${paths[entry.key]})';
      lines.add('  ${entry.key}: $status$pathSuffix');
    }

    lines.add('');
    lines.add('Capabilities');
    for (final capability in capabilities) {
      final status = capability.available ? 'available' : 'unavailable';
      final hintSuffix =
          capability.available || capability.hint == null
          ? ''
          : ' — ${capability.hint}';
      lines.add(
        '  ${capability.direction} ${capability.format}: '
        '$status (${capability.engine})$hintSuffix',
      );
    }

    if (updateAvailable) {
      lines.add('');
      lines.add('Run `docmd upgrade` to install the latest release.');
    }

    if (!checks.values.every((value) => value)) {
      lines.add('');
      lines.add('Install the missing tools before using import and render workflows.');
    }

    return lines.join('\n');
  }
}

class DoctorCommand implements Command<DoctorInput, DoctorOutput> {
  @override
  final DoctorInput input;

  final String? Function() _resolvePandocExecutable;
  final String? Function() _resolveLibreOfficeExecutable;
  final Future<VersionCheckResult> Function({required String currentVersion}) _versionChecker;

  DoctorCommand(
    this.input, {
    String? Function()? resolvePandocExecutable,
    String? Function()? resolveLibreOfficeExecutable,
    Future<VersionCheckResult> Function({required String currentVersion})? versionChecker,
  }) : _resolvePandocExecutable = resolvePandocExecutable ?? resolvePandocExecutableDefault,
       _resolveLibreOfficeExecutable = resolveLibreOfficeExecutable ?? resolveLibreOfficeExecutableDefault,
       _versionChecker = versionChecker ?? checkLatestVersion;

  @override
  String? validate() => null;

  @override
  Future<DoctorOutput> execute() async {
    final pandocPath = _resolvePandocExecutable();
    final libreOfficePath = _resolveLibreOfficeExecutable();
    final versionResult = await _versionChecker(currentVersion: docmdVersion);

    return DoctorOutput(
      checks: {
        'pandoc': pandocPath != null,
        'libreoffice': libreOfficePath != null,
      },
      paths: {
        ...?(pandocPath == null ? null : {'pandoc': pandocPath}),
        ...?(libreOfficePath == null ? null : {'libreoffice': libreOfficePath}),
      },
      capabilities: _capabilities(
        pandocPath: pandocPath,
        libreOfficePath: libreOfficePath,
      ),
      currentVersion: docmdVersion,
      latestVersion: versionResult.latestVersion,
      updateAvailable: versionResult.updateAvailable,
    );
  }

  /// Per-capability import/render report, projected from installed tools.
  ///
  /// Import capabilities are read straight from the ingestion registry so this
  /// view cannot drift from the actual import routing; the registry is built
  /// with the same tool resolvers doctor uses, so a missing Pandoc marks
  /// `import docx` unavailable here exactly as it does at import time.
  List<Capability> _capabilities({
    required String? pandocPath,
    required String? libreOfficePath,
  }) {
    final registry = IngestionRegistry([
      MarkdownPassthroughBackend(),
      PandocDocxBackend(isAvailable: () => pandocPath != null),
      PdfIngestionBackend(),
      PptxIngestionBackend(),
      PlaceholderIngestionBackend(),
    ]);

    final capabilities = <Capability>[];

    for (final format in const ['md', 'docx', 'pdf', 'pptx', 'xlsx']) {
      final backend = registry.backendFor(format);
      if (backend == null) continue;
      final available = backend.isAvailable();
      capabilities.add(
        Capability(
          direction: 'import',
          format: format,
          engine: backend.engineId,
          available: available,
          hint: available ? null : _importHint(format),
        ),
      );
    }

    final hasPandoc = pandocPath != null;
    final hasLibreOffice = libreOfficePath != null;
    capabilities.add(
      Capability(
        direction: 'render',
        format: 'docx',
        engine: 'pandoc',
        available: hasPandoc,
        hint: hasPandoc ? null : _pandocHint,
      ),
    );
    capabilities.add(
      Capability(
        direction: 'render',
        format: 'pdf',
        engine: 'pandoc+libreoffice',
        available: hasPandoc && hasLibreOffice,
        hint: hasPandoc && hasLibreOffice
            ? null
            : [
                if (!hasPandoc) _pandocHint,
                if (!hasLibreOffice) _libreOfficeHint,
              ].join(' '),
      ),
    );

    return capabilities;
  }

  static String? _importHint(String format) {
    switch (format) {
      case 'docx':
        return _pandocHint;
      case 'xlsx':
        return 'Real extraction is planned; a dedicated engine is not wired yet.';
      default:
        return null;
    }
  }

  static const String _pandocHint =
      'Install Pandoc: `docmd setup docx` (https://pandoc.org/installing.html)';
  static const String _libreOfficeHint =
      'Install LibreOffice: `docmd setup pdf` (https://www.libreoffice.org/download)';
}

String? resolvePandocExecutableDefault() => resolvePandocExecutable();

String? resolveLibreOfficeExecutableDefault() => resolveLibreOfficeExecutable();
