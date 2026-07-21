import 'package:test/test.dart';

import 'package:docmd_cli/modules/global/commands/tui.dart';
import 'package:docmd_cli/src/version.dart';
import 'package:docmd_cli/src/version_check.dart';

void main() {
  group('TuiCommand (the default `docmd` summary)', () {
    test('shows the summary with no update line when up to date', () async {
      final output = await TuiCommand(
        TuiInput(),
        versionChecker: ({required currentVersion}) async =>
            const VersionCheckResult(updateAvailable: false),
      ).execute();

      expect(output.toText(), contains('DocMD CLI v$docmdVersion'));
      expect(output.toText(), isNot(contains('Update available')));
      expect(output.updateAvailable, isFalse);
    });

    // The gap this closes: on 0.2.0 a bare `docmd` gave no hint that a newer
    // release existed — you had to run `upgrade` to find out. The sibling
    // inquiry CLI surfaces it in its default view; docmd now does too.
    test('surfaces an available update in the summary', () async {
      final output = await TuiCommand(
        TuiInput(),
        versionChecker: ({required currentVersion}) async =>
            const VersionCheckResult(latestVersion: '9.9.9', updateAvailable: true),
      ).execute();

      expect(output.updateAvailable, isTrue);
      expect(output.latestVersion, equals('9.9.9'));
      final text = output.toText();
      expect(text, contains('Update available'));
      expect(text, contains('9.9.9'));
      expect(text, contains('docmd upgrade'));
    });

    // A version check reaches the network; it must never delay or break the
    // summary, which is printed on every bare `docmd`.
    test('is silent when the version check fails', () async {
      final output = await TuiCommand(
        TuiInput(),
        versionChecker: ({required currentVersion}) async =>
            throw Exception('offline'),
      ).execute();

      expect(output.toText(), contains('DocMD CLI v$docmdVersion'));
      expect(output.toText(), isNot(contains('Update available')));
      expect(output.updateAvailable, isFalse);
    });

    test('exposes the update state in JSON for tooling', () async {
      final output = await TuiCommand(
        TuiInput(),
        versionChecker: ({required currentVersion}) async =>
            const VersionCheckResult(latestVersion: '9.9.9', updateAvailable: true),
      ).execute();

      expect(output.toJson(), containsPair('updateAvailable', true));
      expect(output.toJson(), containsPair('latestVersion', '9.9.9'));
    });
  });
}
