library;

import 'dart:convert';
import 'dart:io';

const String _repo = 'ccisnedev/docmd';

class VersionCheckResult {
  final String? latestVersion;
  final bool updateAvailable;
  final String? error;

  const VersionCheckResult({
    this.latestVersion,
    required this.updateAvailable,
    this.error,
  });
}

Future<VersionCheckResult> checkLatestVersion({
  required String currentVersion,
  HttpClient? httpClient,
}) async {
  final client = httpClient ?? HttpClient();

  try {
    client.connectionTimeout = const Duration(seconds: 5);

    final request = await client.getUrl(
      Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
    );
    request.headers.set('Accept', 'application/vnd.github+json');
    request.headers.set('User-Agent', 'docmd-cli/$currentVersion');

    final response = await request.close();
    if (response.statusCode != 200) {
      await response.drain<void>();
      return const VersionCheckResult(updateAvailable: false);
    }

    final body = await response.transform(utf8.decoder).join();
    final release = jsonDecode(body) as Map<String, dynamic>;
    final tagName = '${release['tag_name'] ?? ''}';
    final latestVersion = tagName.startsWith('v') ? tagName.substring(1) : tagName;

    return VersionCheckResult(
      latestVersion: latestVersion,
      updateAvailable: isNewerVersion(latestVersion, currentVersion),
    );
  } catch (_) {
    return const VersionCheckResult(updateAvailable: false);
  } finally {
    if (httpClient == null) {
      client.close();
    }
  }
}

bool isNewerVersion(String remote, String current) {
  final remoteParts = _parseSemver(remote);
  final currentParts = _parseSemver(current);
  if (remoteParts == null || currentParts == null) {
    return false;
  }

  if (remoteParts[0] != currentParts[0]) {
    return remoteParts[0] > currentParts[0];
  }
  if (remoteParts[1] != currentParts[1]) {
    return remoteParts[1] > currentParts[1];
  }
  return remoteParts[2] > currentParts[2];
}

List<int>? _parseSemver(String version) {
  final parts = version.split('.');
  if (parts.length != 3) {
    return null;
  }

  final parsed = parts.map(int.tryParse).toList();
  if (parsed.any((value) => value == null)) {
    return null;
  }

  return parsed.cast<int>();
}