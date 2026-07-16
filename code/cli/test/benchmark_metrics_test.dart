import 'package:test/test.dart';

import 'package:docmd_cli/src/benchmark/metrics.dart';

void main() {
  group('IngestionMetrics.fromMarkdown', () {
    const sample = '''
# Title

Some intro text with several words here.

## Section

| Name | Value |
| --- | --- |
| a | 1 |
| b | 2 |

![figure](../assets/fig.png)

More prose after the table.
''';

    final metrics = IngestionMetrics.fromMarkdown(sample);

    test('counts headings', () {
      expect(metrics.headings, equals(2));
    });

    test('counts a single table by its delimiter row', () {
      expect(metrics.tables, equals(1));
    });

    test('counts image references', () {
      expect(metrics.images, equals(1));
    });

    test('counts words, ignoring markdown punctuation', () {
      expect(metrics.words, greaterThan(0));
      // "Some intro text with several words here" -> at least these tokens.
      expect(tokenize('Some intro text').length, equals(3));
    });

    test('does not miscount a table row as its own table', () {
      const twoTables = '''
| a | b |
| - | - |
| 1 | 2 |

| c | d |
| :- | -: |
| 3 | 4 |
''';
      expect(IngestionMetrics.fromMarkdown(twoTables).tables, equals(2));
    });
  });

  group('textRecall', () {
    test('is 1.0 when the candidate contains all reference vocabulary', () {
      expect(textRecall('alpha beta gamma', 'gamma alpha beta delta'),
          equals(1.0));
    });

    test('is 0.5 when half the reference vocabulary is captured', () {
      expect(textRecall('alpha beta', 'alpha zzz'), equals(0.5));
    });

    test('is 0.0 when nothing is captured', () {
      expect(textRecall('alpha beta', 'nothing here'), equals(0.0));
    });

    test('is 1.0 for an empty reference', () {
      expect(textRecall('', 'anything'), equals(1.0));
    });

    test('ignores case and punctuation', () {
      expect(textRecall('Hello, WORLD!', 'hello world'), equals(1.0));
    });
  });
}
