library;

import 'dart:convert';
import 'dart:io';

import 'package:cli_router/cli_router.dart';
import 'package:modular_cli_sdk/modular_cli_sdk.dart';
import 'package:path/path.dart' as p;

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
typedef ExtractArchive = Future<void> Function(String archivePath, String destDir);
typedef ExecFileText = Future<String> Function(String executable, List<String> arguments);
typedef RenamePath = Future<void> Function(String fromPath, String toPath);
typedef DeletePath = Future<void> Function(String path);
typedef EnsureDirectory = Future<void> Function(String path);
typedef ChmodPath = Future<void> Function(String path, String mode);
typedef EnsureSymlink = Future<void> Function(String targetPath, String linkPath);

class UpgradeDeps {
  final String platform;
  final String? localAppData;
  final String? homeDirectory;
  final String resolvedExecutable;
  final bool Function(String path) directoryExists;
  final bool Function(String path) fileExists;
  final FetchReleaseJson fetchJson;
  final DownloadReleaseAsset downloadFile;
  final ExtractArchive extractZip;
  final ExtractArchive extractTarGz;
  final ExecFileText execFile;
  final RenamePath renamePath;
  final DeletePath deletePath;
  final EnsureDirectory ensureDirectory;
  final ChmodPath chmodPath;
  final EnsureSymlink ensureSymlink;
  final String Function() tempDirectoryPath;

  UpgradeDeps({
    String? platform,
    this.localAppData,
    this.homeDirectory,
    String? resolvedExecutable,
    bool Function(String path)? directoryExists,
    bool Function(String path)? fileExists,
    FetchReleaseJson? fetchJson,
    DownloadReleaseAsset? downloadFile,
    ExtractArchive? extractZip,
    ExtractArchive? extractTarGz,
    ExecFileText? execFile,
    RenamePath? renamePath,
    DeletePath? deletePath,
    EnsureDirectory? ensureDirectory,
    ChmodPath? chmodPath,
    EnsureSymlink? ensureSymlink,
    String Function()? tempDirectoryPath,
  }) : platform = platform ?? Platform.operatingSystem,
       resolvedExecutable = resolvedExecutable ?? Platform.resolvedExecutable,
       directoryExists = directoryExists ?? ((path) => Directory(path).existsSync()),
       fileExists = fileExists ?? ((path) => File(path).existsSync()),
       fetchJson = fetchJson ?? _fetchJson,
       downloadFile = downloadFile ?? _downloadFile,
       extractZip = extractZip ?? _extractZip,
       extractTarGz = extractTarGz ?? _extractTarGz,
       execFile = execFile ?? _execFile,
       renamePath = renamePath ?? _renamePath,
       deletePath = deletePath ?? _deletePath,
       ensureDirectory = ensureDirectory ?? _ensureDirectory,
       chmodPath = chmodPath ?? _chmodPath,
       ensureSymlink = ensureSymlink ?? _ensureSymlink,
       tempDirectoryPath = tempDirectoryPath ?? (() => Directory.systemTemp.path);
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
    final installPath = _resolveManagedInstallPath(_deps);
    final binaryPath = _resolveManagedBinaryPath(_deps);
    final assetName = _resolveAssetName(_deps.platform);

    if (installPath == null || binaryPath == null || assetName == null) {
      throw UnsupportedError('Unsupported platform: ${_deps.platform}');
    }

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

    final runningManagedBinary = _pathEquals(_deps.platform, _deps.resolvedExecutable, binaryPath);
    final backupPath = '$binaryPath.bak';

    if (_deps.platform == 'windows' && runningManagedBinary && _deps.fileExists(binaryPath)) {
      if (_deps.fileExists(backupPath)) {
        await _deps.deletePath(backupPath);
      }
      await _deps.renamePath(binaryPath, backupPath);
    }

    await _deps.ensureDirectory(installPath);
    if (_deps.platform == 'windows') {
      await _deps.extractZip(archivePath, installPath);
    } else {
      await _deps.extractTarGz(archivePath, installPath);
      await _deps.chmodPath(binaryPath, '755');

      final linkPath = paths.join(_requireHomeDirectory(_deps), '.local', 'bin', 'docmd');
      await _deps.ensureDirectory(paths.dirname(linkPath));
      await _deps.ensureSymlink(binaryPath, linkPath);
    }

    await _deps.deletePath(archivePath);

    if (_deps.platform == 'windows' && _deps.fileExists(backupPath)) {
      try {
        await _deps.deletePath(backupPath);
      } catch (_) {
        // Best-effort cleanup for a previously running executable.
      }
    }

    final installedVersion = (await _deps.execFile(binaryPath, ['version'])).trim();

    return UpgradeOutput(
      status: 'upgraded',
      message: 'Upgraded from $docmdVersion to $installedVersion',
      previousVersion: docmdVersion,
      newVersion: installedVersion,
      upgraded: true,
      installPath: installPath,
    );
  }
}

String? _resolveAssetName(String platform) {
  switch (platform) {
    case 'windows':
    case 'win32':
      return 'docmd-windows-x64.zip';
    case 'linux':
      return 'docmd-linux-x64.tar.gz';
    default:
      return null;
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
    return paths.join(_requireHomeDirectory(deps), '.docmd');
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
    deps.platform == 'windows' || deps.platform == 'win32' ? 'docmd.exe' : 'docmd',
  );
}

String _requireHomeDirectory(UpgradeDeps deps) {
  final homeDirectory = deps.homeDirectory ?? Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (homeDirectory == null || homeDirectory.isEmpty) {
    throw StateError('Unable to resolve the current user home directory.');
  }

  return homeDirectory;
}

bool _pathEquals(String platform, String a, String b) {
  if (platform == 'windows' || platform == 'win32') {
    return p.windows.normalize(a).toLowerCase() == p.windows.normalize(b).toLowerCase();
  }

  return p.posix.normalize(a) == p.posix.normalize(b);
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

Future<void> _extractZip(String archivePath, String destDir) async {
  final result = await Process.run('powershell', [
    '-NoProfile',
    '-Command',
    "Expand-Archive -Path '$archivePath' -DestinationPath '$destDir' -Force",
  ]);

  if (result.exitCode != 0) {
    throw ProcessException(
      'powershell',
      ['Expand-Archive', archivePath, destDir],
      '${result.stderr}'.trim(),
      result.exitCode,
    );
  }
}

Future<void> _extractTarGz(String archivePath, String destDir) async {
  final result = await Process.run('tar', ['xzf', archivePath, '-C', destDir]);
  if (result.exitCode != 0) {
    throw ProcessException('tar', ['xzf', archivePath, '-C', destDir], '${result.stderr}'.trim(), result.exitCode);
  }
}

Future<String> _execFile(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw ProcessException(executable, arguments, '${result.stderr}'.trim(), result.exitCode);
  }

  return '${result.stdout}'.trim();
}

Future<void> _renamePath(String fromPath, String toPath) async {
  await File(fromPath).rename(toPath);
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

Future<void> _chmodPath(String path, String mode) async {
  final result = await Process.run('chmod', [mode, path]);
  if (result.exitCode != 0) {
    throw ProcessException('chmod', [mode, path], '${result.stderr}'.trim(), result.exitCode);
  }
}

Future<void> _ensureSymlink(String targetPath, String linkPath) async {
  final link = Link(linkPath);
  if (await link.exists()) {
    await link.delete();
  } else {
    final file = File(linkPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  await link.create(targetPath, recursive: true);
}