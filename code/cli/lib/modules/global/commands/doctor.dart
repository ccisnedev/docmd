library;

import 'package:modular_cli_sdk/modular_cli_sdk.dart';

import '../../../src/ingestion/ingestion_registry.dart';
import '../../../src/ingestion/markdown_passthrough_backend.dart';
import '../../../src/ingestion/pandoc_docx_backend.dart';
import '../../../src/ingestion/pdf_backend.dart';
import '../../../src/ingestion/placeholder_backend.dart';
import '../../../src/ingestion/pptx_backend.dart';
import '../../../src/tool_locator.dart';

/// Contributes docmd's own doctor checks (Pandoc and LibreOffice
/// availability, plus one check per import/render capability) to the `doctor.checks` extension point [DoctorPlugin]
/// declares. `doctor` itself is owned entirely by `modular_cli_sdk`'s own
/// [DoctorPlugin]; this plugin only adds the two checks that are specific to
/// docmd's own import/render tooling.
class DocmdDoctorChecksPlugin implements CliPlugin {
  DocmdDoctorChecksPlugin({
    String? Function()? resolvePandocExecutable,
    String? Function()? resolveLibreOfficeExecutable,
  }) : _resolvePandocExecutable =
           resolvePandocExecutable ?? resolvePandocExecutableDefault,
       _resolveLibreOfficeExecutable =
           resolveLibreOfficeExecutable ?? resolveLibreOfficeExecutableDefault;

  final String? Function() _resolvePandocExecutable;
  final String? Function() _resolveLibreOfficeExecutable;

  @override
  CliPluginManifest get manifest => const CliPluginManifest(
    id: 'docmd.doctor_checks',
    displayName: 'DocMD doctor checks',
    version: '1.0.0',
    hostApiVersion: '^$cliPluginHostApiVersion',
    requires: ['modular_cli.doctor'],
  );

  @override
  void setup(CliPluginHost host) {
    host.contribute<CliDoctorCheck>(
      DoctorPlugin.extensionPoint,
      CliDoctorCheck(name: 'pandoc', run: _checkPandoc),
    );
    host.contribute<CliDoctorCheck>(
      DoctorPlugin.extensionPoint,
      CliDoctorCheck(name: 'libreoffice', run: _checkLibreOffice),
    );
    for (final name in _capabilityNames) {
      host.contribute<CliDoctorCheck>(
        DoctorPlugin.extensionPoint,
        CliDoctorCheck(name: name, run: () async => _checkCapability(name)),
      );
    }
  }

  static const List<String> _importFormats = [
    'md',
    'docx',
    'pdf',
    'pptx',
    'xlsx',
  ];

  static final List<String> _capabilityNames = [
    for (final format in _importFormats) 'import $format',
    'render docx',
    'render pdf',
  ];

  /// One import/render capability, projected from the installed tools
  /// exactly as origin/main's doctor did.
  ///
  /// Import capabilities are read straight from the ingestion registry, so
  /// this view cannot drift from the actual import routing. A capability a
  /// missing tool disables is a warning carrying that tool's install hint;
  /// one docmd itself has not wired yet (xlsx) is reported as unavailable
  /// but stays ok, since nothing on this machine can fix it.
  CliCheckResult _checkCapability(String name) {
    final pandocPath = _resolvePandocExecutable();
    final libreOfficePath = _resolveLibreOfficeExecutable();
    final hasPandoc = pandocPath != null;
    final hasLibreOffice = libreOfficePath != null;

    final String engine;
    final bool available;
    final String? hint;
    final bool fixableHere;
    switch (name) {
      case 'render docx':
        engine = 'pandoc';
        available = hasPandoc;
        hint = hasPandoc ? null : _pandocHint;
        fixableHere = true;
      case 'render pdf':
        engine = 'pandoc+libreoffice';
        available = hasPandoc && hasLibreOffice;
        hint = available
            ? null
            : [
                if (!hasPandoc) _pandocHint,
                if (!hasLibreOffice) _libreOfficeHint,
              ].join(' ');
        fixableHere = true;
      default:
        final format = name.substring('import '.length);
        final registry = IngestionRegistry([
          MarkdownPassthroughBackend(),
          PandocDocxBackend(isAvailable: () => hasPandoc),
          PdfIngestionBackend(),
          PptxIngestionBackend(),
          PlaceholderIngestionBackend(),
        ]);
        final backend = registry.backendFor(format)!;
        engine = backend.engineId;
        available = backend.isAvailable();
        hint = available ? null : _importHint(format);
        fixableHere = format == 'docx';
    }

    if (available) {
      return CliCheckResult(
        status: CliCheckStatus.ok,
        message: 'available ($engine)',
      );
    }
    final hintSuffix = hint == null ? '' : ': $hint';
    return CliCheckResult(
      status: fixableHere ? CliCheckStatus.warning : CliCheckStatus.ok,
      message: 'unavailable ($engine)$hintSuffix',
    );
  }

  static String? _importHint(String format) {
    switch (format) {
      case 'docx':
        return _pandocHint;
      case 'xlsx':
        return 'Real extraction is planned; a dedicated engine is not wired '
            'yet.';
      default:
        return null;
    }
  }

  static const String _pandocHint =
      'Install Pandoc: `docmd setup docx` (https://pandoc.org/installing.html)';
  static const String _libreOfficeHint =
      'Install LibreOffice: `docmd setup pdf` '
      '(https://www.libreoffice.org/download)';

  Future<CliCheckResult> _checkPandoc() async {
    final path = _resolvePandocExecutable();
    return path != null
        ? CliCheckResult(
            status: CliCheckStatus.ok,
            message: 'pandoc found at $path',
          )
        : const CliCheckResult(
            status: CliCheckStatus.error,
            message:
                'pandoc was not found. Install it: `docmd setup docx` '
                '(https://pandoc.org/installing.html)',
          );
  }

  Future<CliCheckResult> _checkLibreOffice() async {
    final path = _resolveLibreOfficeExecutable();
    return path != null
        ? CliCheckResult(
            status: CliCheckStatus.ok,
            message: 'libreoffice found at $path',
          )
        : const CliCheckResult(
            status: CliCheckStatus.error,
            message:
                'libreoffice was not found. Install it: `docmd setup pdf` '
                '(https://www.libreoffice.org/download)',
          );
  }
}

String? resolvePandocExecutableDefault() => resolvePandocExecutable();

String? resolveLibreOfficeExecutableDefault() => resolveLibreOfficeExecutable();
