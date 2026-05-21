import 'package:test/test.dart';

import 'package:docmd_cli/modules/global/commands/version.dart';
import 'package:docmd_cli/src/version.dart';

void main() {
  VersionCommand makeVersion() => VersionCommand(VersionInput());

  group('Version Command', () {
    test('output version matches docmdVersion constant', () async {
      final output = await makeVersion().execute();
      expect(output.version, equals(docmdVersion));
    });

    test('exitCode is 0', () async {
      final output = await makeVersion().execute();
      expect(output.exitCode, equals(0));
    });

    test('toJson() contains version key', () async {
      final output = await makeVersion().execute();
      final json = output.toJson();
      expect(json['version'], equals(docmdVersion));
    });
  });
}
