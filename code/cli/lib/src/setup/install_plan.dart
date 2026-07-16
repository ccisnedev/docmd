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

/// Capabilities a user can provision. `all` covers every engine; the others
/// scope provisioning to what a direction/format needs.
const Set<String> setupCapabilities = {'all', 'pdf', 'docx'};

/// Tools required per capability. PDF spans import (docling, bootstrapped by uv)
/// and render (pandoc + LibreOffice). Order is dependency-correct: uv precedes
/// the uv-installed tools.
const Map<String, List<String>> _capabilityTools = {
  'docx': ['pandoc'],
  'pdf': ['pandoc', 'libreoffice', 'uv', 'docling'],
  'all': ['pandoc', 'libreoffice', 'uv', 'docling', 'markitdown'],
};

/// Builds the ordered list of install steps for [capability] on [platform],
/// skipping any tool already reported present. Availability flags are injected
/// so the plan reflects the real machine without probing during planning.
List<InstallStep> buildSetupPlan({
  required String platform,
  required String capability,
  bool hasPandoc = false,
  bool hasLibreOffice = false,
  bool hasUv = false,
  bool hasDocling = false,
  bool hasMarkitdown = false,
}) {
  final os = _normalizePlatform(platform);
  final present = {
    'pandoc': hasPandoc,
    'libreoffice': hasLibreOffice,
    'uv': hasUv,
    'docling': hasDocling,
    'markitdown': hasMarkitdown,
  };

  final tools = _capabilityTools[capability] ?? const [];
  final steps = <InstallStep>[];
  for (final tool in tools) {
    if (present[tool] == true) continue;
    // docling/markitdown need uv; if uv is already present it won't be in the
    // list, which is fine — the uv-tool step still runs.
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
    case 'libreoffice':
      return _packageStep(
        tool: 'libreoffice',
        description: 'Office suite for PDF render and pptx/xlsx conversion',
        os: os,
        wingetId: 'TheDocumentFoundation.LibreOffice',
        brewArgs: ['install', '--cask', 'libreoffice'],
        aptPackage: 'libreoffice',
      );
    case 'uv':
      return _uvStep(os);
    case 'docling':
      return const InstallStep(
        tool: 'docling',
        description: 'Default PDF ingestion engine (layout, tables, OCR)',
        executable: 'uv',
        args: ['tool', 'install', 'docling'],
        display: 'uv tool install docling',
      );
    case 'markitdown':
      return const InstallStep(
        tool: 'markitdown',
        description: 'Lightweight PDF ingestion fallback',
        executable: 'uv',
        args: ['tool', 'install', 'markitdown[all]'],
        display: "uv tool install 'markitdown[all]'",
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
  required String aptPackage,
}) {
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
        args: ['apt-get', 'install', '-y', aptPackage],
        display: 'sudo apt-get install -y $aptPackage',
      );
  }
}

InstallStep _uvStep(String os) {
  if (os == 'windows') {
    return const InstallStep(
      tool: 'uv',
      description: 'Python tool runner that bootstraps docling/markitdown '
          '(no pre-existing Python required)',
      executable: 'powershell',
      args: ['-ExecutionPolicy', 'ByPass', '-c', 'irm https://astral.sh/uv/install.ps1 | iex'],
      display: 'powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"',
    );
  }
  return const InstallStep(
    tool: 'uv',
    description: 'Python tool runner that bootstraps docling/markitdown '
        '(no pre-existing Python required)',
    executable: 'sh',
    args: ['-c', 'curl -LsSf https://astral.sh/uv/install.sh | sh'],
    display: 'curl -LsSf https://astral.sh/uv/install.sh | sh',
  );
}

String _normalizePlatform(String platform) {
  if (platform == 'windows' || platform == 'win32') return 'windows';
  if (platform == 'macos' || platform == 'darwin') return 'macos';
  return 'linux';
}
