import 'package:test/test.dart';

import 'package:docmd_cli/src/render/front_matter.dart';

void main() {
  group('FrontMatter', () {
    test('reads the top-level scalars of the leading YAML block', () {
      final fm = FrontMatter.parse('''
---
title: "Tarea Académica 2"
lang: es-PE
number-sections: true
author: ["A", "B"]
---

# Body
''');
      expect(fm['title'], equals('Tarea Académica 2'));
      expect(fm['lang'], equals('es-PE'));
      expect(fm.flag('number-sections'), isTrue);
    });

    test('ignores nested keys, list items and the body', () {
      final fm = FrontMatter.parse('''
---
author:
  - name: A
    number-sections: true
header-includes: |
  number-sections: true
---
number-sections: true
''');
      expect(fm.flag('number-sections'), isFalse);
      expect(fm['name'], isNull);
    });

    test('is empty without a leading block', () {
      expect(FrontMatter.parse('# Title\n\n---\nnumber-sections: true\n---\n')
          .flag('number-sections'), isFalse);
      expect(FrontMatter.parse('').flag('number-sections'), isFalse);
    });

    test('reads YAML booleans the way pandoc does', () {
      for (final yes in ['true', 'True', 'yes', 'on']) {
        expect(FrontMatter.parse('---\nx: $yes\n---\n').flag('x'), isTrue,
            reason: yes);
      }
      for (final no in ['false', 'no', 'off', '"true"']) {
        expect(FrontMatter.parse('---\nx: $no\n---\n').flag('x'), isFalse,
            reason: no);
      }
    });

    // bibliography may be a scalar or a list; either way it is present.
    test('knows which keys are present, whatever their value', () {
      bool has(String yaml) =>
          FrontMatter.parse('---\n$yaml---\n').has('bibliography');

      expect(has('bibliography: a.bib\n'), isTrue);
      expect(has('bibliography:\n  - a.bib\n  - b.bib\n'), isTrue);
      expect(has('title: x\n'), isFalse);
      expect(has('meta:\n  bibliography: a.bib\n'), isFalse);
    });

    test('accepts CRLF line endings and a "..." terminator', () {
      final fm = FrontMatter.parse('---\r\nnumber-sections: true\r\n...\r\n');
      expect(fm.flag('number-sections'), isTrue);
    });
  });
}
