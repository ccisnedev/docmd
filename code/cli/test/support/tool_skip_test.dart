import 'package:test/test.dart';

import 'tool_skip.dart';

void main() {
  group('toolSkipReason', () {
    test('is false (run the test) when the tool is available', () {
      expect(toolSkipReason(available: true, tool: 'Pandoc'), isFalse);
    });

    test('names the tool in an explicit reason when unavailable', () {
      final reason = toolSkipReason(available: false, tool: 'Pandoc');
      expect(reason, isA<String>());
      expect(
        reason,
        contains('Pandoc is not installed (or not on PATH) on this machine'),
      );
    });
  });
}
