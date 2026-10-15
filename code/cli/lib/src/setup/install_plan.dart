library;

/// A single provisioning action: how to install one tool on the current OS.
class InstallStep {
  final String tool;
  final String description;

  /// Executable and arguments for the injected process runner.
  final String executable;
  final List<String> args;

  /// Human-facing command line, shown in the plan / dry-run output.
  final String display;

  const InstallStep({
    required this.tool,
    required this.description,
    required this.executable,
    required this.args,
    required this.display,
  });

  Map<String, dynamic> toJson() => {
    'tool': tool,
    'description': description,
    'command': display,
  };
}

/// Tools required per capability. Import is pure Dart (pdf/pptx) or Pandoc
/// (docx); the tools to provision are Pandoc — for docx import and all render —
/// and Typst, for PDF render (ADR 0003). LibreOffice is only the PDF fallback,
/// installed when named. No Python engines.
///
/// Every individual tool is also a capability: the root help advertises the tool
/// names, so the tool names have to be accepted, and naming one is how a user
/// repairs exactly the thing `doctor` told them about.
const Map<String, List<String>> _capabilityTools = {
  'docx': ['pandoc'],
  'pdf': ['pandoc', 'typst'],
  'all': ['pandoc', 'typst'],
  'pandoc': ['pandoc'],
  'typst': ['typst'],
  'libreoffice': ['libreoffice'],
};

/// Capabilities a user can provision, derived from the plans that exist so the
/// two can never drift apart.
final Set<String> setupCapabilities = _capabilityTools.keys.toSet();

/// Builds the ordered list of install steps for [capability] on [platform],
/// skipping any tool already reported present unless [force] is set. Availability
/// flags are injected so the plan reflects the real machine without probing
/// during planning.
List<InstallStep> buildSetupPlan({
  required String platform,
  required String capability,
  bool hasPandoc = false,
  bool hasLibreOffice = false,
  bool hasTypst = false,
  bool force = false,
}) {
  final os = _normalizePlatform(platform);
  final present = {
    'pandoc': hasPandoc,
    'libreoffice': hasLibreOffice,
    'typst': hasTypst,
  };

  final tools = _capabilityTools[capability] ?? const [];
  final steps = <InstallStep>[];
  for (final tool in tools) {
    if (!force && present[tool] == true) continue;
    steps.add(_stepFor(tool, os));
  }
  return steps;
}

InstallStep _stepFor(String tool, String os) {
  switch (tool) {
    case 'pandoc':
      return _packageStep(
        tool: 'pandoc',
        description: 'Document converter for docx/pptx import and render',
        os: os,
        wingetId: 'JohnMacFarlane.Pandoc',
        brewArgs: ['install', 'pandoc'],
        aptPackage: 'pandoc',
      );
    case 'typst':
      return _packageStep(
        tool: 'typst',
        description: 'Typesetter for PDF render',
        os: os,
        wingetId: 'Typst.Typst',
        brewArgs: ['install', 'typst'],
        // Not in apt on the common distributions; Typst's README points Linux
        // at the snap.
        linuxArgs: ['snap', 'install', 'typst'],
      );
    case 'libreoffice':
      return _packageStep(
        tool: 'libreoffice',
        description: 'Office suite, the PDF render fallback without Typst',
        os: os,
        wingetId: 'TheDocumentFoundation.LibreOffice',
        brewArgs: ['install', '--cask', 'libreoffice'],
        aptPackage: 'libreoffice',
      );
    default:
      throw ArgumentError('Unknown tool: $tool');
  }
}

InstallStep _packageStep({
  required String tool,
  required String description,
  required String os,
  required String wingetId,
  required List<String> brewArgs,
  String? aptPackage,
  List<String>? linuxArgs,
}) {
  final linux = linuxArgs ?? ['apt-get', 'install', '-y', aptPackage!];
  switch (os) {
    case 'windows':
      return InstallStep(
        tool: tool,
        description: description,
        executable: 'winget',
        args: ['install', '--exact', '--id', wingetId, '--source', 'winget'],
        display: 'winget install --exact --id $wingetId',
      );
    case 'macos':
      return InstallStep(
        tool: tool,
        description: description,
        executable: 'brew',
        args: brewArgs,
        display: 'brew ${brewArgs.join(' ')}',
      );
    default:
      return InstallStep(
        tool: tool,
        description: description,
        executable: 'sudo',
        args: linux,
        display: 'sudo ${linux.join(' ')}',
      );
  }
}

String _normalizePlatform(String platform) {
  if (platform == 'windows' || platform == 'win32') return 'windows';
  if (platform == 'macos' || platform == 'darwin') return 'macos';
  return 'linux';
}
