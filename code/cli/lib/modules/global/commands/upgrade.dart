library;

import 'dart:convert';
import 'dart:io';

import 'package:cli_router/cli_router.dart';
import 'package:modular_cli_sdk/modular_cli_sdk.dart';
import 'package:path/path.dart' as p;

import '../../../src/platform/platform_ops.dart';
import '../../../src/version.dart';
import '../../../src/version_check.dart';

const String _repo = 'ccisnedev/docmd';
const String _latestReleaseUrl = 'https://api.github.com/repos/$_repo/releases/latest';

class UpgradeInput extends Input {
  UpgradeInput();

  factory UpgradeInput.fromCliRequest(CliRequest req) => UpgradeInput();

  static const List<CliParam> params = [];

  @override
  List<CliParam> get schemaFields => params;

  @override
  Map<String, dynamic> toJson() => {};
}

class UpgradeOutput extends Output {
  final String status;
  final String message;
  final String previousVersion;
  final String newVersion;
  final bool upgraded;
  final String? installPath;

  UpgradeOutput({
    required this.status,
    required this.message,
    required this.previousVersion,
    required this.newVersion,
    required this.upgraded,
    this.installPath,
  });

  @override
  Map<String, dynamic> toJson() => {
    'status': status,
    'message': message,
    'previousVersion': previousVersion,
    'newVersion': newVersion,
    'upgraded': upgraded,
    if (installPath != null) 'installPath': installPath,
  };

  @override
  int get exitCode => ExitCode.ok;

  @override
  String? toText() {
    if (!upgraded) {
      return message;
    }

    return 'Upgraded: $previousVersion -> $newVersion';
  }
}

typedef FetchReleaseJson = Future<Map<String, dynamic>> Function(
  String url,
  Map<String, String> headers,
);
typedef DownloadReleaseAsset = Future<void> Function(
  String url,
  String destPath,
  Map<String, String> headers,
);
typedef ExecFileText = Future<String> Function(String executable, List<String> arguments);
typedef DeletePath = Future<void> Function(String path);
typedef EnsureDirectory = Future<void> Function(String path);

class UpgradeDeps {
  final String platform;
  final String? localAppData;
  final String? homeDirectory;
  final String resolvedExecutable;
  final bool Function(String path) directoryExists;
  final FetchReleaseJson fetchJson;
  final DownloadReleaseAsset downloadFile;
  final ExecFileText execFile;
  final DeletePath deletePath;
  final EnsureDirectory ensureDirectory;
  final String Function() tempDirectoryPath;

  /// Every platform-varying operation — asset naming, extraction, the execute
  /// bit, the running-binary backup, and PATH linking. Null only when the
  /// platform is unsupported.
  final PlatformOps? platformOps;

  UpgradeDeps({
    String? platform,
    this.localAppData,
    this.homeDirectory,
    String? resolvedExecutable,
    bool Function(String path)? directoryExists,
    FetchReleaseJson? fetchJson,
    DownloadReleaseAsset? downloadFile,
    ExecFileText? execFile,
    DeletePath? deletePath,
    EnsureDirectory? ensureDirectory,
    String Function()? tempDirectoryPath,
    PlatformOps? platformOps,
  }) : platform = platform ?? Platform.operatingSystem,
       resolvedExecutable = resolvedExecutable ?? Platform.resolvedExecutable,
       directoryExists = directoryExists ?? ((path) => Directory(path).existsSync()),
       fetchJson = fetchJson ?? _fetchJson,
       downloadFile = downloadFile ?? _downloadFile,
       execFile = execFile ?? _execFile,
       deletePath = deletePath ?? _deletePath,
       ensureDirectory = ensureDirectory ?? _ensureDirectory,
       tempDirectoryPath = tempDirectoryPath ?? (() => Directory.systemTemp.path),
       platformOps = platformOps ??
           PlatformOps.forPlatform(platform ?? Platform.operatingSystem);
}

class UpgradeCommand implements Command<UpgradeInput, UpgradeOutput> {
  @override
  final UpgradeInput input;

  final UpgradeDeps _deps;

  UpgradeCommand(this.input, {UpgradeDeps? deps}) : _deps = deps ?? UpgradeDeps();

  @override
  String? validate() => null;

  @override
  Future<UpgradeOutput> execute() async {
    final paths = _pathContext(_deps.platform);
    final platformOps = _deps.platformOps;
    final installPath = _resolveManagedInstallPath(_deps);
    final binaryPath = _resolveManagedBinaryPath(_deps);

    if (platformOps == null || installPath == null || binaryPath == null) {
      throw UnsupportedError('Unsupported platform: ${_deps.platform}');
    }
    final assetName = platformOps.assetName;

    if (!_deps.directoryExists(installPath)) {
      return UpgradeOutput(
        status: 'absent',
        message: 'DocMD CLI is not installed in the managed directory.',
        previousVersion: docmdVersion,
        newVersion: docmdVersion,
        upgraded: false,
        installPath: installPath,
      );
    }

    stderr.writeln('Current version: $docmdVersion');
    stderr.writeln('Checking for updates...');

    final release = await _deps.fetchJson(
      _latestReleaseUrl,
      {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'docmd-cli/$docmdVersion',
      },
    );

    final tagName = '${release['tag_name'] ?? ''}';
    final latestVersion = tagName.startsWith('v') ? tagName.substring(1) : tagName;

    if (!isNewerVersion(latestVersion, docmdVersion)) {
      return UpgradeOutput(
        status: 'up-to-date',
        message: 'Already on the latest version.',
        previousVersion: docmdVersion,
        newVersion: docmdVersion,
        upgraded: false,
        installPath: installPath,
      );
    }

    final assets = (release['assets'] as List<dynamic>? ?? const <dynamic>[])
        .cast<Map<String, dynamic>>();
    final asset = assets.cast<Map<String, dynamic>?>().firstWhere(
      (candidate) => candidate?['name'] == assetName,
      orElse: () => null,
    );

    if (asset == null) {
      throw StateError('No $assetName asset found in release ${release['tag_name']}.');
    }

    final archivePath = paths.join(
      _deps.tempDirectoryPath(),
      'docmd-$latestVersion-${asset['name']}',
    );
    stderr.writeln('Downloading ${asset['name']}...');
    await _deps.downloadFile(
      '${asset['browser_download_url']}',
      archivePath,
      {'User-Agent': 'docmd-cli/$docmdVersion'},
    );

    // The install is entirely platform-polymorphic — every step below is a
    // no-op on the platform it does not apply to, so there is no OS branching
    // here. See PlatformOps.
    await platformOps.backupRunningBinary(
      binaryPath,
      runningExecutable: _deps.resolvedExecutable,
    );
    await _deps.ensureDirectory(installPath);
    await platformOps.expandArchive(archivePath, installPath);
    await platformOps.makeExecutable(binaryPath);
    await platformOps.linkIntoUserPath(binaryPath, userHome: _resolveHomeDirectory(_deps));

    await _deps.deletePath(archivePath);
    await platformOps.removeBackup(binaryPath);

    // Smoke-check that the freshly installed binary actually runs. Its output is
    // deliberately discarded: the version to report is the release tag, not this
    // command's text (`docmd version` prints a labelled "version: X", which would
    // otherwise leak into the upgrade message).
    await _deps.execFile(binaryPath, ['version']);

    return UpgradeOutput(
      status: 'upgraded',
      message: 'Upgraded from $docmdVersion to $latestVersion',
      previousVersion: docmdVersion,
      newVersion: latestVersion,
      upgraded: true,
      installPath: installPath,
    );
  }
}

String? _resolveManagedInstallPath(UpgradeDeps deps) {
  final paths = _pathContext(deps.platform);

  if (deps.platform == 'windows' || deps.platform == 'win32') {
    final localAppData = deps.localAppData ?? Platform.environment['LOCALAPPDATA'];
    if (localAppData == null || localAppData.isEmpty) {
      return null;
    }

    return paths.join(localAppData, 'docmd');
  }

  if (deps.platform == 'linux') {
    final home = _resolveHomeDirectory(deps);
    if (home == null) return null;
    return paths.join(home, '.docmd');
  }

  return null;
}

String? _resolveManagedBinaryPath(UpgradeDeps deps) {
  final paths = _pathContext(deps.platform);
  final installPath = _resolveManagedInstallPath(deps);
  if (installPath == null) {
    return null;
  }

  return paths.join(
    installPath,
    'bin',
    deps.platformOps?.binaryName ?? 'docmd',
  );
}

String? _resolveHomeDirectory(UpgradeDeps deps) {
  final home = deps.homeDirectory ??
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'];
  return (home == null || home.isEmpty) ? null : home;
}

p.Context _pathContext(String platform) {
  return p.Context(
    style: platform == 'windows' || platform == 'win32'
        ? p.Style.windows
        : p.Style.posix,
  );
}

Future<Map<String, dynamic>> _fetchJson(
  String url,
  Map<String, String> headers,
) async {
  final client = HttpClient();

  try {
    final request = await client.getUrl(Uri.parse(url));
    headers.forEach(request.headers.set);

    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('GitHub API request failed: HTTP ${response.statusCode}', uri: Uri.parse(url));
    }

    final body = await response.transform(utf8.decoder).join();
    return jsonDecode(body) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

Future<void> _downloadFile(
  String url,
  String destPath,
  Map<String, String> headers,
) async {
  final client = HttpClient();

  Future<void> downloadFrom(Uri uri) async {
    final request = await client.getUrl(uri);
    headers.forEach(request.headers.set);
    final response = await request.close();

    if (response.isRedirect && response.headers.value(HttpHeaders.locationHeader) != null) {
      await response.drain<void>();
      await downloadFrom(uri.resolve(response.headers.value(HttpHeaders.locationHeader)!));
      return;
    }

    if (response.statusCode != 200) {
      throw HttpException('Download failed: HTTP ${response.statusCode}', uri: uri);
    }

    final file = File(destPath)..createSync(recursive: true);
    final sink = file.openWrite();
    await response.pipe(sink);
    await sink.flush();
    await sink.close();
  }

  try {
    await downloadFrom(Uri.parse(url));
  } finally {
    client.close();
  }
}

Future<String> _execFile(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw ProcessException(executable, arguments, '${result.stderr}'.trim(), result.exitCode);
  }

  return '${result.stdout}'.trim();
}

Future<void> _deletePath(String path) async {
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
    return;
  }

  final directory = Directory(path);
  if (await directory.exists()) {
    await directory.delete(recursive: true);
  }
}

Future<void> _ensureDirectory(String path) async {
  await Directory(path).create(recursive: true);
}