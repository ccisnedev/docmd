import 'dart:io';

import 'package:test/test.dart';

import 'package:docmd_cli/src/version.dart';

void main() {
  test('pubspec.yaml version matches version.dart', () {
    final pubspecFile = File('pubspec.yaml');
    expect(pubspecFile.existsSync(), isTrue, reason: 'pubspec.yaml must exist');

    final content = pubspecFile.readAsStringSync();
    final match = RegExp(r'^version:\s*([^\s]+)\s*$', multiLine: true).firstMatch(content);

    expect(match, isNotNull, reason: 'pubspec.yaml must declare a version');
    expect(
      match!.group(1),
      equals(docmdVersion),
      reason: 'pubspec.yaml version must match lib/src/version.dart',
    );
  });
}